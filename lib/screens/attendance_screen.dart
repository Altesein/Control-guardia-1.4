import 'package:flutter/material.dart';
import '../models.dart';
import '../services/db.dart';
import '../widgets/app_chrome.dart';
import '../services/weekly_generator.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  DateTime selectedDate = DateTime.now();
  List<Officer> officers = [];
  Map<int, Set<int>> daysOffByOfficer = {};
  Set<int> absentIds = {};
  bool loading = true;
  bool recalculating = false;

  static const dayNames = [
    'Lunes',
    'Martes',
    'Miércoles',
    'Jueves',
    'Viernes',
    'Sábado',
    'Domingo',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  String _dateLabel(DateTime d) =>
      '${dayNames[d.weekday - 1]} ${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';

  DateTime _monday(DateTime d) => DateTime(
        d.year,
        d.month,
        d.day,
      ).subtract(Duration(days: d.weekday - 1));

  Future<void> _load() async {
    setState(() => loading = true);
    final list = await AppDb.instance.officers();
    final map = await AppDb.instance.weeklyDaysOffForOfficers(
      list.where((o) => o.id != null).map((o) => o.id!).toList(),
    );
    final absent = await AppDb.instance.absentIds(_iso(selectedDate));

    if (mounted) {
      setState(() {
        officers = list;
        daysOffByOfficer = map;
        absentIds = absent;
        loading = false;
      });
    }
  }

  List<Officer> get scheduledOfficers => officers.where((o) {
        if (!o.active || o.id == null) return false;
        return !(daysOffByOfficer[o.id]?.contains(selectedDate.weekday) ?? false);
      }).toList();

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;

    setState(() => selectedDate = picked);
    await _load();
  }

  Future<void> _setPresence(Officer officer, bool present) async {
    if (recalculating) return;

    setState(() => recalculating = true);

    try {
      final date = _iso(selectedDate);
      if (present) {
        await AppDb.instance.clearAbsence(officer.id!, date);
      } else {
        await AppDb.instance.markAbsence(officer.id!, date);
      }

      final monday = _monday(selectedDate);
      final result = await WeeklyGenerator().generate(
        monday: monday,
        officers: officers,
      );

      if (mounted) {
        setState(() {
          absentIds = {
            if (!present) ...absentIds,
          };
          if (present) {
            absentIds.remove(officer.id!);
          } else {
            absentIds.add(officer.id!);
          }
          daysOffByOfficer = result.daysOffByOfficer;
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              present
                  ? '${officer.name} marcado como presente. Turno recalculado.'
                  : '${officer.name} marcado como ausente. Turno recalculado.',
            ),
          ),
        );
      }
    } catch (e) {
      // Si el cambio deja el día en una configuración que no puede generarse,
      // la ausencia se revierte para no dejar la base de datos en un estado
      // que no tenga una programación válida.
      final date = _iso(selectedDate);
      final presentNow = await AppDb.instance.hasAbsence(officer.id!, date);
      if (presentNow == !present) {
        if (present) {
          await AppDb.instance.markAbsence(officer.id!, date);
        } else {
          await AppDb.instance.clearAbsence(officer.id!, date);
        }
      }
      await _load();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'No se pudo recalcular la programación: $e',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => recalculating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheduled = scheduledOfficers;

    return Scaffold(
      appBar: buildBrandAppBar(
        context,
        'Asistencia del Día',
        actions: [
          IconButton(
            onPressed: recalculating ? null : _pickDate,
            icon: const Icon(Icons.calendar_month),
            tooltip: 'Cambiar fecha',
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Control de Asistencia',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _dateLabel(selectedDate),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Los oficiales que tienen este día como día libre no aparecen aquí. '
                          'Todos los demás comienzan como presentes.',
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (recalculating)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(14),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Actualizando recorridos y descansos…',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (scheduled.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(18),
                      child: Text(
                        'No hay oficiales programados para venir este día.',
                      ),
                    ),
                  ),
                for (final officer in scheduled)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: SwitchListTile(
                      secondary: CircleAvatar(
                        child: Text(
                          officer.name.isEmpty
                              ? '?'
                              : officer.name[0].toUpperCase(),
                        ),
                      ),
                      title: Text(
                        officer.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: Text(
                        absentIds.contains(officer.id)
                            ? 'Ausente · no recibe recorridos ni descanso'
                            : 'Presente · participa en la programación',
                      ),
                      value: !absentIds.contains(officer.id),
                      onChanged: recalculating
                          ? null
                          : (value) => _setPresence(officer, value),
                    ),
                  ),
              ],
            ),
    );
  }
}
