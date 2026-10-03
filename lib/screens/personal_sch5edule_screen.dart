import 'package:flutter/material.dart';

import '../models.dart';
import '../services/db.dart';
import '../services/export_service.dart';
import '../widgets/app_chrome.dart';

class PersonalScheduleScreen extends StatefulWidget {
  const PersonalScheduleScreen({super.key});

  @override
  State<PersonalScheduleScreen> createState() => _PersonalScheduleScreenState();
}

class _PersonalScheduleScreenState extends State<PersonalScheduleScreen> {
  static const _days = [
    'LUN',
    'MAR',
    'MIÉ',
    'JUE',
    'VIE',
    'SÁB',
    'DOM',
  ];

  static const _months = [
    'enero',
    'febrero',
    'marzo',
    'abril',
    'mayo',
    'junio',
    'julio',
    'agosto',
    'septiembre',
    'octubre',
    'noviembre',
    'diciembre',
  ];

  static const _turnColors = [
    Color(0xFF0B63CE),
    Color(0xFF18A56B),
    Color(0xFFE58A00),
    Color(0xFF7A4CC2),
    Color(0xFFE34B67),
    Color(0xFF008B8B),
  ];

  DateTime _monday = _weekMonday(DateTime.now());
  List<Officer> _officers = [];
  int? _selectedOfficerId;
  final Map<String, Map<int, int>> _restByDay = {};
  final Map<String, List<RestBlock>> _blocksByDay = {};
  final Map<int, Set<int>> _daysOffByOfficer = {};
  bool _loading = true;
  final GlobalKey _reportKey = GlobalKey();
  final GlobalKey _turnsReportKey = GlobalKey();
  final GlobalKey _attendanceReportKey = GlobalKey();
  final GlobalKey _routesReportKey = GlobalKey();
  final ExportService _exportService = ExportService();
  Map<String, List<Assignment>> _assignmentsByDay = {};

  static DateTime _weekMonday(DateTime date) => DateTime(
        date.year,
        date.month,
        date.day,
      ).subtract(Duration(days: date.weekday - 1));

  String _iso(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    final officers = await AppDb.instance.officers();
    final active = officers.where((o) => o.active).toList();
    final ids = active.where((o) => o.id != null).map((o) => o.id!).toList();
    final daysOff = await AppDb.instance.weeklyDaysOffForOfficers(ids);

    final rest = <String, Map<int, int>>{};
    final blocks = <String, List<RestBlock>>{};
    final assignments = <String, List<Assignment>>{};

    final assignmentRows = await AppDb.instance.assignmentsForWeek(
      _iso(_monday),
      _iso(_monday.add(const Duration(days: 6))),
    );
    for (final row in assignmentRows) {
      final date = row['date'] as String;
      (assignments[date] ??= <Assignment>[]).add(
        Assignment(
          date: date,
          officer: row['name'] as String,
          hour: (row['hour'] as num).toInt(),
          longRoute: ((row['long_route'] as num?)?.toInt() ?? 0) == 1,
          restBlock: (row['rest_block'] as num?)?.toInt() ?? 0,
        ),
      );
    }

    for (var i = 0; i < 7; i++) {
      final date = _monday.add(Duration(days: i));
      final iso = _iso(date);
      rest[iso] = await AppDb.instance.dailyRestForDate(iso);

      final available = active.where((o) {
        final off = daysOff[o.id]?.contains(date.weekday) ?? false;
        return !off;
      }).length;
      if (available > 0) {
        blocks[iso] = (await AppDb.instance.restProfile(available)).blocks;
      }
    }

    if (!mounted) return;
    setState(() {
      _officers = active;
      _daysOffByOfficer
        ..clear()
        ..addAll(daysOff);
      _restByDay
        ..clear()
        ..addAll(rest);
      _blocksByDay
        ..clear()
        ..addAll(blocks);
      _assignmentsByDay = assignments;
      _selectedOfficerId = _selectedOfficerId != null &&
              active.any((o) => o.id == _selectedOfficerId)
          ? _selectedOfficerId
          : (active.isNotEmpty ? active.first.id : null);
      _loading = false;
    });
  }

  Officer? get _selectedOfficer {
    for (final officer in _officers) {
      if (officer.id == _selectedOfficerId) return officer;
    }
    return null;
  }

  int _weekNumber() {
    final firstThursday = DateTime(_monday.year, 1, 4);
    final firstMonday = _weekMonday(firstThursday);
    return (_monday.difference(firstMonday).inDays ~/ 7) + 1;
  }

  String _dateRange() {
    final sunday = _monday.add(const Duration(days: 6));
    return '${_monday.day.toString().padLeft(2, '0')} – '
        '${sunday.day.toString().padLeft(2, '0')} de '
        '${_months[sunday.month - 1]} de ${sunday.year}';
  }

  String _dayDate(DateTime date) =>
      '${_days[date.weekday - 1]} ${date.day.toString().padLeft(2, '0')}';

  Color _turnColor(int block) =>
      _turnColors[(block - 1).clamp(0, _turnColors.length - 1)];

  String _turnLabel(int block) {
    if (block <= 0) return 'SIN ASIGNAR';
    if (block == 1) return '1er TURNO';
    if (block == 2) return '2º TURNO';
    if (block == 3) return '3er TURNO';
    return '$blockº TURNO';
  }

  RestBlock? _blockFor(String iso, int block) {
    for (final item in _blocksByDay[iso] ?? const <RestBlock>[]) {
      if (item.number == block) return item;
    }
    return null;
  }

  Widget _turnChip({required int block, required String label}) {
    final color = _turnColor(block);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: color.withValues(alpha: 0.10)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.person, size: 18, color: color),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _dayRow(DateTime date, Officer officer) {
    final iso = _iso(date);
    final isDayOff =
        _daysOffByOfficer[officer.id]?.contains(date.weekday) ?? false;
    final block = _restByDay[iso]?[officer.id];
    final rest = block == null ? null : _blockFor(iso, block);

    if (isDayOff) {
      return _row(
        date: date,
        child: const Row(
          children: [
            Icon(Icons.nightlight_round, color: kBrandNavy, size: 21),
            SizedBox(width: 8),
            Text(
              'DESCANSO',
              style: TextStyle(
                color: kBrandNavy,
                fontWeight: FontWeight.w900,
                fontSize: 14,
              ),
            ),
          ],
        ),
        schedule: '—',
      );
    }

    if (block == null || block <= 0) {
      return _row(
        date: date,
        child: const Text(
          'SIN ASIGNAR',
          style: TextStyle(fontWeight: FontWeight.w800, color: Colors.black54),
        ),
        schedule: '—',
      );
    }

    final range = rest == null ? '—' : '${rest.start} – ${rest.end}';
    return _row(
      date: date,
      child: _turnChip(block: block, label: _turnLabel(block)),
      schedule: range,
    );
  }

  Widget _row({
    required DateTime date,
    required Widget child,
    required String schedule,
  }) {
    return Container(
      constraints: const BoxConstraints(minHeight: 66),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: const Color(0xFFE1E7ED)),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 82,
            child: Center(
              child: Text(
                _dayDate(date),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: kBrandNavy,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 8),
              child: Center(child: child),
            ),
          ),
          Expanded(
            flex: 2,
            child: Center(
              child: Text(
                schedule,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: kBrandNavy,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _scheduleTable(Officer officer) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            height: 45,
            color: kBrandNavy,
            child: const Row(
              children: [
                SizedBox(
                  width: 82,
                  child: Center(
                    child: Text(
                      'DÍA',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Center(
                    child: Text(
                      'TURNO',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Center(
                    child: Text(
                      'HORARIO',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          for (var i = 0; i < 7; i++)
            _dayRow(_monday.add(Duration(days: i)), officer),
        ],
      ),
    );
  }

  Widget _summary(Officer officer) {
    final counts = <int, int>{};
    for (var i = 0; i < 7; i++) {
      final date = _monday.add(Duration(days: i));
      if (_daysOffByOfficer[officer.id]?.contains(date.weekday) ?? false) {
        continue;
      }
      final block = _restByDay[_iso(date)]?[officer.id];
      if (block != null && block > 0) counts[block] = (counts[block] ?? 0) + 1;
    }

    final blocks = <int>{...counts.keys};
    for (var i = 1; i <= 3; i++) {
      if (blocks.length < 3) blocks.add(i);
    }
    final ordered = blocks.toList()..sort();

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF4F8FC),
        border: Border.all(color: const Color(0xFFDCE8F4)),
        borderRadius: BorderRadius.circular(13),
      ),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
      child: Column(
        children: [
          const Text(
            'RESUMEN SEMANAL',
            style: TextStyle(
              color: kBrandNavy,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              for (var i = 0; i < ordered.length && i < 3; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Column(
                      children: [
                        Text(
                          _turnLabel(ordered[i]),
                          style: TextStyle(
                            color: _turnColor(ordered[i]),
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${counts[ordered[i]] ?? 0}',
                          style: TextStyle(
                            color: _turnColor(ordered[i]),
                            fontSize: 25,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _personHeader(Officer officer) {
    final index = _officers.indexOf(officer) + 1;
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 2, 4, 14),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF2FC),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(Icons.person, color: kBrandNavy, size: 34),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  officer.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: kBrandNavy,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  officer.alias.trim().isNotEmpty
                      ? officer.alias.trim()
                      : 'Oficial ${index.toString().padLeft(2, '0')}',
                  style: const TextStyle(
                    color: Color(0xFF455A70),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.calendar_month, color: kBrandNavy, size: 23),
                  SizedBox(width: 5),
                  Text(
                    'Semana',
                    style: TextStyle(
                      color: kBrandNavy,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              Text(
                '${_weekNumber()}',
                style: const TextStyle(
                  color: kBrandNavy,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                _dateRange(),
                textAlign: TextAlign.right,
                style: const TextStyle(
                  color: kBrandNavy,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _sharePersonalSchedule(Officer officer) async {
    var sharePersonal = true;
    var shareTurns = true;
    var shareAttendance = true;
    var shareRoutes = true;

    final safeName = officer.alias.trim().isNotEmpty
        ? officer.alias.trim()
        : officer.name.trim();
    final cleanName = safeName.replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '_');
    final personalFileName =
        'horario_personal_${cleanName}_semana_${_weekNumber()}.png';
    final personalShareText =
        'Horario personal de ${officer.alias.trim().isNotEmpty ? officer.alias.trim() : officer.name} · Semana ${_weekNumber()}';

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final allSelected =
                sharePersonal && shareTurns && shareAttendance && shareRoutes;
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
                        'Puedes seleccionar el horario personal y los demás reportes.',
                        style: TextStyle(color: Colors.black54),
                      ),
                    ),
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      value: allSelected,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text(
                        'Seleccionar todos',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                      onChanged: (value) {
                        final selected = value ?? false;
                        setSheetState(() {
                          sharePersonal = selected;
                          shareTurns = selected;
                          shareAttendance = selected;
                          shareRoutes = selected;
                        });
                      },
                    ),
                    const Divider(height: 1),
                    CheckboxListTile(
                      value: sharePersonal,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text('Horario personal de $safeName'),
                      subtitle: const Text('Reporte del oficial seleccionado'),
                      onChanged: (value) => setSheetState(
                        () => sharePersonal = value ?? false,
                      ),
                    ),
                    CheckboxListTile(
                      value: shareTurns,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text('Horario de Turnos'),
                      subtitle: const Text('Turnos de descanso de la semana'),
                      onChanged: (value) => setSheetState(
                        () => shareTurns = value ?? false,
                      ),
                    ),
                    CheckboxListTile(
                      value: shareAttendance,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text('Horario de Asistencia'),
                      subtitle: const Text('Disponibilidad semanal de los oficiales'),
                      onChanged: (value) => setSheetState(
                        () => shareAttendance = value ?? false,
                      ),
                    ),
                    CheckboxListTile(
                      value: shareRoutes,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text('Horario de Recorridos'),
                      subtitle: const Text('Programación semanal de recorridos'),
                      onChanged: (value) => setSheetState(
                        () => shareRoutes = value ?? false,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: !(sharePersonal || shareTurns || shareAttendance || shareRoutes)
                            ? null
                            : () async {
                                final reports = <({GlobalKey key, String fileName})>[];
                                if (sharePersonal) {
                                  reports.add((
                                    key: _reportKey,
                                    fileName: personalFileName,
                                  ));
                                }
                                if (shareTurns) {
                                  reports.add((
                                    key: _turnsReportKey,
                                    fileName: 'horario_turnos_semanal.png',
                                  ));
                                }
                                if (shareAttendance) {
                                  reports.add((
                                    key: _attendanceReportKey,
                                    fileName: 'horario_asistencia_semanal.png',
                                  ));
                                }
                                if (shareRoutes) {
                                  reports.add((
                                    key: _routesReportKey,
                                    fileName: 'horario_recorridos_semanal.png',
                                  ));
                                }

                                Navigator.pop(sheetContext);
                                await _exportService.shareWidgets(
                                  reports,
                                  shareText: personalShareText,
                                );
                              },
                        icon: const Icon(Icons.share),
                        label: const Text('Compartir seleccionados'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _changeWeek(int days) async {
    setState(() {
      _monday = _monday.add(Duration(days: days));
    });
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final officer = _selectedOfficer;

    return Scaffold(
      appBar: buildBrandAppBar(
        context,
        'Horario Personal',
        actions: [
          IconButton(
            onPressed: (_loading || officer == null)
                ? null
                : () => _sharePersonalSchedule(officer),
            icon: const Icon(Icons.share),
            tooltip: 'Compartir horario personal',
          ),
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _officers.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No hay oficiales activos registrados.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                )
              : Stack(
                  children: [
                    RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                    padding: const EdgeInsets.fromLTRB(12, 14, 12, 24),
                    children: [
                      const SectionTitle(
                        title: 'HORARIO PERSONAL',
                        subtitle: 'Consulta semanal individual del oficial.',
                        icon: Icons.person,
                      ),
                      const SizedBox(height: 12),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 5,
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<int>(
                              isExpanded: true,
                              value: _selectedOfficerId,
                              icon: const Icon(Icons.keyboard_arrow_down),
                              onChanged: (value) => setState(
                                () => _selectedOfficerId = value,
                              ),
                              items: [
                                for (final item in _officers)
                                  DropdownMenuItem<int>(
                                    value: item.id,
                                    child: Text(
                                      item.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (officer != null) ...[
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _changeWeek(-7),
                                icon: const Icon(Icons.chevron_left),
                                label: const Text('Ant.'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 2,
                              child: OutlinedButton(
                                onPressed: () async {
                                  setState(() =>
                                      _monday = _weekMonday(DateTime.now()));
                                  await _load();
                                },
                                child: const Text('Semana actual'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => _changeWeek(7),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
                                  children: const [
                                    Text('Sig.'),
                                    SizedBox(width: 6),
                                    Icon(Icons.chevron_right),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        RepaintBoundary(
                          child: Container(
                            color: Colors.white,
                            padding: const EdgeInsets.all(4),
                            child: Column(
                              children: [
                                _personHeader(officer),
                                _scheduleTable(officer),
                                const SizedBox(height: 12),
                                _summary(officer),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                      ),
                    ),
                    Positioned(
                      left: -10000,
                      top: 0,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 1000,
                            child: RepaintBoundary(
                              key: _turnsReportKey,
                              child: WeeklyRestMatrixReport(
                                officers: _officers,
                                restByDay: _restByDay,
                                daysOffByOfficer: _daysOffByOfficer,
                                restBlocksByDay: _blocksByDay,
                                monday: _monday,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 565,
                            child: RepaintBoundary(
                              key: _attendanceReportKey,
                              child: Container(
                                color: Colors.white,
                                padding: const EdgeInsets.all(12),
                                child: WeeklyAvailabilityReport(
                                  officers: _officers,
                                  daysOffByOfficer: _daysOffByOfficer,
                                  monday: _monday,
                                ),
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 565,
                            child: RepaintBoundary(
                              key: _routesReportKey,
                              child: Container(
                                color: Colors.white,
                                padding: const EdgeInsets.all(12),
                                child: WeeklyRoutesReport(
                                  officers: _officers,
                                  assignmentsByDay: _assignmentsByDay,
                                  monday: _monday,
                                ),
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 760,
                            child: RepaintBoundary(
                              key: _reportKey,
                              child: PersonalWeeklyReport(
                                officer: officer!,
                                restByDay: _restByDay,
                                daysOffByOfficer: _daysOffByOfficer,
                                restBlocksByDay: _blocksByDay,
                                monday: _monday,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }
}
