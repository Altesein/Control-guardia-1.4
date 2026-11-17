import 'package:flutter/material.dart';
import '../models.dart';
import '../services/db.dart';
import '../widgets/app_chrome.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _selectedOfficerCount = 3;
  int _activeOfficerCount = 3;
  List<RestBlock> _blocks = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final officers = await AppDb.instance.officers();
    final active = officers.where((o) => o.active).length.clamp(1, 12).toInt();
    final profile = await AppDb.instance.restProfile(active);
    if (!mounted) return;
    setState(() {
      _activeOfficerCount = active;
      _selectedOfficerCount = active;
      _blocks = profile.blocks;
      _loading = false;
    });
  }

  Future<void> _loadProfile(int count) async {
    setState(() => _loading = true);
    final profile = await AppDb.instance.restProfile(count);
    if (!mounted) return;
    setState(() {
      _selectedOfficerCount = count;
      _blocks = profile.blocks;
      _loading = false;
    });
  }

  Future<TimeOfDay?> _pick(String value) async {
    final p = value.split(':');
    return showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: int.tryParse(p[0]) ?? 0,
        minute: int.tryParse(p[1]) ?? 0,
      ),
    );
  }

  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  bool get _validCapacity {
    final activeBlocks = _blocks.where((b) => b.capacity > 0).length;
    final total = _blocks.fold<int>(0, (sum, b) => sum + b.capacity);
    return activeBlocks <= _selectedOfficerCount && total >= _selectedOfficerCount;
  }

  Future<void> _editBlock(RestBlock block) async {
    var start = block.start;
    var end = block.end;
    var capacity = block.capacity;
    final result = await showDialog<List<dynamic>>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: Text('Editar ${block.label}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('Hora de inicio'),
                subtitle: Text(start),
                trailing: const Icon(Icons.schedule),
                onTap: () async {
                  final t = await _pick(start);
                  if (t != null) setDialog(() => start = _fmt(t));
                },
              ),
              ListTile(
                title: const Text('Hora de finalización'),
                subtitle: Text(end),
                trailing: const Icon(Icons.schedule),
                onTap: () async {
                  final t = await _pick(end);
                  if (t != null) setDialog(() => end = _fmt(t));
                },
              ),
              Row(
                children: [
                  const Expanded(child: Text('Oficiales permitidos')),
                  IconButton(
                    onPressed: capacity > 0
                        ? () => setDialog(() => capacity--)
                        : null,
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  SizedBox(
                    width: 36,
                    child: Text(
                      '$capacity',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    onPressed: capacity < 99
                        ? () => setDialog(() => capacity++)
                        : null,
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'La cantidad es el máximo de oficiales que pueden compartir este descanso. Usa 0 para desactivarlo.',
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () => Navigator.pop(context, [start, end, capacity]),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    await AppDb.instance.setRestBlock(
      _selectedOfficerCount,
      block.number,
      result[0] as String,
      result[1] as String,
      capacity: result[2] as int,
    );
    await _loadProfile(_selectedOfficerCount);
  }

  Future<void> _changeBlockCount(int delta) async {
    final next = (_blocks.length + delta).clamp(1, _selectedOfficerCount).toInt();
    if (next == _blocks.length) return;
    await AppDb.instance.setRestBlockCount(_selectedOfficerCount, next);
    await _loadProfile(_selectedOfficerCount);
  }

  Future<void> _removeBlock(RestBlock block) async {
    if (_blocks.length <= 1) return;
    await AppDb.instance.removeRestBlock(block.number, officerCount: _selectedOfficerCount);
    await _loadProfile(_selectedOfficerCount);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: buildBrandAppBar(context, 'Configuración'),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                children: [
                  const BrandBanner(
                    title: 'Configuración',
                    subtitle: 'Descansos independientes según los oficiales disponibles.',
                  ),
                  const SizedBox(height: 12),
                  _section('Configuraciones por cantidad de oficiales', [
                    const Text(
                      'Cada cantidad de oficiales tiene su propia configuración. Cambiar una no modifica las demás. Puedes elegir cuántos descansos existen y cuántos oficiales comparten cada uno.',
                      style: TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      value: _selectedOfficerCount,
                      decoration: const InputDecoration(
                        labelText: 'Oficiales disponibles',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (var n = 1; n <= 12; n++)
                          DropdownMenuItem(value: n, child: Text('$n oficiales')),
                      ],
                      onChanged: (n) {
                        if (n != null) _loadProfile(n);
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _selectedOfficerCount == _activeOfficerCount
                          ? 'Perfil usado actualmente: $_activeOfficerCount oficiales activos.'
                          : 'Estás editando otro perfil. Se usará automáticamente cuando ese número esté disponible.',
                      style: const TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  _section('Descansos de este perfil', [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Cantidad de descansos',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        IconButton(
                          onPressed: _blocks.length > 1 ? () => _changeBlockCount(-1) : null,
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                        Text(
                          '${_blocks.length}',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        IconButton(
                          onPressed: _blocks.length < _selectedOfficerCount
                              ? () => _changeBlockCount(1)
                              : null,
                          icon: const Icon(Icons.add_circle_outline),
                        ),
                      ],
                    ),
                    const Text(
                      'El número de descansos puede ser menor que el número de oficiales. La capacidad de cada descanso define cuántos pueden compartirlo; la suma de capacidades debe cubrir a todos los oficiales disponibles.',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    for (final block in _blocks)
                      Card(
                        child: ListTile(
                          title: Text(block.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text('${block.start} – ${block.end}\nMáximo de oficiales: ${block.capacity}'),
                          isThreeLine: true,
                          trailing: Wrap(
                            children: [
                              IconButton(
                                tooltip: 'Editar',
                                icon: const Icon(Icons.edit),
                                onPressed: () => _editBlock(block),
                              ),
                              IconButton(
                                tooltip: 'Eliminar',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: _blocks.length > 1 ? () => _removeBlock(block) : null,
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (!_validCapacity)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          '⚠ La capacidad configurada no alcanza para todos los oficiales disponibles. Aumenta alguna capacidad o agrega descansos.',
                          style: TextStyle(color: Colors.red, fontWeight: FontWeight.w700),
                        ),
                      ),
                  ]),
                  const SizedBox(height: 12),
                  _section('Recorridos', const [
                    ListTile(
                      title: Text('Horarios de recorrido'),
                      subtitle: Text('20:00, 21:00, 22:00, 23:00, 00:00, 01:00, 02:00, 03:00, 04:00, 05:00, 06:00'),
                    ),
                    ListTile(
                      leading: Icon(Icons.block),
                      title: Text('Los recorridos respetan los descansos'),
                      subtitle: Text('Cada día se usa el perfil correspondiente a la cantidad real de oficiales disponibles. Los recorridos son fijos y no se retrasan; nunca se asignan dentro del descanso.'),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  _section('Reglas de asignación', const [
                    ListTile(leading: Icon(Icons.hotel), title: Text('Descansos primero'), subtitle: Text('Primero se asignan los descansos. Los recorridos mantienen su hora exacta y se evita especialmente salir del descanso directamente a un recorrido; si es inevitable, se prefiere la transición de entrada.')),
                    ListTile(leading: Icon(Icons.balance), title: Text('Equilibrio'), subtitle: Text('La carga diaria se mantiene lo más pareja posible y el acumulado semanal favorece a quien lleva menos recorridos. El recorrido de las 20:00 se reparte equitativamente.')),
                    ListTile(leading: Icon(Icons.block), title: Text('Días libres'), subtitle: Text('Un oficial con Día Libre nunca recibe un recorrido.')),
                  ]),
                ],
              ),
      );

  Widget _section(String title, List<Widget> children) => Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ),
              ...children,
            ],
          ),
        ),
      );
}
