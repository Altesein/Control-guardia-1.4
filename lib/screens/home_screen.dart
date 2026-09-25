import 'package:flutter/material.dart';
import '../services/db.dart';
import '../widgets/app_chrome.dart';
import 'officers_screen.dart';
import 'schedule_screen.dart';
import 'settings_screen.dart';
import 'history_screen.dart';
import 'about_screen.dart';
import 'attendance_screen.dart';
import 'personal_schedule_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int officerCount = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final os = await AppDb.instance.officers();
    if (!mounted) return;
    setState(() {
      officerCount = os.where((o) => o.active).length;
    });
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    final sunday = monday.add(const Duration(days: 6));

    return Scaffold(
      appBar: buildBrandAppBar(context, 'Control de Guardias'),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          children: [
            const BrandBanner(
              title: 'Control de Guardias',
              subtitle: 'Organización · Disciplina · Servicio',
            ),
            const SizedBox(height: 14),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEAF2FC),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.calendar_month,
                        color: kBrandNavy,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _weekday(now),
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              color: kBrandNavy,
                            ),
                          ),
                          Text(
                            '${_fullDate(now)} · Semana activa',
                            style: const TextStyle(
                              color: Colors.black54,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _metric(
                    Icons.groups,
                    '$officerCount',
                    'Oficiales activos',
                    const Color(0xFFEAF2FC),
                    kBrandBlue,
                  ),
                ),
                const SizedBox(width: 10),

              ],
            ),
            const SizedBox(height: 18),
            const SectionTitle(
              title: 'Acciones rápidas',
              subtitle: 'Lo más usado, a un toque.',
              icon: Icons.flash_on,
            ),
            const SizedBox(height: 10),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 1.65,
              children: [
                _quickAction(
                  Icons.fact_check,
                  'Asistencia',
                  const Color(0xFF0B63CE),
                  () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AttendanceScreen(),
                      ),
                    );
                    _load();
                  },
                ),
                _quickAction(
                  Icons.route,
                  'Ver Turno',
                  const Color(0xFF13A65B),
                  () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ScheduleScreen(),
                      ),
                    );
                    _load();
                  },
                ),
                _quickAction(
                  Icons.calendar_view_week,
                  'Plan Semanal',
                  const Color(0xFF6841B8),
                  () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ScheduleScreen(),
                      ),
                    );
                    _load();
                  },
                ),
                _quickAction(
                  Icons.person,
                  'Horario Personal',
                  const Color(0xFF0D7A8A),
                  () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const PersonalScheduleScreen(),
                      ),
                    );
                    _load();
                  },
                ),
                _quickAction(
                  Icons.bar_chart,
                  'Estadísticas',
                  const Color(0xFFE88B00),
                  () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const HistoryScreen(),
                      ),
                    );
                    _load();
                  },
                ),
              ],
            ),
            const SizedBox(height: 14),
            Card(
              color: const Color(0xFFEAF3FC),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: kBrandNavy,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.shield,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        '“La seguridad no es un destino, es un trabajo en equipo.”',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            _action(context, Icons.people, 'Oficiales', () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const OfficersScreen()),
              );
              _load();
            }),
            _action(context, Icons.settings, 'Configuración', () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
              _load();
            }),
            _action(context, Icons.info_outline, 'Acerca de', () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AboutScreen()),
              );
            }),
            const SizedBox(height: 8),
            Text(
              '${_fmt(monday)} – ${_fmt(sunday)}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.black45,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metric(
    IconData icon,
    String value,
    String label,
    Color background,
    Color iconColor,
  ) =>
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                        color: kBrandNavy,
                      ),
                    ),
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.black54,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  Widget _quickAction(
    IconData icon,
    String title,
    Color color,
    VoidCallback onTap,
  ) =>
      Material(
        color: color,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: Colors.white, size: 27),
                const SizedBox(height: 6),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _action(
    BuildContext context,
    IconData icon,
    String title,
    VoidCallback onTap,
  ) =>
      Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          leading: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF2FC),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: kBrandNavy),
          ),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      );

  String _weekday(DateTime d) {
    const names = [
      'Lunes',
      'Martes',
      'Miércoles',
      'Jueves',
      'Viernes',
      'Sábado',
      'Domingo',
    ];
    return names[d.weekday - 1];
  }

  String _fullDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
}
