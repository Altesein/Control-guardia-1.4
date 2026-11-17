class Officer {
  final int? id;
  final String name;
  final String alias;
  final bool active;
  /// Empty means automatic color assignment. Otherwise this is an ARGB hex color, e.g. #1565C0.
  final String colorHex;

  Officer({
    this.id,
    required this.name,
    this.alias = '',
    this.active = true,
    this.colorHex = '',
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'alias': alias,
        'active': active ? 1 : 0,
        'color': colorHex,
      };

  factory Officer.fromMap(Map<String, Object?> m) => Officer(
        id: m['id'] as int?,
        name: m['name'] as String,
        alias: (m['alias'] as String?) ?? '',
        active: (m['active'] as int? ?? 1) == 1,
        colorHex: (m['color'] as String?) ?? '',
      );
}



/// Colores deliberadamente separados para que los oficiales sean fáciles de
/// distinguir. Los colores no se asignan por nombre: se asignan por posición
/// entre los oficiales que usan el modo automático.
class OfficerColorPalette {
  static const hex = <String>[
    '#1565C0',
    '#00897B',
    '#EF6C00',
    '#6A1B9A',
    '#C62828',
    '#00695C',
    '#455A64',
    '#AD1457',
    '#2E7D32',
    '#5D4037',
    '#283593',
    '#00838F',
    '#7B1FA2',
    '#9E9D24',
    '#37474F',
    '#D84315',
  ];
}

class Assignment {
  final String date;
  final String officer;
  final int hour;
  final bool longRoute;
  final int restBlock;

  Assignment({
    required this.date,
    required this.officer,
    required this.hour,
    this.longRoute = false,
    this.restBlock = 0,
  });

  Map<String, Object?> toMap() => {
        'date': date,
        'officer': officer,
        'hour': hour,
        'long_route': longRoute ? 1 : 0,
        'rest_block': restBlock,
      };
}

/// A single configurable rest/turn window inside an officer-count profile.
class RestBlock {
  final int number;
  final String start;
  final String end;
  final int capacity;

  const RestBlock({
    required this.number,
    required this.start,
    required this.end,
    this.capacity = 1,
  });

  String get label => 'Descanso N° $number';
}

/// Complete configuration for a specific number of officers available that day.
class RestProfile {
  final int officerCount;
  final List<RestBlock> blocks;

  const RestProfile({required this.officerCount, required this.blocks});
}

class DailyPlan {
  final List<Assignment> assignments;
  final Map<int, int> restByOfficer;

  const DailyPlan({required this.assignments, required this.restByOfficer});
}

class WeeklyStats {
  final int routes;
  final int longRoutes;
  final List<int> restCounts;

  const WeeklyStats({
    this.routes = 0,
    this.longRoutes = 0,
    this.restCounts = const [0, 0, 0],
  });

  int restCount(int block) =>
      block >= 1 && block <= restCounts.length ? restCounts[block - 1] : 0;
}
