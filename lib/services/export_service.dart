import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models.dart';

class ExportService {
  Future<void> shareWidgetAsPng(
    GlobalKey key, {
    String fileName = 'matriz_descansos_semanal.png',
    String shareText = 'Matriz Semanal de Turnos de Descanso',
  }) async {
    await shareWidget(
      key,
      fileName: fileName,
      shareText: shareText,
    );
  }

  /// Captura varios reportes existentes y los comparte en una sola acción.
  /// No modifica el contenido ni el diseño de ninguno de los reportes.
  Future<void> shareWidgets(
    List<({GlobalKey key, String fileName})> reports, {
    String shareText = 'Reportes semanales',
  }) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final files = <XFile>[];

      for (final report in reports) {
        final boundary = report.key.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
        if (boundary == null) {
          debugPrint('No se encontró el área de impresión para ${report.fileName}.');
          continue;
        }

        final image = await boundary.toImage(pixelRatio: 3.0);
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        if (byteData == null) {
          debugPrint('No se pudo convertir ${report.fileName} a PNG.');
          continue;
        }

        final file = File('${tempDir.path}/${report.fileName}');
        await file.writeAsBytes(byteData.buffer.asUint8List());
        files.add(XFile(file.path));
      }

      if (files.isNotEmpty) {
        await Share.shareXFiles(files, text: shareText);
      }
    } catch (e) {
      debugPrint('Error al compartir reportes: $e');
    }
  }

  Future<void> shareWidget(
    GlobalKey key, {
    required String fileName,
    required String shareText,
  }) async {
    try {
      final boundary =
          key.currentContext?.findRenderObject() as RenderRepaintBoundary?;

      if (boundary == null) {
        debugPrint('No se encontró el área de impresión.');
        return;
      }

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );

      if (byteData == null) {
        debugPrint('No se pudo convertir el reporte a PNG.');
        return;
      }

      final pngBytes = byteData.buffer.asUint8List();
      final tempDir = await getTemporaryDirectory();

      final safeFileName =
          fileName.endsWith('.png') ? fileName : '$fileName.png';

      final file = File('${tempDir.path}/$safeFileName');
      await file.writeAsBytes(pngBytes);

      await Share.shareXFiles(
        [XFile(file.path)],
        text: shareText,
      );
    } catch (e) {
      debugPrint('Error al generar la imagen PNG: $e');
    }
  }
}

class ReportHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final DateTime monday;

  const ReportHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.monday,
  });

  int _weekNumber() {
    final firstThursday = DateTime(monday.year, 1, 4);
    final firstMonday = firstThursday.subtract(
      Duration(days: firstThursday.weekday - 1),
    );
    return (monday.difference(firstMonday).inDays ~/ 7) + 1;
  }

  String _dateRange() {
    final sunday = monday.add(const Duration(days: 6));
    String f(DateTime d) => '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/${d.year}';
    return '${f(monday)} – ${f(sunday)}';
  }

  String _generatedAt() {
    final now = DateTime.now();
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    return 'Generado el: ${now.day.toString().padLeft(2, '0')}/'
        '${now.month.toString().padLeft(2, '0')}/${now.year} $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 3, 8, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 58,
            height: 58,
            child: Image.asset(
              'assets/brand/logo.png',
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'CONTROL DE GUARDIAS',
                    style: TextStyle(
                      color: Color(0xFF0D253F),
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  const Text(
                    'Organización • Disciplina • Servicio',
                    style: TextStyle(
                      color: Color(0xFF0D253F),
                      fontSize: 8,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    title.toUpperCase(),
                    style: const TextStyle(
                      color: Color(0xFF0D253F),
                      fontSize: 8,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Color(0xFF455A70),
                      fontSize: 7.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 7),
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.calendar_month,
                      size: 18,
                      color: Color(0xFF0D253F),
                    ),
                    const SizedBox(width: 5),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Semana ${_weekNumber()}',
                          style: const TextStyle(
                            color: Color(0xFF0D253F),
                            fontSize: 8,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          _dateRange(),
                          style: const TextStyle(
                            color: Color(0xFF0D253F),
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _generatedAt(),
                  style: const TextStyle(
                    color: Color(0xFF455A70),
                    fontSize: 6.5,
                    fontWeight: FontWeight.w600,
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

class ReportFooter extends StatelessWidget {
  const ReportFooter({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(12, 7, 12, 7),
      decoration: const BoxDecoration(
        color: Color(0xFF0D253F),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 34,
            height: 34,
            child: Image.asset(
              'assets/brand/logo.png',
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CAMI',
                  style: TextStyle(
                    color: Color(0xFFD9A72E),
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Control de Asignación y Manejo Inteligente',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 7,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Una herramienta creada para simplificar la organización de la guardia.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 7,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 10),
          const Text(
            'Versión 1.0.0',
            style: TextStyle(
              color: Colors.white,
              fontSize: 7,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class WeeklyRestMatrixReport extends StatelessWidget {
  final List<Officer> officers;
  final Map<String, Map<int, int>> restByDay;
  final Map<int, Set<int>> daysOffByOfficer;
  final Map<String, List<RestBlock>> restBlocksByDay;
  final DateTime monday;

  const WeeklyRestMatrixReport({
    super.key,
    required this.officers,
    required this.restByDay,
    required this.daysOffByOfficer,
    required this.restBlocksByDay,
    required this.monday,
  });

  static const days = ['LUN', 'MAR', 'MIÉ', 'JUE', 'VIE', 'SÁB', 'DOM'];
  static const _months = [
    'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
    'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
  ];
  static const _turnColors = [
    Color(0xFF1677D2),
    Color(0xFF18A56B),
    Color(0xFFE58A00),
    Color(0xFF7A4CC2),
    Color(0xFFE34B67),
    Color(0xFF008B8B),
  ];

  String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  int _weekNumber() {
    final firstThursday = DateTime(monday.year, 1, 4);
    final firstMonday = firstThursday.subtract(
      Duration(days: firstThursday.weekday - 1),
    );
    return (monday.difference(firstMonday).inDays ~/ 7) + 1;
  }

  String _dateRange() {
    final sunday = monday.add(const Duration(days: 6));
    if (monday.month == sunday.month && monday.year == sunday.year) {
      return '${monday.day.toString().padLeft(2, '0')} – '
          '${sunday.day.toString().padLeft(2, '0')} de '
          '${_months[sunday.month - 1]} de ${sunday.year}';
    }
    return '${monday.day.toString().padLeft(2, '0')} de '
        '${_months[monday.month - 1]} – '
        '${sunday.day.toString().padLeft(2, '0')} de '
        '${_months[sunday.month - 1]} de ${sunday.year}';
  }

  String _generatedAt() {
    final now = DateTime.now();
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    return 'Generado el: ${now.day.toString().padLeft(2, '0')}/'
        '${now.month.toString().padLeft(2, '0')}/${now.year} $hh:$mm';
  }

  Color _turnColor(int block) =>
      _turnColors[(block - 1).clamp(0, _turnColors.length - 1)];

  String _turnLabel(int block) => '$block° TURNO';

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 86,
            height: 86,
            child: Image.asset('assets/brand/logo.png', fit: BoxFit.contain),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'CONTROL DE GUARDIAS',
                    style: TextStyle(
                      color: Color(0xFF0D2F59),
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Organización • Disciplina • Servicio',
                    style: TextStyle(
                      color: Color(0xFF0D2F59),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.calendar_month, color: Color(0xFF0D2F59), size: 28),
                  const SizedBox(width: 8),
                  Text(
                    'Semana ${_weekNumber()}',
                    style: const TextStyle(
                      color: Color(0xFF0D2F59),
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                _dateRange(),
                textAlign: TextAlign.right,
                style: const TextStyle(
                  color: Color(0xFF0D2F59),
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 9),
              Text(
                _generatedAt(),
                style: const TextStyle(
                  color: Color(0xFF526579),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _footer() {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
      decoration: const BoxDecoration(
        color: Color(0xFF0D2F59),
        border: Border(top: BorderSide(color: Color(0xFFD9A72E), width: 4)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 42,
            height: 42,
            child: Image.asset('assets/brand/logo.png', fit: BoxFit.contain),
          ),
          const SizedBox(width: 10),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'CAMI',
                style: TextStyle(
                  color: Color(0xFFD9A72E),
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
              Text(
                'Control de Asignación y Manejo Inteligente',
                style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const Spacer(),
          const Text(
            'Una herramienta creada para simplificar la organización de la guardia.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          const Text(
            'Versión 1.0.0',
            style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _weeklyReportCell(Officer officer, int i) {
    final date = monday.add(Duration(days: i));
    final iso = _iso(date);
    final isOff = daysOffByOfficer[officer.id]?.contains(date.weekday) ?? false;
    final block = restByDay[iso]?[officer.id];
    if (isOff) {
      return const SizedBox(height: 78, child: _WeeklyReportRestCell());
    }

    RestBlock? rest;
    for (final candidate in restBlocksByDay[iso] ?? const <RestBlock>[]) {
      if (candidate.number == block) {
        rest = candidate;
        break;
      }
    }

    final hasTurn = block != null && block > 0;
    return SizedBox(
      height: 78,
      child: _WeeklyReportTurnCell(
        label: hasTurn ? _turnLabel(block) : '—',
        time: hasTurn && rest != null ? '${rest.start} – ${rest.end}' : '',
        color: hasTurn ? _turnColor(block) : const Color(0xFF0D2F59),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final active = officers.where((o) => o.active).toList();
    return Container(
      width: 1000,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(),
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 4, 18, 9),
            child: Text(
              '▣  PLAN SEMANAL',
              style: TextStyle(color: Color(0xFF0D2F59), fontSize: 21, fontWeight: FontWeight.w900),
            ),
          ),
          Table(
            border: TableBorder.all(color: Color(0xFFD4DCE4), width: 1),
            columnWidths: const {
              0: FixedColumnWidth(210),
              1: FixedColumnWidth(110),
              2: FixedColumnWidth(110),
              3: FixedColumnWidth(110),
              4: FixedColumnWidth(110),
              5: FixedColumnWidth(110),
              6: FixedColumnWidth(110),
              7: FixedColumnWidth(110),
            },
            children: [
              TableRow(
                decoration: const BoxDecoration(color: Color(0xFF0D2F59)),
                children: [
                  const SizedBox(height: 48, child: Center(child: Text('OFICIAL', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900)))),
                  for (final d in days)
                    SizedBox(height: 48, child: Center(child: Text(d, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900)))),
                ],
              ),
              for (final officer in active)
                TableRow(
                  children: [
                    SizedBox(
                      height: 78,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              officer.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Color(0xFF173B63), fontSize: 13, fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              officer.alias.trim().isNotEmpty
                                  ? officer.alias.trim()
                                  : 'Oficial ${active.indexOf(officer) + 1}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Color(0xFF647589), fontSize: 10, fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                    ),
                    for (var i = 0; i < 7; i++)
                      _weeklyReportCell(officer, i),
                  ],
                ),
            ],
          ),
          _footer(),
        ],
      ),
    );
  }
}

class _WeeklyReportTurnCell extends StatelessWidget {
  final String label;
  final String time;
  final Color color;
  const _WeeklyReportTurnCell({required this.label, required this.time, required this.color});

  @override
  Widget build(BuildContext context) {
    if (label == '—') {
      return const Center(child: Text('—', style: TextStyle(color: Color(0xFF0D2F59), fontSize: 16, fontWeight: FontWeight.w700)));
    }
    return Center(
      child: Container(
        width: 92,
        height: 58,
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.30)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label, textAlign: TextAlign.center, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w900)),
            const SizedBox(height: 3),
            Text(time, textAlign: TextAlign.center, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}

class _WeeklyReportRestCell extends StatelessWidget {
  const _WeeklyReportRestCell();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('Descanso', style: TextStyle(color: Color(0xFF0D2F59), fontSize: 12, fontWeight: FontWeight.w800)),
          SizedBox(height: 4),
          Icon(Icons.nightlight_round, color: Color(0xFF0D2F59), size: 19),
        ],
      ),
    );
  }
}

class PersonalWeeklyReport extends StatelessWidget {
  final Officer officer;
  final Map<String, Map<int, int>> restByDay;
  final Map<int, Set<int>> daysOffByOfficer;
  final Map<String, List<RestBlock>> restBlocksByDay;
  final DateTime monday;

  const PersonalWeeklyReport({
    super.key,
    required this.officer,
    required this.restByDay,
    required this.daysOffByOfficer,
    required this.restBlocksByDay,
    required this.monday,
  });

  static const _days = ['LUN', 'MAR', 'MIÉ', 'JUE', 'VIE', 'SÁB', 'DOM'];
  static const _months = [
    'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
    'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
  ];
  static const _colors = [
    Color(0xFF1677D2), Color(0xFF18A56B), Color(0xFFE58A00), Color(0xFF7A4CC2),
  ];

  String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  int _weekNumber() {
    final firstThursday = DateTime(monday.year, 1, 4);
    final firstMonday = firstThursday.subtract(Duration(days: firstThursday.weekday - 1));
    return (monday.difference(firstMonday).inDays ~/ 7) + 1;
  }

  String _range() {
    final sunday = monday.add(const Duration(days: 6));
    return '${monday.day.toString().padLeft(2, '0')} – ${sunday.day.toString().padLeft(2, '0')} de ${_months[sunday.month - 1]} de ${sunday.year}';
  }

  String _generated() {
    final n = DateTime.now();
    return 'Generado el: ${n.day.toString().padLeft(2, '0')}/${n.month.toString().padLeft(2, '0')}/${n.year} ${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')}';
  }

  TableRow _personalTableRow(int i) {
    final date = monday.add(Duration(days: i));
    final iso = _iso(date);
    final off = daysOffByOfficer[officer.id]?.contains(date.weekday) ?? false;
    final block = restByDay[iso]?[officer.id];

    RestBlock? rest;
    for (final candidate in restBlocksByDay[iso] ?? const <RestBlock>[]) {
      if (candidate.number == block) {
        rest = candidate;
        break;
      }
    }

    final color = block != null && block > 0
        ? _colors[(block - 1).clamp(0, _colors.length - 1)]
        : const Color(0xFF0D2F59);

    return TableRow(
      children: [
        SizedBox(
          height: 64,
          child: Center(
            child: Text(
              '${_days[i]} ${date.day}',
              style: const TextStyle(
                color: Color(0xFF0D2F59),
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
        SizedBox(
          height: 64,
          child: Center(
            child: off
                ? const Text(
                    'DESCANSO',
                    style: TextStyle(
                      color: Color(0xFF0D2F59),
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  )
                : Text(
                    '${block ?? 0}° TURNO',
                    style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
          ),
        ),
        SizedBox(
          height: 64,
          child: Center(
            child: Text(
              off ? '—' : (rest == null ? '—' : '${rest.start} – ${rest.end}'),
              style: const TextStyle(
                color: Color(0xFF0D2F59),
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final counts = <int, int>{};
    for (var i = 0; i < 7; i++) {
      final date = monday.add(Duration(days: i));
      final block = restByDay[_iso(date)]?[officer.id];
      if (block != null && block > 0) counts[block] = (counts[block] ?? 0) + 1;
    }

    return Container(
      width: 760,
      color: Colors.white,
      padding: const EdgeInsets.all(18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              SizedBox(width: 70, height: 70, child: Image.asset('assets/brand/logo.png')),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('CONTROL DE GUARDIAS', style: TextStyle(color: Color(0xFF0D2F59), fontSize: 22, fontWeight: FontWeight.w900)),
                  SizedBox(height: 3),
                  Text('Organización • Disciplina • Servicio', style: TextStyle(color: Color(0xFF0D2F59), fontSize: 10, fontWeight: FontWeight.w700)),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('Semana ${_weekNumber()}', style: const TextStyle(color: Color(0xFF0D2F59), fontSize: 13, fontWeight: FontWeight.w900)),
                Text(_range(), style: const TextStyle(color: Color(0xFF0D2F59), fontSize: 10, fontWeight: FontWeight.w800)),
                const SizedBox(height: 5),
                Text(_generated(), style: const TextStyle(color: Color(0xFF526579), fontSize: 8)),
              ]),
            ],
          ),
          const SizedBox(height: 14),
          Align(alignment: Alignment.centerLeft, child: Text('HORARIO PERSONAL', style: const TextStyle(color: Color(0xFF0D2F59), fontSize: 18, fontWeight: FontWeight.w900))),
          const SizedBox(height: 5),
          Align(alignment: Alignment.centerLeft, child: Text(officer.name, style: const TextStyle(color: Color(0xFF173B63), fontSize: 16, fontWeight: FontWeight.w900))),
          Align(alignment: Alignment.centerLeft, child: Text(officer.alias.trim().isNotEmpty ? officer.alias.trim() : 'Oficial', style: const TextStyle(color: Color(0xFF647589), fontSize: 10, fontWeight: FontWeight.w700))),
          const SizedBox(height: 10),
          Table(
            border: TableBorder.all(color: Color(0xFFD4DCE4)),
            columnWidths: const {0: FixedColumnWidth(100), 1: FixedColumnWidth(330), 2: FixedColumnWidth(270)},
            children: [
              TableRow(decoration: const BoxDecoration(color: Color(0xFF0D2F59)), children: [
                for (final h in ['DÍA', 'TURNO', 'HORARIO'])
                  SizedBox(height: 40, child: Center(child: Text(h, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900)))),
              ]),
              for (var i = 0; i < 7; i++) _personalTableRow(i),
            ],
          ),
          const SizedBox(height: 10),
          Row(children: [
            for (var i = 1; i <= 4; i++)
              Expanded(child: Container(margin: const EdgeInsets.symmetric(horizontal: 3), padding: const EdgeInsets.symmetric(vertical: 7), decoration: BoxDecoration(color: _colors[i-1].withValues(alpha: .08), borderRadius: BorderRadius.circular(7)), child: Column(children: [Text('$i° TURNO', style: TextStyle(color: _colors[i-1], fontSize: 9, fontWeight: FontWeight.w900)), Text('${counts[i] ?? 0}', style: TextStyle(color: _colors[i-1], fontSize: 18, fontWeight: FontWeight.w900))]))),
          ]),
          Container(
            margin: const EdgeInsets.only(top: 10),
            padding: const EdgeInsets.all(8),
            color: const Color(0xFF0D2F59),
            child: Row(children: [
              const Text('CAMI', style: TextStyle(color: Color(0xFFD9A72E), fontSize: 13, fontWeight: FontWeight.w900)),
              const Spacer(),
              const Text('Control de Asignación y Manejo Inteligente', style: TextStyle(color: Colors.white, fontSize: 7, fontWeight: FontWeight.w700)),
            ]),
          ),
        ],
      ),
    );
  }
}

class WeeklyAvailabilityReport extends StatelessWidget {
  final List<Officer> officers;
  final Map<int, Set<int>> daysOffByOfficer;
  final DateTime monday;

  const WeeklyAvailabilityReport({
    super.key,
    required this.officers,
    required this.daysOffByOfficer,
    required this.monday,
  });

  static const days = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];

  String _dateRange() {
    final sunday = monday.add(const Duration(days: 6));
    return '${monday.day.toString().padLeft(2, '0')}/'
        '${monday.month.toString().padLeft(2, '0')}/'
        '${monday.year} – '
        '${sunday.day.toString().padLeft(2, '0')}/'
        '${sunday.month.toString().padLeft(2, '0')}/'
        '${sunday.year}';
  }

  Widget _availabilityCell(Officer officer, int weekday) {
    final isAvailable = officer.active &&
        !(daysOffByOfficer[officer.id]?.contains(weekday) ?? false);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isAvailable
                  ? Colors.green.shade500
                  : Colors.grey.shade400,
            ),
            child: Icon(
              isAvailable ? Icons.check : Icons.remove,
              color: Colors.white,
              size: 15,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            isAvailable ? 'Disponible' : 'Libre',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.w700,
              color: isAvailable
                  ? Colors.green.shade700
                  : Colors.grey.shade700,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ReportHeader(
            title: 'Disponibilidad Semanal',
            subtitle: 'Semana: ${_dateRange()}',
            monday: monday,
          ),
          Table(
            border: TableBorder.all(
              color: Colors.grey.shade400,
              width: 1,
            ),
            columnWidths: const {0: FlexColumnWidth(2.2)},
            children: [
              TableRow(
                decoration: const BoxDecoration(
                  color: Color(0xFFF1F4F6),
                ),
                children: [
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: Text(
                      'Oficial',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  for (final d in days)
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        d,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                ],
              ),
              for (final officer in officers)
                TableRow(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        officer.name,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          color:
                              officer.active ? Colors.black87 : Colors.grey,
                        ),
                      ),
                    ),
                    for (var i = 0; i < 7; i++)
                      _availabilityCell(officer, i + 1),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.green.shade500,
                ),
              ),
              const SizedBox(width: 5),
              const Text(
                'Disponible',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 14),
              Container(
                width: 12,
                height: 12,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(width: 5),
              const Text(
                'Libre',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const ReportFooter(),
        ],
      ),
    );
  }
}

class WeeklyRoutesReport extends StatelessWidget {
  final List<Officer> officers;
  final Map<String, List<Assignment>> assignmentsByDay;
  final DateTime monday;

  const WeeklyRoutesReport({
    super.key,
    required this.officers,
    required this.assignmentsByDay,
    required this.monday,
  });

  static const days = ['LUN', 'MAR', 'MIÉ', 'JUE', 'VIE', 'SÁB', 'DOM'];
  static const hours = [20, 21, 22, 23, 0, 1, 2, 3, 4, 5, 6];

  String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  String _dateRange() {
    final sunday = monday.add(const Duration(days: 6));
    return '${monday.day.toString().padLeft(2, '0')}/'
        '${monday.month.toString().padLeft(2, '0')}/${monday.year} – '
        '${sunday.day.toString().padLeft(2, '0')}/'
        '${sunday.month.toString().padLeft(2, '0')}/${sunday.year}';
  }

  Assignment? _assignmentFor(String iso, int index) {
    final routes = assignmentsByDay[iso] ?? const <Assignment>[];
    if (index < 0 || index >= routes.length) return null;
    return routes[index];
  }

  Color _officerColor(String name) {
    final index = officers.indexWhere((o) => o.name == name);
    const colors = [
      Color(0xFF1677D2),
      Color(0xFF18A56B),
      Color(0xFFE58A00),
      Color(0xFF7A4CC2),
      Color(0xFFE34B67),
      Color(0xFF008B8B),
    ];
    if (index < 0) return const Color(0xFF0D253F);
    return colors[index % colors.length];
  }

  Widget _cell(Assignment? route) {
    if (route == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8, horizontal: 2),
        child: Text(
          '—',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 8, color: Colors.black38),
        ),
      );
    }

    final color = _officerColor(route.officer);
    return Container(
      margin: const EdgeInsets.all(1.5),
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Text(
        route.officer,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: color,
          fontSize: 7.2,
          height: 1.05,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ReportHeader(
            title: 'Recorridos',
            subtitle: 'Horario de recorridos · ${_dateRange()}',
            monday: monday,
          ),
          Row(
            children: [
              const Icon(Icons.directions_walk, size: 18, color: Color(0xFF0D253F)),
              const SizedBox(width: 6),
              const Text(
                'RECORRIDOS (8:00 PM – 6:00 AM)',
                style: TextStyle(
                  color: Color(0xFF0D253F),
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Spacer(),
              const Text(
                'R1 = recorrido largo',
                style: TextStyle(fontSize: 8.5, color: Colors.black54),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Table(
            border: TableBorder.all(
              color: const Color(0xFFD5DCE2),
              width: 0.8,
            ),
            columnWidths: const {
              0: FixedColumnWidth(58),
            },
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              TableRow(
                decoration: const BoxDecoration(color: Color(0xFF0D253F)),
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 7, horizontal: 2),
                    child: Text(
                      'HORARIO',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 7.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  for (var i = 0; i < 11; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 1),
                      child: Column(
                        children: [
                          Text(
                            'R${i + 1}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 7.5,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            '${hours[i].toString().padLeft(2, '0')}:00',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 6.8,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              for (var dayIndex = 0; dayIndex < 7; dayIndex++)
                TableRow(
                  decoration: BoxDecoration(
                    color: dayIndex.isEven
                        ? Colors.white
                        : const Color(0xFFFAFBFC),
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                      child: Column(
                        children: [
                          Text(
                            '${days[dayIndex]} ${monday.add(Duration(days: dayIndex)).day}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Color(0xFF0D253F),
                              fontSize: 8,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                    for (var routeIndex = 0; routeIndex < 11; routeIndex++)
                      _cell(
                        _assignmentFor(
                          _iso(monday.add(Duration(days: dayIndex))),
                          routeIndex,
                        ),
                      ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 7),
          const Text(
            'R1 (20:00) corresponde al recorrido largo / primero de la noche.',
            style: TextStyle(
              fontSize: 8,
              color: Colors.black54,
              fontWeight: FontWeight.w600,
            ),
          ),
          const ReportFooter(),
        ],
      ),
    );
  }
}

