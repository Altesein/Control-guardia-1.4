import '../models.dart';
import 'assignment_engine.dart';
import 'db.dart';

class WeeklyGenerator {
  final AppDb db;
  final AssignmentEngine engine;

  WeeklyGenerator({AppDb? db, AssignmentEngine? engine})
      : db = db ?? AppDb.instance,
        engine = engine ?? AssignmentEngine();

  Future<WeeklyGenerationResult> generate({
    required DateTime monday,
    required List<Officer> officers,
  }) async {
    final active = officers.where((o) => o.active).toList();
    final daysOffByOfficer = await db.weeklyDaysOffForOfficers(
      active.where((o) => o.id != null).map((o) => o.id!).toList(),
    );
    final currentStats = <int, WeeklyStats>{
      for (final o in active) o.id!: const WeeklyStats(),
    };
    final previousStats = await db.weeklyStats(
      _weekKey(monday.subtract(const Duration(days: 7))),
    );

    final result = <String, List<Assignment>>{};
    final rests = <String, Map<int, int>>{};
    final blocksByDay = <String, List<RestBlock>>{};
    final profilesByDay = <String, int>{};

    for (var d = 0; d < 7; d++) {
      final date = monday.add(Duration(days: d));
      final iso = _iso(date);
      final absent = await db.absentIds(iso);
      final dayOffIds = active
          .where((o) => daysOffByOfficer[o.id]?.contains(date.weekday) ?? false)
          .map((o) => o.id!)
          .toSet();
      final availableCount = active.where((o) {
        return !absent.contains(o.id) && !dayOffIds.contains(o.id);
      }).length;

      if (availableCount == 0) {
        result[iso] = [];
        rests[iso] = {};
        blocksByDay[iso] = [];
        profilesByDay[iso] = 0;
        continue;
      }

      // Each day selects the configuration for the number of officers actually
      // available that day. Profiles are independent: changing the 4-officer
      // profile never changes the 3- or 5-officer profile.
      final profile = await db.restProfile(availableCount);
      blocksByDay[iso] = profile.blocks;
      profilesByDay[iso] = availableCount;

      final plan = engine.generate(
        date: iso,
        active: active,
        absentIds: absent,
        unavailableIds: dayOffIds,
        currentWeekStats: currentStats,
        previousWeekStats: previousStats,
        restBlocks: profile.blocks,
      );

      final forbiddenIds = {...dayOffIds, ...absent};
      final officerByName = {for (final o in active) o.name: o};
      if (plan.assignments.any((a) => forbiddenIds.contains(officerByName[a.officer]?.id))) {
        throw StateError('Se intentó asignar un recorrido a un oficial ausente o en su día libre.');
      }

      for (final entry in plan.restByOfficer.entries) {
        final old = currentStats[entry.key] ?? const WeeklyStats();
        final counts = List<int>.from(old.restCounts);
        while (counts.length < profile.blocks.length) counts.add(0);
        counts[entry.value - 1]++;
        currentStats[entry.key] = WeeklyStats(
          routes: old.routes,
          longRoutes: old.longRoutes,
          restCounts: counts,
        );
      }

      for (final a in plan.assignments) {
        final officer = officerByName[a.officer];
        if (officer == null || officer.id == null) continue;
        final old = currentStats[officer.id] ?? const WeeklyStats();
        currentStats[officer.id!] = WeeklyStats(
          routes: old.routes + 1,
          longRoutes: old.longRoutes + (a.longRoute ? 1 : 0),
          restCounts: old.restCounts,
        );
      }

      result[iso] = plan.assignments;
      rests[iso] = plan.restByOfficer;
    }

    final ids = {for (final o in officers) if (o.id != null) o.name: o.id!};
    for (var d = 0; d < 7; d++) {
      final iso = _iso(monday.add(Duration(days: d)));
      await db.clearAssignmentsForDate(iso);
      await db.saveDailyRest(iso, rests[iso] ?? {});
      await db.saveAssignments(result[iso] ?? [], ids);
    }
    await db.saveWeeklyStats(_weekKey(monday), currentStats);

    return WeeklyGenerationResult(
      assignmentsByDay: result,
      restByDay: rests,
      daysOffByOfficer: daysOffByOfficer,
      restBlocksByDay: blocksByDay,
      officerCountByDay: profilesByDay,
    );
  }

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String _weekKey(DateTime d) => _iso(d);
}

class WeeklyGenerationResult {
  final Map<String, List<Assignment>> assignmentsByDay;
  final Map<String, Map<int, int>> restByDay;
  final Map<int, Set<int>> daysOffByOfficer;
  final Map<String, List<RestBlock>> restBlocksByDay;
  final Map<String, int> officerCountByDay;

  const WeeklyGenerationResult({
    required this.assignmentsByDay,
    required this.restByDay,
    required this.daysOffByOfficer,
    required this.restBlocksByDay,
    required this.officerCountByDay,
  });

  // Compatibility accessor for screens that only need one set of blocks.
  List<RestBlock> get restBlocks => restBlocksByDay.values.isEmpty
      ? const []
      : restBlocksByDay.values.first;
}
