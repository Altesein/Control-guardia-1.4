import '../models.dart';

/// Generates one night's rests and the 11 fixed-time patrols.
///
/// Rules used by this engine:
/// 1. Patrol hours are immutable: 20:00, 21:00 ... 06:00.
/// 2. A patrol is never assigned during an officer's configured rest.
/// 3. If a conflict around a rest is unavoidable, leaving the rest is much
///    more expensive than entering it, so the engine prefers the latter.
/// 4. Daily patrol totals are kept as even as possible.
/// 5. Weekly totals are used as the next fairness criterion.
/// 6. The 20:00 long patrol is balanced separately, without overriding the
///    rest and fixed-hour rules.
class AssignmentEngine {
  static const hours = [20, 21, 22, 23, 0, 1, 2, 3, 4, 5, 6];

  DailyPlan generate({
    required String date,
    required List<Officer> active,
    required Set<int> absentIds,
    required Set<int> unavailableIds,
    required Map<int, WeeklyStats> currentWeekStats,
    required Map<int, WeeklyStats> previousWeekStats,
    required List<RestBlock> restBlocks,
  }) {
    final available = active
        .where((o) =>
            !absentIds.contains(o.id) && !unavailableIds.contains(o.id))
        .toList();

    if (available.isEmpty) {
      return const DailyPlan(assignments: [], restByOfficer: {});
    }
    if (restBlocks.isEmpty) {
      throw StateError('Debe existir al menos un descanso configurado.');
    }

    final sizeOptions = _groupSizeOptions(available.length, restBlocks);
    final restByOfficer = _chooseRestGroups(
      available,
      sizeOptions,
      currentWeekStats,
      previousWeekStats,
    );

    final weeklyRoutes = <int, int>{
      for (final o in available) o.id!: currentWeekStats[o.id]?.routes ?? 0,
    };
    final weeklyLong = <int, int>{
      for (final o in available)
        o.id!: currentWeekStats[o.id]?.longRoutes ?? 0,
    };
    final dailyRoutes = <int, int>{for (final o in available) o.id!: 0};

    final assignments = <Assignment>[];

    for (final hour in hours) {
      final candidates = available
          .where((o) => !_isRestHour(hour, restByOfficer[o.id!]!, restBlocks))
          .toList();

      if (candidates.isEmpty) {
        throw StateError(
          'No hay un oficial disponible para el recorrido de las ${_label(hour)} sin violar un descanso.',
        );
      }

      candidates.sort((a, b) {
        final sa = _candidateScore(
          a,
          hour,
          restByOfficer,
          dailyRoutes,
          weeklyRoutes,
          weeklyLong,
          currentWeekStats,
          previousWeekStats,
          restBlocks,
        );
        final sb = _candidateScore(
          b,
          hour,
          restByOfficer,
          dailyRoutes,
          weeklyRoutes,
          weeklyLong,
          currentWeekStats,
          previousWeekStats,
          restBlocks,
        );

        for (var i = 0; i < sa.length; i++) {
          if (sa[i] != sb[i]) return sa[i].compareTo(sb[i]);
        }
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

      final officer = candidates.first;
      final longRoute = hour == 20;
      assignments.add(Assignment(
        date: date,
        officer: officer.name,
        hour: hour,
        longRoute: longRoute,
        restBlock: restByOfficer[officer.id!]!,
      ));

      dailyRoutes[officer.id!] = (dailyRoutes[officer.id!] ?? 0) + 1;
      weeklyRoutes[officer.id!] = (weeklyRoutes[officer.id!] ?? 0) + 1;
      if (longRoute) {
        weeklyLong[officer.id!] = (weeklyLong[officer.id!] ?? 0) + 1;
      }
    }

    assignments.sort((a, b) => _orderHour(a.hour).compareTo(_orderHour(b.hour)));
    return DailyPlan(assignments: assignments, restByOfficer: restByOfficer);
  }

  /// Lexicographic score. Lower is better.
  List<int> _candidateScore(
    Officer officer,
    int hour,
    Map<int, int> restByOfficer,
    Map<int, int> dailyRoutes,
    Map<int, int> weeklyRoutes,
    Map<int, int> weeklyLong,
    Map<int, WeeklyStats> current,
    Map<int, WeeklyStats> previous,
    List<RestBlock> restBlocks,
  ) {
    final id = officer.id!;
    final block = restByOfficer[id]!;

    // Exit transition (the first patrol at the exact end of a rest) is the
    // worst conflict. Entry transition (the patrol immediately before the
    // rest) is allowed when necessary and is deliberately a softer penalty.
    final transition = _transitionPenalty(hour, block, restBlocks);

    return [
      transition,
      dailyRoutes[id] ?? 0,
      weeklyRoutes[id] ?? 0,
      if (hour == 20) weeklyLong[id] ?? 0,
      current[id]?.longRoutes ?? 0,
      previous[id]?.routes ?? 0,
    ];
  }

  /// 0 = no transition conflict, 20 = entering rest, 1000 = leaving rest.
  int _transitionPenalty(int hour, int block, List<RestBlock> restBlocks) {
    final rest = restBlocks[block - 1];
    final current = _isRestHour(hour, block, restBlocks);
    if (current) return 1 << 20;

    final nextHour = _nextHour(hour);
    if (_isRestHour(nextHour, block, restBlocks)) return 20;

    // Exact end of the rest is the most undesirable transition.
    if (_minutesForHour(hour) == _minutes(rest.end)) return 1000;
    return 0;
  }

  int _nextHour(int hour) {
    final index = hours.indexOf(hour);
    return index < 0 || index == hours.length - 1 ? hours.first : hours[index + 1];
  }

  bool _isRestHour(int hour, int block, List<RestBlock> blocks) {
    if (block < 1 || block > blocks.length) return false;
    final rest = blocks[block - 1];
    final start = _minutes(rest.start);
    final end = _minutes(rest.end);
    final value = _minutesForHour(hour);
    if (start == end) return false;
    if (start < end) return value >= start && value < end;
    return value >= start || value < end;
  }

  int _minutes(String value) {
    final parts = value.split(':');
    final h = int.tryParse(parts.first) ?? 0;
    final m = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    return h * 60 + m;
  }

  int _minutesForHour(int hour) => hour * 60;

  String _label(int hour) => '${hour.toString().padLeft(2, '0')}:00';

  List<List<int>> _groupSizeOptions(int count, List<RestBlock> restBlocks) {
    final enabled = restBlocks.where((b) => b.capacity > 0).toList();
    if (enabled.length > count) {
      throw StateError(
        'Hay ${enabled.length} descansos activos, pero solo hay $count oficiales disponibles.',
      );
    }

    final totalCapacity = enabled.fold<int>(0, (sum, b) => sum + b.capacity);
    if (totalCapacity < count) {
      throw StateError(
        'La capacidad total de los descansos ($totalCapacity) es menor que los $count oficiales disponibles. Ajusta la capacidad de los descansos.',
      );
    }

    final options = <List<int>>[];
    final current = List<int>.filled(enabled.length, 0);

    void enumerate(int index, int remaining) {
      if (index == enabled.length) {
        if (remaining == 0) options.add(List<int>.from(current));
        return;
      }

      final blocksLeft = enabled.length - index - 1;
      final maxHere = enabled[index].capacity < remaining
          ? enabled[index].capacity
          : remaining;
      for (var value = 1; value <= maxHere; value++) {
        final after = remaining - value;
        final maxRemaining = enabled
            .skip(index + 1)
            .fold<int>(0, (sum, b) => sum + b.capacity);
        if (after < blocksLeft || after > maxRemaining) continue;
        current[index] = value;
        enumerate(index + 1, after);
      }
    }

    enumerate(0, count);
    if (options.isEmpty) {
      throw StateError(
        'No existe una distribución válida para $count oficiales con las capacidades configuradas.',
      );
    }

    options.sort((a, b) {
      final aShared = a.where((v) => v > 1).length;
      final bShared = b.where((v) => v > 1).length;
      if (aShared != bShared) return aShared.compareTo(bShared);
      return a.join(',').compareTo(b.join(','));
    });

    return options.map((option) {
      final full = List<int>.filled(restBlocks.length, 0);
      var j = 0;
      for (var i = 0; i < restBlocks.length; i++) {
        if (restBlocks[i].capacity > 0) full[i] = option[j++];
      }
      return full;
    }).toList();
  }

  Map<int, int> _chooseRestGroups(
    List<Officer> officers,
    List<List<int>> sizeOptions,
    Map<int, WeeklyStats> current,
    Map<int, WeeklyStats> previous,
  ) {
    final candidates = <Map<int, int>>[];

    for (final sizes in sizeOptions) {
      void enumerate(int group, List<int> remaining, Map<int, int> assignment) {
        if (group == sizes.length) {
          candidates.add(Map<int, int>.from(assignment));
          return;
        }
        _combinations(remaining, sizes[group], (chosen) {
          final chosenSet = chosen.toSet();
          final next = remaining.where((id) => !chosenSet.contains(id)).toList();
          for (final id in chosen) assignment[id] = group + 1;
          enumerate(group + 1, next, assignment);
          for (final id in chosen) assignment.remove(id);
        });
      }

      enumerate(0, officers.map((o) => o.id!).toList(), <int, int>{});
    }

    candidates.sort((a, b) {
      final sa = _restFairnessScore(a, current, previous);
      final sb = _restFairnessScore(b, current, previous);
      for (var i = 0; i < sa.length; i++) {
        if (sa[i] != sb[i]) return sa[i].compareTo(sb[i]);
      }
      return _signature(a).compareTo(_signature(b));
    });

    return candidates.first;
  }

  List<int> _restFairnessScore(
    Map<int, int> assignment,
    Map<int, WeeklyStats> current,
    Map<int, WeeklyStats> previous,
  ) {
    final values = <int>[];
    for (final e in assignment.entries) {
      values.add(current[e.key]?.restCount(e.value) ?? 0);
    }
    values.sort();
    final previousValues = assignment.entries
        .map((e) => previous[e.key]?.restCount(e.value) ?? 0)
        .toList()
      ..sort();
    return [...values, ...previousValues];
  }

  void _combinations(
    List<int> source,
    int choose,
    void Function(List<int>) callback,
  ) {
    final picked = <int>[];
    void visit(int start) {
      if (picked.length == choose) {
        callback(List<int>.from(picked));
        return;
      }
      final needed = choose - picked.length;
      for (var i = start; i <= source.length - needed; i++) {
        picked.add(source[i]);
        visit(i + 1);
        picked.removeLast();
      }
    }
    visit(0);
  }

  String _signature(Map<int, int> assignment) {
    final entries = assignment.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return entries.map((e) => '${e.key}:${e.value}').join('|');
  }

  int _orderHour(int hour) => hour >= 20 ? hour : hour + 24;
}
