import 'package:flutter/material.dart';
import '../models.dart';
import '../services/db.dart';
import '../widgets/app_chrome.dart';

class OfficersScreen extends StatefulWidget {
  const OfficersScreen({super.key});
  @override
  State<OfficersScreen> createState() => _OfficersScreenState();
}

class _OfficerEditResult {
  final String name;
  final String alias;
  final String colorHex;
  final Set<int> daysOff;

  const _OfficerEditResult({
    required this.name,
    required this.alias,
    required this.colorHex,
    required this.daysOff,
  });
}

class _OfficersScreenState extends State<OfficersScreen> {
  List<Officer> list = [];

  static const days = [
    (1, 'Lunes'),
    (2, 'Martes'),
    (3, 'Miércoles'),
    (4, 'Jueves'),
    (5, 'Viernes'),
    (6, 'Sábado'),
    (7, 'Domingo'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final x = await AppDb.instance.officers();
    if (mounted) setState(() => list = x);
  }

  Color _hexColor(String hex) {
    final value = int.tryParse(hex.replaceFirst('#', ''), radix: 16);
    return value == null ? const Color(0xFF1565C0) : Color(0xFF000000 | value);
  }

  Color _officerColor(Officer officer) {
    if (officer.colorHex.trim().isNotEmpty) {
      return _hexColor(officer.colorHex.trim());
    }

    final manual = list
        .map((o) => o.colorHex.trim().toUpperCase())
        .where((c) => c.isNotEmpty)
        .toSet();
    final usedAutomatic = <String>{};

    for (final o in list) {
      if (o.colorHex.trim().isNotEmpty) continue;
      String? chosen;
      for (final hex in OfficerColorPalette.hex) {
        final key = hex.toUpperCase();
        if (!manual.contains(key) && !usedAutomatic.contains(key)) {
          chosen = hex;
          break;
        }
      }
      chosen ??= OfficerColorPalette.hex[usedAutomatic.length % OfficerColorPalette.hex.length];
      if (o.id == officer.id) return _hexColor(chosen);
      usedAutomatic.add(chosen.toUpperCase());
    }

    return const Color(0xFF1565C0);
  }

  Future<void> _manageAbsence(Officer officer) async {
    var selectedDate = DateTime.now();
    var absent = await AppDb.instance.hasAbsence(officer.id!, _iso(selectedDate));

    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Ausencia de ${officer.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_today),
                title: const Text('Fecha'),
                subtitle: Text(_dateLabel(selectedDate)),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: selectedDate,
                    firstDate: DateTime.now().subtract(const Duration(days: 365)),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (picked != null) {
                    final value = await AppDb.instance.hasAbsence(officer.id!, _iso(picked));
                    setDialogState(() {
                      selectedDate = picked;
                      absent = value;
                    });
                  }
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Marcar como ausente'),
                subtitle: Text(absent ? 'No participará en la programación de ese día.' : 'Participará normalmente.'),
                value: absent,
                onChanged: (value) => setDialogState(() => absent = value),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () async {
                if (absent) {
                  await AppDb.instance.markAbsence(officer.id!, _iso(selectedDate));
                } else {
                  await AppDb.instance.clearAbsence(officer.id!, _iso(selectedDate));
                }
                if (context.mounted) Navigator.pop(context, true);
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );

    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ausencia actualizada para ${_dateLabel(selectedDate)}.')),
      );
    }
  }

  String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _dateLabel(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Future<String?> _chooseColor({required Officer officer}) async {
    final current = officer.colorHex.trim().toUpperCase();
    final reservedByOther = list
        .where((o) => o.id != officer.id)
        .map((o) => o.colorHex.trim().toUpperCase())
        .where((c) => c.isNotEmpty)
        .toSet();

    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Color del oficial'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: _officerColor(officer),
                  child: const Icon(Icons.auto_awesome, color: Colors.white, size: 18),
                ),
                title: const Text('Automático'),
                subtitle: const Text('La aplicación elige un color libre y diferente.'),
                trailing: current.isEmpty ? const Icon(Icons.check_circle) : null,
                onTap: () => Navigator.pop(dialogContext, ''),
              ),
              const Divider(),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Elegir manualmente', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final hex in OfficerColorPalette.hex)
                    _colorSwatch(
                      dialogContext,
                      hex,
                      selected: current == hex.toUpperCase(),
                      disabled: reservedByOther.contains(hex.toUpperCase()),
                    ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
  }

  Widget _colorSwatch(
    BuildContext dialogContext,
    String hex, {
    required bool selected,
    required bool disabled,
  }) {
    final color = _hexColor(hex);
    return Tooltip(
      message: disabled ? 'Ya está usado por otro oficial' : hex,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: disabled ? null : () => Navigator.pop(dialogContext, hex),
        child: Opacity(
          opacity: disabled ? 0.28 : 1,
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? Colors.black : Colors.white,
                width: selected ? 3 : 2,
              ),
              boxShadow: const [BoxShadow(blurRadius: 3, color: Colors.black26)],
            ),
            child: selected ? const Icon(Icons.check, color: Colors.white) : null,
          ),
        ),
      ),
    );
  }

  Future<void> _edit(Officer officer) async {
    final nameController = TextEditingController(text: officer.name);
    final aliasController = TextEditingController(text: officer.alias);
    final daysOff = await AppDb.instance.weeklyDaysOff(officer.id!);
    final selected = {...daysOff};
    var selectedColor = officer.colorHex.trim();

    final result = await showDialog<_OfficerEditResult>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Editar Oficial'),
          content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Nombre Completo',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: aliasController,
                    decoration: const InputDecoration(
                      labelText: 'Alias / Nombre clave',
                      hintText: 'Ej.: Águila 01',
                      prefixIcon: Icon(Icons.badge_outlined),
                    ),
                  ),
                  const SizedBox(height: 10),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: selectedColor.isEmpty ? _officerColor(officer) : _hexColor(selectedColor),
                    ),
                    title: const Text('Color del oficial'),
                    subtitle: Text(
                      selectedColor.isEmpty ? 'Automático' : selectedColor.toUpperCase(),
                    ),
                    trailing: const Icon(Icons.palette_outlined),
                    onTap: () async {
                      final picked = await _chooseColor(officer: officer);
                      if (picked != null) setDialogState(() => selectedColor = picked);
                    },
                  ),
                  const SizedBox(height: 4),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Días Libres Semanales', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(height: 4),
                  for (final day in days)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(day.$2),
                      value: selected.contains(day.$1),
                      onChanged: (value) {
                        setDialogState(() {
                          if (value == true) {
                            selected.add(day.$1);
                          } else {
                            selected.remove(day.$1);
                          }
                        });
                      },
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                final cleanName = nameController.text.trim();
                if (cleanName.isEmpty) return;
                Navigator.pop(
                  context,
                  _OfficerEditResult(
                    name: cleanName,
                    alias: aliasController.text.trim(),
                    colorHex: selectedColor,
                    daysOff: {...selected},
                  ),
                );
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );

    nameController.dispose();
    aliasController.dispose();

    if (result == null) return;

    if (await AppDb.instance.officerNameExists(result.name, excludingId: officer.id)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ya existe un oficial con ese nombre.')),
        );
      }
      return;
    }

    try {
      await AppDb.instance.updateOfficer(
        id: officer.id!,
        name: result.name,
        alias: result.alias,
        colorHex: result.colorHex,
      );
      await AppDb.instance.setWeeklyDaysOff(officer.id!, result.daysOff);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Oficial actualizado correctamente.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo actualizar el oficial.')),
        );
      }
    }
  }

  Future<void> _delete(Officer officer) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Eliminar oficial'),
        content: Text(
          '¿Eliminar definitivamente a ${officer.name}?\n\n'
          'Esta acción quitará al oficial del registro y también eliminará sus días libres, ausencias, descansos, estadísticas y programaciones guardadas asociadas.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Eliminar definitivamente'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await AppDb.instance.deleteOfficer(officer.id!);
    await _load();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${officer.name} fue eliminado del registro.')),
      );
    }
  }

  Future<void> _add() async {
    final nameController = TextEditingController();
    final aliasController = TextEditingController();
    final selected = <int>{};

    final result = await showDialog<Set<int>>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Agregar Oficial'),
          content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Nombre Completo',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: aliasController,
                    decoration: const InputDecoration(
                      labelText: 'Alias / Nombre clave',
                      hintText: 'Ej.: Águila 01',
                      prefixIcon: Icon(Icons.badge_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Días Libres Semanales', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(height: 4),
                  for (final day in days)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(day.$2),
                      value: selected.contains(day.$1),
                      onChanged: (value) {
                        setDialogState(() {
                          if (value == true) {
                            selected.add(day.$1);
                          } else {
                            selected.remove(day.$1);
                          }
                        });
                      },
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                if (nameController.text.trim().isNotEmpty) {
                  Navigator.pop(context, selected);
                }
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );

    final name = nameController.text.trim();
    final alias = aliasController.text.trim();
    nameController.dispose();
    aliasController.dispose();

    if (result != null) {
      if (await AppDb.instance.officerNameExists(name)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Ya existe un oficial con ese nombre.')),
          );
        }
        return;
      }
      await AppDb.instance.addOfficer(name, alias: alias, daysOff: result);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: buildBrandAppBar(
          context,
          'Oficiales',
          actions: [
            IconButton(
              onPressed: _add,
              icon: const Icon(Icons.person_add),
              tooltip: 'Agregar Oficial',
            ),
          ],
        ),
        body: ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: list.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) {
            final o = list[i];
            final color = _officerColor(o);
            return Card(
              child: ListTile(
                title: Text(o.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                leading: CircleAvatar(
                  backgroundColor: color,
                  child: Text(
                    o.name.isEmpty ? '?' : o.name[0].toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                  ),
                ),
                subtitle: FutureBuilder<Set<int>>(
                  future: AppDb.instance.weeklyDaysOff(o.id!),
                  builder: (context, snapshot) {
                    final selected = snapshot.data ?? {};
                    final names = days.where((d) => selected.contains(d.$1)).map((d) => d.$2).join(', ');
                    final aliasText = o.alias.trim().isEmpty ? '' : ' · Alias: ${o.alias.trim()}';
                    final colorText = o.colorHex.trim().isEmpty ? ' · Color automático' : ' · Color manual';
                    return Text(
                      o.active
                          ? (names.isEmpty
                              ? 'Activo · Sin días libres configurados$aliasText$colorText'
                              : 'Activo · Libre: $names$aliasText$colorText')
                          : 'Inactivo$aliasText$colorText',
                    );
                  },
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PopupMenuButton<String>(
                      tooltip: 'Opciones del oficial',
                      onSelected: (value) {
                        if (value == 'edit') _edit(o);
                        if (value == 'delete') _delete(o);
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'edit',
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.edit),
                            title: Text('Editar oficial'),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.delete_outline),
                            title: Text('Eliminar oficial'),
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      onPressed: o.active ? () => _manageAbsence(o) : null,
                      icon: const Icon(Icons.event_busy),
                      tooltip: 'Registrar ausencia',
                    ),
                    Switch(
                      value: o.active,
                      onChanged: (v) async {
                        await AppDb.instance.setOfficerActive(o.id!, v);
                        _load();
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
}
