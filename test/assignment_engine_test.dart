import 'package:flutter_test/flutter_test.dart';
import 'package:control_guardias/models.dart';
import 'package:control_guardias/services/assignment_engine.dart';

void main() {
  List<Officer> officers(int count) => [
        for (var i = 1; i <= count; i++)
          Officer(id: i, name: 'Oficial $i'),
      ];

  test('genera exactamente los 11 recorridos en sus horas fijas', () {
    final plan = AssignmentEngine().generate(
      date: '2026-08-17',
      active: officers(5),
      absentIds: {},
      unavailableIds: {},
      currentWeekStats: {for (var i = 1; i <= 5; i++) i: const WeeklyStats()},
      previousWeekStats: const {},
      restBlocks: const [
        RestBlock(number: 1, start: '22:00', end: '00:00', capacity: 2),
        RestBlock(number: 2, start: '00:00', end: '02:00', capacity: 2),
        RestBlock(number: 3, start: '02:00', end: '04:00', capacity: 1),
      ],
    );

    expect(plan.assignments, hasLength(11));
    expect(
      plan.assignments.map((a) => a.hour).toList(),
      [20, 21, 22, 23, 0, 1, 2, 3, 4, 5, 6],
    );
  });

  test('la distribución diaria queda equilibrada', () {
    final plan = AssignmentEngine().generate(
      date: '2026-08-17',
      active: officers(5),
      absentIds: {},
      unavailableIds: {},
      currentWeekStats: {for (var i = 1; i <= 5; i++) i: const WeeklyStats()},
      previousWeekStats: const {},
      restBlocks: const [
        RestBlock(number: 1, start: '22:00', end: '00:00', capacity: 2),
        RestBlock(number: 2, start: '00:00', end: '02:00', capacity: 2),
        RestBlock(number: 3, start: '02:00', end: '04:00', capacity: 1),
      ],
    );

    final counts = <String, int>{};
    for (final a in plan.assignments) {
      counts[a.officer] = (counts[a.officer] ?? 0) + 1;
    }
    final values = counts.values.toList();
    expect(values.reduce((a, b) => a > b ? a : b) -
        values.reduce((a, b) => a < b ? a : b), lessThanOrEqualTo(1));
  });

  test('nunca asigna un recorrido dentro del descanso', () {
    final plan = AssignmentEngine().generate(
      date: '2026-08-17',
      active: officers(4),
      absentIds: {},
      unavailableIds: {},
      currentWeekStats: {for (var i = 1; i <= 4; i++) i: const WeeklyStats()},
      previousWeekStats: const {},
      restBlocks: const [
        RestBlock(number: 1, start: '22:00', end: '00:00', capacity: 1),
        RestBlock(number: 2, start: '00:00', end: '02:00', capacity: 2),
        RestBlock(number: 3, start: '02:00', end: '04:00', capacity: 1),
      ],
    );

    final byName = {for (final o in officers(4)) o.name: o.id!};
    for (final a in plan.assignments) {
      final id = byName[a.officer]!;
      final block = plan.restByOfficer[id]!;
      final rest = [
        const RestBlock(number: 1, start: '22:00', end: '00:00', capacity: 1),
        const RestBlock(number: 2, start: '00:00', end: '02:00', capacity: 2),
        const RestBlock(number: 3, start: '02:00', end: '04:00', capacity: 1),
      ][block - 1];
      final minute = a.hour * 60;
      final start = int.parse(rest.start.substring(0, 2)) * 60;
      final end = int.parse(rest.end.substring(0, 2)) * 60;
      final inside = start < end
          ? minute >= start && minute < end
          : minute >= start || minute < end;
      expect(inside, isFalse);
    }
  });

  test('oficiales no disponibles nunca reciben recorridos', () {
    final plan = AssignmentEngine().generate(
      date: '2026-08-17',
      active: officers(5),
      absentIds: {5},
      unavailableIds: {4},
      currentWeekStats: {for (var i = 1; i <= 5; i++) i: const WeeklyStats()},
      previousWeekStats: const {},
      restBlocks: const [
        RestBlock(number: 1, start: '22:00', end: '00:00', capacity: 2),
        RestBlock(number: 2, start: '00:00', end: '02:00', capacity: 2),
        RestBlock(number: 3, start: '02:00', end: '04:00', capacity: 1),
      ],
    );
    expect(plan.assignments.every((a) => a.officer != 'Oficial 4' && a.officer != 'Oficial 5'), isTrue);
  });
}
