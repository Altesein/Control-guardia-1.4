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
  final Map<int, List<RestBlock>> _simulationProfiles = {};
  List<Officer> _activeOfficers = [];
  int _officerCount = 4;
  int _profileCount = 4;
  final Map<int, Set<int>> _simDaysOff = {};
  final Map<String, Set<int>> _simAbsences = {};
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
    // Copiar perfiles y días libres a memoria; el simulador nunca guarda cambios en la BD.
    final db = AppDb.instance;
    final daysOff = await db.weeklyDaysOffForOfficers(officers.map((o) => o.id!).toList());
    _simDaysOff
      ..clear()
      ..addAll({for (final entry in daysOff.entries) entry.key: Set<int>.from(entry.value)});
    final profiles = await db.restProfiles(minOfficers: 1, maxOfficers: 12);
    if (!mounted) return;
    setState(() {
      for (final profile in profiles) {
        _simulationProfiles[profile.officerCount] = profile.blocks.map((b) => RestBlock(number: b.number, start: b.start, end: b.end, capacity: b.capacity)).toList();
      }
      _profileCount = _officerCount.clamp(1, 12);
    });
    await _loadWeekAbsences(_monday);
  }

  Future<void> _loadWeekAbsences(DateTime monday) async {
    final db = AppDb.instance;
    final updates = <String, Set<int>>{};
    for (var i = 0; i < 7; i++) {
      final date = monday.add(Duration(days: i));
      final key = _iso(date);
      if (!_simAbsences.containsKey(key)) updates[key] = await db.absentIds(key);
    }
    if (mounted && updates.isNotEmpty) setState(() => _simAbsences.addAll(updates));
  }

  Future<TimeOfDay?> _pickTime(String value) async {
    final p = value.split(':');
    return showTimePicker(context: context, initialTime: TimeOfDay(hour: int.tryParse(p[0]) ?? 0, minute: int.tryParse(p[1]) ?? 0));
  }

  String _fmtTime(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _editSimBlock(RestBlock block) async {
    var start = block.start;
    var end = block.end;
    var capacity = block.capacity;
    final result = await showDialog<List<dynamic>>(context: context, builder: (_) => StatefulBuilder(builder: (context, setDialog) => AlertDialog(
      title: Text('Editar ${block.label} (simulación)'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(title: const Text('Hora de inicio'), subtitle: Text(start), trailing: const Icon(Icons.schedule), onTap: () async { final t = await _pickTime(start); if (t != null) setDialog(() => start = _fmtTime(t)); }),
        ListTile(title: const Text('Hora de finalización'), subtitle: Text(end), trailing: const Icon(Icons.schedule), onTap: () async { final t = await _pickTime(end); if (t != null) setDialog(() => end = _fmtTime(t)); }),
        Row(children: [const Expanded(child: Text('Máximo de oficiales')), IconButton(onPressed: capacity > 0 ? () => setDialog(() => capacity--) : null, icon: const Icon(Icons.remove_circle_outline)), Text('$capacity'), IconButton(onPressed: capacity < 99 ? () => setDialog(() => capacity++) : null, icon: const Icon(Icons.add_circle_outline))]),
        const Text('Estos cambios solo afectan las pruebas de esta sesión.', style: TextStyle(fontSize: 12)),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')), FilledButton(onPressed: () => Navigator.pop(context, [start, end, capacity]), child: const Text('Aplicar'))],
    )));
    if (result == null || !mounted) return;
    setState(() { final blocks = _simulationProfiles[_profileCount] ?? []; final i = blocks.indexWhere((b) => b.number == block.number); if (i >= 0) blocks[i] = RestBlock(number: block.number, start: result[0] as String, end: result[1] as String, capacity: result[2] as int); _simulationProfiles[_profileCount] = blocks; });
  }

  void _changeSimBlockCount(int delta) {
    final blocks = List<RestBlock>.from(_simulationProfiles[_profileCount] ?? []);
    final target = (blocks.length + delta).clamp(1, _profileCount).toInt();
    if (target == blocks.length) return;
    if (target < blocks.length) { blocks.removeRange(target, blocks.length); }
    else { for (var n = blocks.length + 1; n <= target; n++) { blocks.add(RestBlock(number: n, start: '00:00', end: '01:00', capacity: 1)); } }
    setState(() => _simulationProfiles[_profileCount] = blocks);
  }

  Future<void> _editDaysOff(Officer officer) async {
    if (officer.id == null) return;
    final days = Set<int>.from(_simDaysOff[officer.id!] ?? {});
    final result = await showDialog<Set<int>>(context: context, builder: (dialogContext) => StatefulBuilder(builder: (context, setDialog) => AlertDialog(
      title: Text('Días libres · ${officer.name}'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: List.generate(7, (i) {
        final weekday = i + 1;
        return CheckboxListTile(dense: true, contentPadding: EdgeInsets.zero, title: Text(_dayNames[i]), value: days.contains(weekday), onChanged: (v) => setDialog(() { if (v == true) { days.add(weekday); } else { days.remove(weekday); } }));
      }))),
      actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancelar')), FilledButton(onPressed: () => Navigator.pop(dialogContext, days), child: const Text('Aplicar'))],
    )));
    if (result != null && mounted) setState(() => _simDaysOff[officer.id!] = Set<int>.from(result));
  }

  Future<void> _editDayAbsences(DateTime date) async {
    final key = _iso(date);
    final absent = Set<int>.from(_simAbsences[key] ?? {});
    final result = await showDialog<Set<int>>(context: context, builder: (dialogContext) => StatefulBuilder(builder: (context, setDialog) => AlertDialog(
      title: Text('Ausencias · ${_dayNames[date.weekday - 1]} ${date.day}/${date.month}'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: _activeOfficers.take(_officerCount).map((officer) => CheckboxListTile(dense: true, contentPadding: EdgeInsets.zero, title: Text(officer.name), subtitle: Text((_simDaysOff[officer.id] ?? {}).contains(date.weekday) ? 'Ya tiene día libre' : 'Disponible según días libres'), value: absent.contains(officer.id), onChanged: (v) => setDialog(() { if (v == true) { absent.add(officer.id!); } else { absent.remove(officer.id); } }))).toList())),
      actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancelar')), FilledButton(onPressed: () => Navigator.pop(dialogContext, absent), child: const Text('Aplicar'))],
    )));
    if (result != null && mounted) setState(() => _simAbsences[key] = Set<int>.from(result));
  }

  Future<void> _generate() async {
    FocusScope.of(context).unfocus();
    if (_officerCount < 1 || _officerCount > _activeOfficers.length) {
      setState(() => _error = 'No hay suficientes oficiales activos para esa simulación.');
      return;
    }
    if ((_simulationProfiles[_officerCount] ?? []).isEmpty) {
      setState(() => _error = 'Configura al menos un bloque de descanso para este perfil.');
      return;
    }

    setState(() {
      _generating = true;
      _error = null;
    });

    try {
      final db = AppDb.instance;
      final selected = _activeOfficers.take(_officerCount).toList();
      final daysOff = <int, Set<int>>{for (final o in selected) o.id!: Set<int>.from(_simDaysOff[o.id!] ?? {})};
      final previousStats = await db.weeklyStats(_iso(_monday.subtract(const Duration(days: 7))));
      final currentStats = <int, WeeklyStats>{for (final o in selected) o.id!: const WeeklyStats()};
      final generated = <String, _SimulatedDay>{};
      final engine = AssignmentEngine();

      for (var index = 0; index < 7; index++) {
        final date = _monday.add(Duration(days: index));
        final dateKey = _iso(date);
        final absent = Set<int>.from(_simAbsences[dateKey] ?? {});
        final dayOffIds = selected
            .where((o) => daysOff[o.id]?.contains(date.weekday) ?? false)
            .map((o) => o.id!).toSet();
        final availableCount = selected.where((o) => !absent.contains(o.id) && !dayOffIds.contains(o.id)).length;
        if (availableCount == 0) {
          generated[dateKey] = _SimulatedDay(date: date, assignments: const [], rests: const {}, blocks: const [], message: 'No hay oficiales disponibles.');
          continue;
        }
        final blocks = List<RestBlock>.from(_simulationProfiles[availableCount] ?? []);
        if (blocks.isEmpty) {
          throw StateError('Falta configurar el perfil de descansos para $availableCount oficiales disponibles. Selecciona ese perfil en «Perfil de descansos» y ajusta sus bloques dentro del simulador.');
        }
        final totalCapacity = blocks.fold<int>(0, (sum, block) => sum + block.capacity);
        if (totalCapacity < availableCount) {
          throw StateError('El perfil de $availableCount oficiales tiene capacidad $totalCapacity, pero necesita al menos $availableCount. En «Perfil de descansos», selecciona $availableCount y aumenta la capacidad de sus bloques. Los cambios son temporales.');
        }
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
      final profileLabel = '${_simulationProfiles[_officerCount]?.length ?? 0} bloques configurados';
      setState(() {
        _scenarios.insert(0, _SimulatedScenario(
          title: '$_officerCount oficiales · $profileLabel',
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
    final next = _monday.add(Duration(days: delta * 7));
    setState(() { _monday = next; _error = null; });
    await _loadWeekAbsences(next);
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
                      const Text('Días libres de los oficiales', style: TextStyle(fontWeight: FontWeight.w800, color: kBrandNavy)),
                      const Text('Edita los días libres solo para esta prueba.', style: TextStyle(fontSize: 12, color: Colors.black54)),
                      ..._activeOfficers.take(_officerCount).map((officer) => Card(child: ListTile(leading: const Icon(Icons.event_busy), title: Text(officer.name), subtitle: Text((((_simDaysOff[officer.id] ?? {}).toList()..sort()).isEmpty ? 'Sin días libres' : ((_simDaysOff[officer.id] ?? {}).toList()..sort()).map((d) => _dayNames[d - 1]).join(', '))), trailing: const Icon(Icons.edit), onTap: () => _editDaysOff(officer)))),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int>(
                        value: _profileCount.clamp(1, 12),
                        decoration: const InputDecoration(labelText: 'Perfil de descansos (oficiales disponibles)'),
                        items: List.generate(12, (i) => i + 1).map((n) => DropdownMenuItem(value: n, child: Text('$n ${n == 1 ? 'oficial' : 'oficiales'}'))).toList(),
                        onChanged: (v) => setState(() { if (v != null) _profileCount = v; }),
                      ),
                      const SizedBox(height: 8),
                      Row(children: [
                        const Expanded(child: Text('Bloques de descanso', style: TextStyle(fontWeight: FontWeight.w700))),
                        IconButton(tooltip: 'Quitar bloque', onPressed: (_simulationProfiles[_profileCount]?.length ?? 0) > 1 ? () => _changeSimBlockCount(-1) : null, icon: const Icon(Icons.remove_circle_outline)),
                        Text('${_simulationProfiles[_profileCount]?.length ?? 0}', style: const TextStyle(fontWeight: FontWeight.w800)),
                        IconButton(tooltip: 'Agregar bloque', onPressed: (_simulationProfiles[_profileCount]?.length ?? 0) < _profileCount ? () => _changeSimBlockCount(1) : null, icon: const Icon(Icons.add_circle_outline)),
                      ]),
                      const Text('Puedes editar el perfil de cada cantidad de oficiales disponibles. Así se corrigen también los días en que algunos descansan o están ausentes.', style: TextStyle(fontSize: 12, color: Colors.black54)),
                      const SizedBox(height: 8),
                      ...(_simulationProfiles[_profileCount] ?? []).map((block) => Card(child: ListTile(
                        title: Text(block.label),
                        subtitle: Text('${block.start} – ${block.end} · Máximo de oficiales: ${block.capacity}'),
                        trailing: const Icon(Icons.edit),
                        onTap: () => _editSimBlock(block),
                      ))),
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
                      const SizedBox(height: 4),
                      const Align(alignment: Alignment.centerLeft, child: Text('Ausencias por día', style: TextStyle(fontWeight: FontWeight.w800))),
                      const SizedBox(height: 4),
                      Wrap(spacing: 6, runSpacing: 6, children: List.generate(7, (i) {
                        final date = _monday.add(Duration(days: i));
                        final count = (_simAbsences[_iso(date)] ?? {}).length;
                        return OutlinedButton(onPressed: () => _editDayAbsences(date), child: Text('${_dayNames[i].substring(0, 3)} ${date.day} · $count'));
                      })),
                      const SizedBox(height: 8),
                      const Text('Se utiliza el motor original de asignación y los bloques configurados para cada cantidad de oficiales. Los cambios de esta pantalla son temporales.', style: TextStyle(color: Colors.black54, fontSize: 12)),
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
