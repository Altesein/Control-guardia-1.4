import 'package:flutter/material.dart';
import '../models.dart';
import '../services/db.dart';
import '../widgets/app_chrome.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  DateTime monday = _monday(DateTime.now());
  List<Officer> officers = [];
  Map<int, WeeklyStats> current = {};
  Map<int, WeeklyStats> previous = {};
  List<RestBlock> restBlocks = [];

  static DateTime _monday(DateTime d) => DateTime(
        d.year,
        d.month,
        d.day,
      ).subtract(Duration(days: d.weekday - 1));

  String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final os = await AppDb.instance.officers();
    final cur = await AppDb.instance.weeklyStats(_iso(monday));
    final prev = await AppDb.instance.weeklyStats(
      _iso(monday.subtract(const Duration(days: 7))),
    );
    final blocks = await AppDb.instance.restBlocks();

    if (!mounted) return;

    setState(() {
      officers = os;
      current = cur;
      previous = prev;
      restBlocks = blocks;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildBrandAppBar(context, 'Historial Semanal'),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Text(
            'Semana Activa: ${_fmt(monday)} – ${_fmt(monday.add(const Duration(days: 6)))}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Semana Anterior: ${_fmt(monday.subtract(const Duration(days: 7)))} – ${_fmt(monday.subtract(const Duration(days: 1)))}',
            style: const TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 12),
          const Text(
            'La Semana Activa tiene prioridad. La Semana Anterior solo se usa para desempates.',
            style: TextStyle(fontStyle: FontStyle.italic),
          ),
          const SizedBox(height: 16),
          const Text(
            'Estadísticas de Recorridos',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Card(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Oficial')),
                  DataColumn(label: Text('Recorridos')),
                  DataColumn(label: Text('Largos')),
                  DataColumn(label: Text('Anterior: Recorridos')),
                ],
                rows: [
                  for (final o in officers) _routeRow(o),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Estadísticas de Descansos',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Table(
                  defaultColumnWidth: const IntrinsicColumnWidth(),
                  border: TableBorder(
                    horizontalInside: BorderSide(
                      color: Colors.grey,
                      width: 0.8,
                    ),
                  ),
                  children: [
                    TableRow(
                      decoration: const BoxDecoration(color: Color(0xFFF1F4F6)),
                      children: [
                        _headCell('Oficial'),
                        for (final block in restBlocks) _headCell('Turno ${block.number}'),
                      ],
                    ),
                    for (final o in officers)
                      TableRow(
                        children: [
                          _bodyCell(o.name, bold: true),
                          for (final block in restBlocks)
                            _bodyCell('${current[o.id]?.restCount(block.number) ?? 0}'),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),

        ],
      ),
    );
  }

  Widget _headCell(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        child: Text(text, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
      );

  Widget _bodyCell(String text, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        child: Text(text, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, fontWeight: bold ? FontWeight.w600 : FontWeight.normal)),
      );

  DataRow _routeRow(Officer o) {
    final c = current[o.id] ?? const WeeklyStats();
    final p = previous[o.id] ?? const WeeklyStats();

    return DataRow(
      cells: [
        DataCell(Text(o.name)),
        DataCell(Text('${c.routes}')),
        DataCell(Text('${c.longRoutes}')),
        DataCell(Text('${p.routes}')),
      ],
    );
  }
}