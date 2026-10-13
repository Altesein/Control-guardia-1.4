import 'package:flutter/material.dart';
import '../models.dart';
import '../services/assignment_engine.dart';
import '../services/db.dart';
import '../widgets/app_chrome.dart';

class SimulatorScreen extends StatefulWidget {
  const SimulatorScreen({super.key});

  @override
  State<SimulatorScreen> createState() => _SimulatorScreenState();
}

class _SimulatorScreenState extends State<SimulatorScreen> {
  final _hoursController = TextEditingController(text: '2');
  final _minutesController = TextEditingController(text: '0');
  final _startController = TextEditingController(text: '21:00');
  List<Officer> _activeOfficers = [];
  int _officerCount = 4;
  bool _loading = true;
  bool _generating = false;
  DateTime _monday = _weekMonday(DateTime.now());
  final List<_SimulatedScenario> _scenarios = [];
  String? _error;

  static DateTime _weekMonday(DateTime d) => DateTime(d.year, d.month, d.day)
      .subtract(Duration(days: d.weekday - 1));

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static const _dayNames = [
    'Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo'
  ];

  @override
  void initState() {
    super.initState();
    _loadOfficers();
  }

  @override
  void dispose() {
    _hoursController.dispose();
    _minutesController.dispose();
    _startController.dispose();
    super.dispose();
  }

  Future<void> _loadOfficers() async {
    final officers = (await AppDb.instance.officers())
        .where((o) => o.active && o.id != null)
        .toList();
    if (!mounted) return;
    setState(() {
      _activeOfficers = officers;
      _officerCount = officers.length < 4 ? officers.length : 4;
      _loading = false;
    });
  }

  int _minuteOf(String value) {
    final parts = value.trim().split(':');
    if (parts.length != 2) throw const FormatException('Usa el formato HH:MM para la hora de inicio.');
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) {
      throw const FormatException('La hora de inicio debe estar entre 00:00 y 23:59.');
    }
    return h * 60 + m;
  }

  String _clock(int minutes) {
    final v = minutes % (24 * 60);
    return '${(v ~/ 60).toString().padLeft(2, '0')}:${(v % 60).toString().padLeft(2, '0')}';
  }

  List<RestBlock> _makeBlocks(int count, int start, int duration) {
    final blockCount = count.clamp(1, 3).toInt();
    final capacities = switch (count) {
      1 => [1],
      2 => [1, 1],
      3 => [1, 1, 1],
      4 => [1, 1, 2],
      5 => [1, 2, 2],
      _ => List<int>.filled(blockCount, count ~/ blockCount)
          .asMap().entries.map((e) => e.value + (e.key < count % blockCount ? 1 : 0)).toList(),
    };
    return List.generate(blockCount, (i) {
      final from = start + i * duration;
      return RestBlock(
        number: i + 1,
        start: _clock(from),
        end: _clock(from + duration),
        capacity: capacities[i],
      );
    });
  }

  Future<void> _generate() async {
    FocusScope.of(context).unfocus();
    final hours = int.tryParse(_hoursController.text.trim());
    final minutes = int.tryParse(_minutesController.text.trim());
    if (hours == null || minutes == null || hours < 0 || minutes < 0 || minutes > 59 || (hours == 0 && minutes == 0)) {
      setState(() => _error = 'Indica una duración válida. Las horas deben ser 0 o más y los minutos entre 0 y 59.');
      return;
    }
    if (_officerCount < 1 || _officerCount > _activeOfficers.length) {
      setState(() => _error = 'No hay suficientes oficiales activos para esa simulación.');
      return;
    }
    final duration = hours * 60 + minutes;
    if (duration * _officerCount.clamp(1, 3) > 24 * 60) {
      setState(() => _error = 'La duración por bloque es demasiado grande para distribuir los descansos dentro de un día.');
      return;
    }
    int start;
    try {
      start = _minuteOf(_startController.text);
    } on FormatException catch (e) {
      setState(() => _error = e.message);
      return;
    }

    setState(() {
      _generating = true;
      _error = null;
    });

    try {
      final db = AppDb.instance;
      final selected = _activeOfficers.take(_officerCount).toList();
      final daysOff = await db.weeklyDaysOffForOfficers(selected.map((o) => o.id!).toList());
      final previousStats = await db.weeklyStats(_iso(_monday.subtract(const Duration(days: 7))));
      final currentStats = <int, WeeklyStats>{for (final o in selected) o.id!: const WeeklyStats()};
      final generated = <String, _SimulatedDay>{};
      final engine = AssignmentEngine();

      for (var index = 0; index < 7; index++) {
        final date = _monday.add(Duration(days: index));
        final dateKey = _iso(date);
        final absent = await db.absentIds(dateKey);
        final dayOffIds = selected
            .where((o) => daysOff[o.id]?.contains(date.weekday) ?? false)
            .map((o) => o.id!).toSet();
        final availableCount = selected.where((o) => !absent.contains(o.id) && !dayOffIds.contains(o.id)).length;
        if (availableCount == 0) {
          generated[dateKey] = _SimulatedDay(date: date, assignments: const [], rests: const {}, blocks: const [], message: 'No hay oficiales disponibles.');
          continue;
        }
        final blocks = _makeBlocks(availableCount, start, duration);
        final plan = engine.generate(
          date: dateKey,
          active: selected,
          absentIds: absent,
          unavailableIds: dayOffIds,
          currentWeekStats: currentStats,
          previousWeekStats: previousStats,
          restBlocks: blocks,
        );

        for (final entry in plan.restByOfficer.entries) {
          final old = currentStats[entry.key] ?? const WeeklyStats();
          final counts = List<int>.from(old.restCounts);
          while (counts.length < blocks.length) counts.add(0);
          if (entry.value > 0 && entry.value <= counts.length) counts[entry.value - 1]++;
          currentStats[entry.key] = WeeklyStats(routes: old.routes, longRoutes: old.longRoutes, restCounts: counts);
        }
        for (final assignment in plan.assignments) {
          Officer? officer;
          for (final candidate in selected) {
            if (candidate.name == assignment.officer) {
              officer = candidate;
              break;
            }
          }
          if (officer?.id == null) continue;
          final officerId = officer!.id!;
          final old = currentStats[officerId] ?? const WeeklyStats();
          currentStats[officerId] = WeeklyStats(
            routes: old.routes + 1,
            longRoutes: old.longRoutes + (assignment.longRoute ? 1 : 0),
            restCounts: old.restCounts,
          );
        }
        generated[dateKey] = _SimulatedDay(date: date, assignments: plan.assignments, rests: plan.restByOfficer, blocks: blocks);
      }
      if (!mounted) return;
      final durationLabel = hours > 0 && minutes > 0
          ? '${hours} h ${minutes} min'
          : hours > 0
              ? '${hours} h'
              : '${minutes} min';
      setState(() {
        _scenarios.insert(0, _SimulatedScenario(
          title: '$_officerCount oficiales · $durationLabel · inicio ${_startController.text.trim()}',
          weekStart: _monday,
          days: generated,
        ));
        _generating = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _generating = false;
        _error = 'No se pudo generar esta simulación: $e';
      });
    }
  }

  Future<void> _changeWeek(int delta) async {
    setState(() {
      _monday = _monday.add(Duration(days: delta * 7));
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final canSimulate = _activeOfficers.length >= 1;
    return Scaffold(
      appBar: buildBrandAppBar(context, 'Simulador de Guardia'),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              children: [
                const BrandBanner(
                  title: 'Modo de práctica',
                  subtitle: 'Prueba horarios sin modificar la semana real',
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Row(children: [Icon(Icons.tune, color: kBrandNavy), SizedBox(width: 8), Text('Configuración de prueba', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: kBrandNavy))]),
                      const SizedBox(height: 6),
                      const Text('Estos valores solo se usan en el simulador. No cambian Configuración ni la planificación oficial.'),
                      const SizedBox(height: 14),
                      DropdownButtonFormField<int>(
                        value: _activeOfficers.isEmpty ? null : _officerCount.clamp(1, _activeOfficers.length).toInt(),
                        decoration: const InputDecoration(labelText: 'Cantidad de oficiales'),
                        items: List.generate(_activeOfficers.length, (i) => i + 1)
                            .map((n) => DropdownMenuItem(value: n, child: Text('$n ${n == 1 ? 'oficial' : 'oficiales'}'))).toList(),
                        onChanged: (v) => setState(() { if (v != null) { _officerCount = v; } }),
                      ),
                      const SizedBox(height: 12),
                      const Text('Duración de cada descanso', style: TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(child: TextField(controller: _hoursController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Horas', hintText: '0'))),
                        const SizedBox(width: 10),
                        Expanded(child: TextField(controller: _minutesController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Minutos', hintText: '0'))),
                      ]),
                      const SizedBox(height: 12),
                      TextField(controller: _startController, keyboardType: TextInputType.datetime, decoration: const InputDecoration(labelText: 'Hora de inicio del primer bloque', hintText: '21:00', helperText: 'Formato 24 horas, por ejemplo 21:00')),
                      const SizedBox(height: 8),
                      Row(children: [
                        const Icon(Icons.date_range, color: kBrandNavy),
                        const SizedBox(width: 8),
                        const Text('Semana a simular', style: TextStyle(fontWeight: FontWeight.w700)),
                        const Spacer(),
                        IconButton(tooltip: 'Semana anterior', onPressed: () => _changeWeek(-1), icon: const Icon(Icons.chevron_left)),
                        Text('${_date(_monday)}', style: const TextStyle(fontWeight: FontWeight.w700)),
                        IconButton(tooltip: 'Semana siguiente', onPressed: () => _changeWeek(1), icon: const Icon(Icons.chevron_right)),
                      ]),
                      const SizedBox(height: 8),
                      const Text('Los bloques se crean consecutivamente con la duración indicada. El sistema comprobará si los recorridos pueden asignarse sin coincidir con los descansos.', style: TextStyle(color: Colors.black54, fontSize: 12)),
                      const SizedBox(height: 14),
                      FilledButton.icon(onPressed: canSimulate && !_generating ? _generate : null, icon: _generating ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.play_arrow), label: Text(_generating ? 'Generando prueba…' : 'Generar simulación')),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFFFFF0F0), borderRadius: BorderRadius.circular(12)), child: Text(_error!, style: const TextStyle(color: Color(0xFF9D2424)))),
                      ],
                    ]),
                  ),
                ),
                const SizedBox(height: 14),
                if (_scenarios.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8, top: 4),
                    child: Text('PRUEBAS GENERADAS EN ESTA SESIÓN', style: TextStyle(color: kBrandNavy, fontWeight: FontWeight.w900, letterSpacing: .5)),
                  ),
                  const Text('Puedes generar otra configuración y conservar las anteriores para compararlas. Al salir del simulador, estas pruebas temporales se descartan.', style: TextStyle(color: Colors.black54, fontSize: 12)),
                  const SizedBox(height: 8),
                  ..._scenarios.map(_scenarioCard),
                ],
              ],
            ),
    );
  }

  Widget _scenarioCard(_SimulatedScenario scenario) {
    final end = scenario.weekStart.add(const Duration(days: 6));
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        initiallyExpanded: _scenarios.first == scenario,
        leading: const CircleAvatar(backgroundColor: Color(0xFFEAF2FC), child: Icon(Icons.science, color: kBrandNavy)),
        title: Text(scenario.title, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text('Semana ${_date(scenario.weekStart)} – ${_date(end)} · No guardada'),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: [
          const Text('Resultado temporal: no modifica el historial ni la equidad real.', style: TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 8),
          ...scenario.days.values.map(_dayCard),
        ],
      ),
    );
  }

  Widget _dayCard(_SimulatedDay day) {
    final title = '${_dayNames[day.date.weekday - 1]} ${day.date.day}/${day.date.month}';
    final namesByBlock = <int, List<String>>{};
    for (final entry in day.rests.entries) {
      if (entry.value > 0) {
        Officer? officer;
        for (final candidate in _activeOfficers) {
          if (candidate.id == entry.key) {
            officer = candidate;
            break;
          }
        }
        if (officer != null) (namesByBlock[entry.value] ??= []).add(officer.name);
      }
    }
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        initiallyExpanded: false,
        leading: const CircleAvatar(backgroundColor: Color(0xFFEAF2FC), child: Icon(Icons.route, color: kBrandNavy)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text('${day.assignments.length} recorridos · ${day.blocks.length} bloques de descanso'),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        children: [
          if (day.message != null) Align(alignment: Alignment.centerLeft, child: Text(day.message!)),
          if (day.blocks.isNotEmpty) ...[
            const Align(alignment: Alignment.centerLeft, child: Text('Descansos', style: TextStyle(fontWeight: FontWeight.w800, color: kBrandNavy))),
            const SizedBox(height: 6),
            ...day.blocks.map((block) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                SizedBox(width: 92, child: Text('${block.start}–${block.end}', style: const TextStyle(fontWeight: FontWeight.w700))),
                Expanded(child: Text(namesByBlock[block.number]?.join(', ') ?? 'Sin asignar')),
                Text('Máx. ${block.capacity}', style: const TextStyle(fontSize: 11, color: Colors.black54)),
              ]),
            )),
            const Divider(height: 18),
          ],
          const Align(alignment: Alignment.centerLeft, child: Text('Recorridos', style: TextStyle(fontWeight: FontWeight.w800, color: kBrandNavy))),
          const SizedBox(height: 6),
          if (day.assignments.isEmpty) const Align(alignment: Alignment.centerLeft, child: Text('No hay recorridos generados.')),
          ...day.assignments.map((a) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              SizedBox(width: 58, child: Text('${a.hour.toString().padLeft(2, '0')}:00', style: const TextStyle(fontWeight: FontWeight.w800))),
              Expanded(child: Text(a.officer)),
              if (a.longRoute) const Chip(label: Text('Recorrido largo', style: TextStyle(fontSize: 10)), visualDensity: VisualDensity.compact),
            ]),
          )),
        ],
      ),
    );
  }

  String _date(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

class _SimulatedScenario {
  final String title;
  final DateTime weekStart;
  final Map<String, _SimulatedDay> days;

  const _SimulatedScenario({required this.title, required this.weekStart, required this.days});
}

class _SimulatedDay {
  final DateTime date;
  final List<Assignment> assignments;
  final Map<int, int> rests;
  final List<RestBlock> blocks;
  final String? message;

  const _SimulatedDay({required this.date, required this.assignments, required this.rests, required this.blocks, this.message});
}
