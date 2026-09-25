import 'package:flutter/material.dart';
import '../models.dart';
import '../services/db.dart';
import '../services/weekly_generator.dart';
import '../services/export_service.dart';
import '../widgets/app_chrome.dart';
import 'history_screen.dart';

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  final GlobalKey _printKey = GlobalKey();
  final GlobalKey _availabilityPrintKey = GlobalKey();
  final GlobalKey _routesPrintKey = GlobalKey();
  final GlobalKey _personalPrintKey = GlobalKey();
  int? _personalReportOfficerId;

  DateTime monday = _monday(DateTime.now());
  Map<String, List<Assignment>> byDay = {};
  Map<String, Map<int, int>> restByDay = {};
  Map<int, Set<int>> daysOffByOfficer = {};
  List<Officer> officers = [];
  List<RestBlock> restBlocks = [];
  Map<String, List<RestBlock>> restBlocksByDay = {};
  bool generating = false;

  static const dayNames = [
    'Lunes',
    'Martes',
    'Miércoles',
    'Jueves',
    'Viernes',
    'Sábado',
    'Domingo',
  ];

  Color _hexColor(String hex) {
    final value = int.tryParse(hex.replaceFirst('#', ''), radix: 16);
    return value == null ? const Color(0xFF1565C0) : Color(0xFF000000 | value);
  }

  Color _officerColor(String name) {
    final officerIndex = officers.indexWhere((o) => o.name == name);
    if (officerIndex < 0) return const Color(0xFF1565C0);

    final officer = officers[officerIndex];
    if (officer.colorHex.trim().isNotEmpty) {
      return _hexColor(officer.colorHex.trim());
    }

    // Automatic colors deliberately skip colors already reserved manually.
    final manual = officers
        .map((o) => o.colorHex.trim().toUpperCase())
        .where((c) => c.isNotEmpty)
        .toSet();
    final usedAutomatic = <String>{};
    var automaticNumber = 0;
    for (final o in officers) {
      if (o.colorHex.trim().isNotEmpty) continue;
      String? chosen;
      for (final hex in OfficerColorPalette.hex) {
        final key = hex.toUpperCase();
        if (!manual.contains(key) && !usedAutomatic.contains(key)) {
          chosen = hex;
          break;
        }
      }
      chosen ??= OfficerColorPalette.hex[automaticNumber % OfficerColorPalette.hex.length];
      if (o.id == officer.id) return _hexColor(chosen);
      usedAutomatic.add(chosen.toUpperCase());
      automaticNumber++;
    }

    return const Color(0xFF1565C0);
  }

  static DateTime _monday(DateTime d) => DateTime(
        d.year,
        d.month,
        d.day,
      ).subtract(Duration(days: d.weekday - 1));

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  String _short(String s) =>
      s.length >= 10 ? '${s.substring(8, 10)}/${s.substring(5, 7)}' : s;

  String _day(DateTime d) =>
      '${dayNames[d.weekday - 1]} ${d.day}/${d.month}';

  Future<void> _load() async {
    final list = await AppDb.instance.officers();
    final map = await AppDb.instance.weeklyDaysOffForOfficers(
      list.where((o) => o.id != null).map((o) => o.id!).toList(),
    );
    final blocks = await AppDb.instance.restBlocks();

    final blocksByDay = <String, List<RestBlock>>{};

    final loadedByDay = <String, List<Assignment>>{};
    final loadedRest = <String, Map<int, int>>{};

    for (var i = 0; i < 7; i++) {
      final date = monday.add(Duration(days: i));
      final iso = _iso(date);
      final rows = await AppDb.instance.assignmentsForDate(iso);

      if (rows.isNotEmpty) {
        loadedByDay[iso] = rows
            .map(
              (r) => Assignment(
                date: iso,
                officer: r['name'] as String,
                hour: r['hour'] as int,
                longRoute: (r['long_route'] as int? ?? 0) == 1,
                restBlock: r['rest_block'] as int? ?? 0,
              ),
            )
            .toList();
      }

      final rests = await AppDb.instance.dailyRestForDate(iso);
      if (rests.isNotEmpty) loadedRest[iso] = rests;

      final absent = await AppDb.instance.absentIds(iso);
      final dayOffIds = list.where((o) => map[o.id]?.contains(date.weekday) ?? false).map((o) => o.id!).toSet();
      final availableCount = list.where((o) => o.active && !absent.contains(o.id) && !dayOffIds.contains(o.id)).length;
      if (availableCount > 0) {
        blocksByDay[iso] = (await AppDb.instance.restProfile(availableCount)).blocks;
      }
    }

    if (!mounted) return;

    setState(() {
      officers = list;
      daysOffByOfficer = map;
      restBlocks = blocks;
      restBlocksByDay = blocksByDay;
      byDay = loadedByDay;
      restByDay = loadedRest;
    });
  }

  Future<void> _generateWeek() async {
    setState(() => generating = true);

    try {
      final result = await WeeklyGenerator().generate(
        monday: monday,
        officers: officers,
      );

      if (!mounted) return;

      setState(() {
        byDay = result.assignmentsByDay;
        restByDay = result.restByDay;
        daysOffByOfficer = result.daysOffByOfficer;
        restBlocks = result.restBlocks;
        restBlocksByDay = result.restBlocksByDay;
        generating = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Programación actualizada respetando asistencia, días libres y descansos.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => generating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo generar la semana: $e')),
      );
    }
  }

  Future<void> _regenerateWeek() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Regenerar semana'),
        content: const Text(
          'Se generará nuevamente toda la programación de esta semana. Se volverán a calcular turnos, descansos y recorridos respetando las reglas configuradas. ¿Deseas continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Regenerar'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await _generateWeek();
    }
  }

  Future<void> _export() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '¿Qué deseas compartir?',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: kBrandNavy,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Selecciona el reporte que quieres enviar.',
                    style: TextStyle(color: Colors.black54),
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.bedtime_outlined),
                  ),
                  title: const Text(
                    'Horario de Turnos',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: const Text('Turnos de descanso de la semana'),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    await ExportService().shareWidget(
                      _printKey,
                      fileName: 'horario_turnos_semanal.png',
                      shareText: 'Horario semanal de turnos',
                    );
                  },
                ),
                ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.groups_2_outlined),
                  ),
                  title: const Text(
                    'Horario de Asistencia',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: const Text(
                    'Disponibilidad semanal de los oficiales',
                  ),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    await ExportService().shareWidget(
                      _availabilityPrintKey,
                      fileName: 'horario_asistencia_semanal.png',
                      shareText: 'Horario semanal de asistencia',
                    );
                  },
                ),
                ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.route_outlined),
                  ),
                  title: const Text(
                    'Horario de Recorridos',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: const Text(
                    'Programación semanal de recorridos',
                  ),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    await ExportService().shareWidget(
                      _routesPrintKey,
                      fileName: 'horario_recorridos_semanal.png',
                      shareText: 'Horario semanal de recorridos',
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _availabilityMatrix() => Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionTitle(
                title: 'Disponibilidad Semanal',
                subtitle: 'Los colores identifican a cada oficial.',
                icon: Icons.groups_2,
              ),
              const SizedBox(height: 12),
              if (officers.isEmpty)
                const Text('Todavía no hay oficiales registrados.')
              else
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Table(
                    defaultColumnWidth: const FixedColumnWidth(65),
                    columnWidths: const {0: FixedColumnWidth(110)},
                    border: TableBorder.all(
                      color: const Color(0xFFE0E4E7),
                    ),
                    children: [
                      TableRow(
                        decoration: const BoxDecoration(
                          color: Color(0xFFF1F4F6),
                        ),
                        children: [
                          _headerCell('Oficial'),
                          for (final day in dayNames) _headerCell(day),
                        ],
                      ),
                      for (final officer in officers)
                        TableRow(
                          children: [
                            Container(
                              height: 58,
                              alignment: Alignment.centerLeft,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 6),
                              child: Row(
                                children: [
                                  Container(
                                    width: 8,
                                    height: 30,
                                    decoration: BoxDecoration(
                                      color: _officerColor(officer.name),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      officer.name,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: officer.active
                                            ? null
                                            : Colors.grey,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            for (var weekday = 1; weekday <= 7; weekday++)
                              _availabilityCell(
                                officer.active &&
                                    !(daysOffByOfficer[officer.id]
                                            ?.contains(weekday) ??
                                        false),
                                officer.active,
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );

  Widget _headerCell(String text) => Container(
        height: 48,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
        ),
      );

  Widget _availabilityCell(bool available, bool active) => SizedBox(
        height: 58,
        child: Center(
          child: Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: !active
                  ? Colors.grey.shade400
                  : available
                      ? Colors.green.shade500
                      : Colors.grey.shade400,
            ),
            child: Icon(
              available && active ? Icons.check : Icons.remove,
              size: 16,
              color: Colors.white,
            ),
          ),
        ),
      );

  Widget _restRich(int? block, List<RestBlock> blocks) {
    if (block == null || block == 0) {
      return const Text('Sin descanso asignado');
    }

    final String range;
    {
      final b = blocks.firstWhere(
        (x) => x.number == block,
        orElse: () => RestBlock(number: block, start: '--:--', end: '--:--'),
      );
      range = '${b.start}–${b.end}';
    }

    return RichText(
      text: TextSpan(
        style: const TextStyle(color: Colors.black54, fontSize: 13),
        children: [
          TextSpan(
            text: 'Turno N°$block',
            style: const TextStyle(
              color: kBrandNavy,
              fontWeight: FontWeight.w900,
            ),
          ),
          TextSpan(text: ' · $range'),
        ],
      ),
    );
  }

  Widget _dayCard(DateTime date) {
    final iso = _iso(date);
    final list = byDay[iso] ?? [];
    final rests = restByDay[iso] ?? {};

    final activeForDay = officers
        .where(
          (o) =>
              o.active &&
              !(daysOffByOfficer[o.id]?.contains(date.weekday) ?? false),
        )
        .toList();

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        initiallyExpanded: _iso(DateTime.now()) == iso,
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        childrenPadding: const EdgeInsets.only(bottom: 8),
        title: Row(
          children: [
            Expanded(
              child: Text(
                _day(date),
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
        subtitle: Text(
          '${list.length} recorridos · ${activeForDay.length} oficiales disponibles',
        ),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Descansos del Día',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
          for (final officer in officers.where((o) => o.active))
            ListTile(
              dense: true,
              leading: Container(
                width: 10,
                height: 34,
                decoration: BoxDecoration(
                  color: _officerColor(officer.name),
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              title: Text(
                officer.name,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle:
                  (daysOffByOfficer[officer.id]?.contains(date.weekday) ??
                          false)
                      ? const Text('Día Libre')
                      : _restRich(rests[officer.id], restBlocksByDay[iso] ?? restBlocks),
            ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Recorridos',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
          for (final a in list)
            ListTile(
              dense: true,
              leading: Container(
                width: 52,
                height: 34,
                decoration: BoxDecoration(
                  color: _officerColor(a.officer),
                  borderRadius: BorderRadius.circular(18),
                ),
                alignment: Alignment.center,
                child: Text(
                  '${a.hour.toString().padLeft(2, '0')}:00',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              title: Text(
                a.officer,
                style: TextStyle(
                  color: _officerColor(a.officer),
                  fontWeight: FontWeight.w800,
                ),
              ),
              subtitle: _restRich(a.restBlock, restBlocksByDay[iso] ?? restBlocks),
              trailing: a.longRoute
                  ? const Chip(
                      label: Text(
                        'LARGO',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    )
                  : null,
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: buildBrandAppBar(
            context,
            'Programación',
            actions: [
              IconButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const HistoryScreen(),
                  ),
                ),
                icon: const Icon(Icons.history),
                tooltip: 'Historial Semanal',
              ),
              IconButton(
                onPressed: _export,
                icon: const Icon(Icons.share, color: Colors.white),
                tooltip: 'Compartir Reporte',
              ),
            ],
          ),
          body: Stack(
            children: [
              // Reportes fuera del área visible: siguen teniendo un RenderObject
              // pintado para que ExportService pueda capturarlos, pero no aparecen
              // detrás de las pantallas.
              Positioned(
                left: -10000,
                top: 0,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 1000,
                      child: RepaintBoundary(
                        key: _printKey,
                        child: WeeklyRestMatrixReport(
                          officers: officers,
                          restByDay: restByDay,
                          daysOffByOfficer: daysOffByOfficer,
                          restBlocksByDay: restBlocksByDay,
                          monday: monday,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 565,
                      child: RepaintBoundary(
                        key: _availabilityPrintKey,
                        child: Container(
                          color: Colors.white,
                          padding: const EdgeInsets.all(12),
                          child: WeeklyAvailabilityReport(
                            officers: officers,
                            daysOffByOfficer: daysOffByOfficer,
                            monday: monday,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 565,
                      child: RepaintBoundary(
                        key: _routesPrintKey,
                        child: Container(
                          color: Colors.white,
                          padding: const EdgeInsets.all(12),
                          child: WeeklyRoutesReport(
                            officers: officers,
                            assignmentsByDay: byDay,
                            monday: monday,
                          ),
                        ),
                      ),
                    ),
                    if (_personalReportOfficerId != null)
                      SizedBox(
                        width: 760,
                        child: RepaintBoundary(
                          key: _personalPrintKey,
                          child: Builder(
                            builder: (_) {
                              Officer? selectedOfficer;
                              for (final o in officers) {
                                if (o.id == _personalReportOfficerId) {
                                  selectedOfficer = o;
                                  break;
                                }
                              }
                              final officer = selectedOfficer;
                              if (officer == null) return const SizedBox.shrink();
                              return PersonalWeeklyReport(
                                officer: officer,
                                restByDay: restByDay,
                                daysOffByOfficer: daysOffByOfficer,
                                restBlocksByDay: restBlocksByDay,
                                monday: monday,
                              );
                            },
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Column(
                children: [
                  Container(
                    color: Theme.of(context).primaryColor,
                    child: const TabBar(
                      labelColor: Colors.white,
                      unselectedLabelColor: Colors.white70,
                      indicatorColor: Colors.white,
                      tabs: [
                        Tab(icon: Icon(Icons.today), text: 'Turno de Hoy'),
                        Tab(icon: Icon(Icons.calendar_month), text: 'Plan Semanal'),
                      ],
                    ),
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        ListView(
                          padding: const EdgeInsets.fromLTRB(12, 14, 12, 24),
                          children: [
                            const BrandBanner(
                              title: 'Turno Actual',
                              subtitle:
                                  'Muestra únicamente los recorridos y descansos programados para el día de hoy.',
                            ),
                            const SizedBox(height: 12),
                            _dayCard(DateTime.now()),
                          ],
                        ),
                        ListView(
                          padding: const EdgeInsets.fromLTRB(12, 14, 12, 24),
                          children: [
                            BrandBanner(
                              title: 'Plan Semanal',
                              subtitle: 'Distribución de recorridos y descansos según asistencia y días libres.',
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Semana Activa: ${_short(_iso(monday))} – ${_short(_iso(monday.add(const Duration(days: 6))))}',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: kBrandNavy,
                              ),
                            ),
                            const SizedBox(height: 10),
                            _availabilityMatrix(),
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              onPressed: generating ? null : _generateWeek,
                              icon: const Icon(Icons.auto_awesome),
                              label: Text(
                                generating
                                    ? 'Generando...'
                                    : 'Generar / Actualizar Semana',
                              ),
                            ),
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              onPressed: generating ? null : _regenerateWeek,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Regenerar Semana'),
                            ),
                            const SizedBox(height: 12),
                            if (byDay.isEmpty)
                              const Card(
                                child: Padding(
                                  padding: EdgeInsets.all(20),
                                  child: Text(
                                    'Todavía no hay una programación generada. Toca "Generar / Actualizar Semana".',
                                  ),
                                ),
                              ),
                            ...List.generate(
                              7,
                              (i) => _dayCard(monday.add(Duration(days: i))),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
}
