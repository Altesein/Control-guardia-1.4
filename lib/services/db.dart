import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../models.dart';

class AppDb {
  AppDb._();
  static final instance = AppDb._();
  Database? _db;

  Future<void> init() async {
    final path = p.join(await getDatabasesPath(), 'control_guardias.db');
    _db = await openDatabase(
      path,
      version: 11,
      onCreate: (db, v) async => _createSchema(db),
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('''CREATE TABLE IF NOT EXISTS weekly_days_off(
            officer_id INTEGER NOT NULL, weekday INTEGER NOT NULL,
            PRIMARY KEY(officer_id, weekday))''');
        }
        if (oldVersion < 3) {
          try { await db.execute('ALTER TABLE assignments ADD COLUMN rest_block INTEGER NOT NULL DEFAULT 0'); } catch (_) {}
          try { await db.execute('ALTER TABLE weekly_stats ADD COLUMN rest1 INTEGER NOT NULL DEFAULT 0'); } catch (_) {}
          try { await db.execute('ALTER TABLE weekly_stats ADD COLUMN rest2 INTEGER NOT NULL DEFAULT 0'); } catch (_) {}
          try { await db.execute('ALTER TABLE weekly_stats ADD COLUMN rest3 INTEGER NOT NULL DEFAULT 0'); } catch (_) {}
          await _insertDefaultRestSettings(db);
        }
        if (oldVersion < 4) await _insertDefaultDeveloperSettings(db);
        if (oldVersion < 5) {
          await db.execute('''CREATE TABLE IF NOT EXISTS daily_rest(
            date TEXT NOT NULL, officer_id INTEGER NOT NULL, rest_block INTEGER NOT NULL,
            PRIMARY KEY(date, officer_id))''');
        }
        if (oldVersion < 6) {
          try { await db.execute('ALTER TABLE weekly_stats ADD COLUMN rest_counts TEXT'); } catch (_) {}
        }
        if (oldVersion < 8) await _createRestProfileSchema(db, migrateLegacy: true);
        if (oldVersion < 9) await _normalizeGeneratedRestProfiles(db);
        if (oldVersion < 10) {
          try { await db.execute("ALTER TABLE officers ADD COLUMN alias TEXT NOT NULL DEFAULT ''"); } catch (_) {}
        }
        if (oldVersion < 11) {
          try { await db.execute("ALTER TABLE officers ADD COLUMN color TEXT NOT NULL DEFAULT ''"); } catch (_) {}
        }
      },
    );
  }

  Future<void> _createSchema(Database db) async {
    await db.execute('''CREATE TABLE officers(
      id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL UNIQUE,
      alias TEXT NOT NULL DEFAULT '', color TEXT NOT NULL DEFAULT '',
      active INTEGER NOT NULL DEFAULT 1)''');
    await db.execute('''CREATE TABLE settings(key TEXT PRIMARY KEY, value TEXT NOT NULL)''');
    await db.execute('''CREATE TABLE absences(
      id INTEGER PRIMARY KEY AUTOINCREMENT, officer_id INTEGER NOT NULL, date TEXT NOT NULL)''');
    await db.execute('''CREATE TABLE weekly_days_off(
      officer_id INTEGER NOT NULL, weekday INTEGER NOT NULL,
      PRIMARY KEY(officer_id, weekday))''');
    await db.execute('''CREATE TABLE assignments(
      id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT NOT NULL, officer_id INTEGER NOT NULL,
      hour INTEGER NOT NULL, long_route INTEGER NOT NULL DEFAULT 0,
      rest_block INTEGER NOT NULL DEFAULT 0, UNIQUE(date, hour))''');
    await db.execute('''CREATE TABLE daily_rest(
      date TEXT NOT NULL, officer_id INTEGER NOT NULL, rest_block INTEGER NOT NULL,
      PRIMARY KEY(date, officer_id))''');
    await db.execute('''CREATE TABLE weekly_stats(
      week TEXT NOT NULL, officer_id INTEGER NOT NULL, routes INTEGER NOT NULL DEFAULT 0,
      long_routes INTEGER NOT NULL DEFAULT 0, rest1 INTEGER NOT NULL DEFAULT 0,
      rest2 INTEGER NOT NULL DEFAULT 0, rest3 INTEGER NOT NULL DEFAULT 0,
      rest_counts TEXT, PRIMARY KEY(week, officer_id))''');
    await _insertDefaultDeveloperSettings(db);
    await _createRestProfileSchema(db, migrateLegacy: false);
  }

  Future<void> _createRestProfileSchema(Database db, {required bool migrateLegacy}) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS rest_profiles(
      officer_count INTEGER PRIMARY KEY, updated_at INTEGER NOT NULL DEFAULT 0)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS rest_profile_blocks(
      id INTEGER PRIMARY KEY AUTOINCREMENT, profile_officer_count INTEGER NOT NULL,
      block_number INTEGER NOT NULL, start TEXT NOT NULL, end TEXT NOT NULL,
      capacity INTEGER NOT NULL DEFAULT 1,
      UNIQUE(profile_officer_count, block_number),
      FOREIGN KEY(profile_officer_count) REFERENCES rest_profiles(officer_count) ON DELETE CASCADE)''');

    if (migrateLegacy) {
      final count = await _getSettingDirect(db, 'rest_block_count');
      final existingProfile = await db.query('rest_profiles', where: 'officer_count=?', whereArgs: [3], limit: 1);
      if (existingProfile.isEmpty) {
        await _ensureRestProfile(db, 3);
        final legacyCount = (int.tryParse(count ?? '') ?? 3).clamp(1, 3).toInt();
        final legacyBlocks = <RestBlock>[];
        for (var i = 1; i <= legacyCount; i++) {
          legacyBlocks.add(RestBlock(
            number: i,
            start: await _getSettingDirect(db, 'rest${i}_start') ?? _defaultStart(i, legacyCount),
            end: await _getSettingDirect(db, 'rest${i}_end') ?? _defaultEnd(i, legacyCount),
            capacity: int.tryParse(await _getSettingDirect(db, 'rest${i}_capacity') ?? '1') ?? 1,
          ));
        }
        await _replaceProfileBlocks(db, 3, legacyBlocks.take(12).toList());
      }
    }
  }

  Future<void> _ensureRestProfile(Database db, int officerCount) async {
    final n = officerCount.clamp(1, 12).toInt();
    await db.insert('rest_profiles', {'officer_count': n, 'updated_at': DateTime.now().millisecondsSinceEpoch}, conflictAlgorithm: ConflictAlgorithm.ignore);
    final rows = await db.query('rest_profile_blocks', where: 'profile_officer_count=?', whereArgs: [n]);
    if (rows.isEmpty) {
      await _replaceProfileBlocks(db, n, _defaultProfileBlocks());
    }
  }


  List<RestBlock> _defaultProfileBlocks() => const [
        RestBlock(number: 1, start: '22:00', end: '00:00', capacity: 1),
        RestBlock(number: 2, start: '00:00', end: '02:00', capacity: 1),
        RestBlock(number: 3, start: '02:00', end: '04:00', capacity: 1),
      ];

  Future<void> _normalizeGeneratedRestProfiles(Database db) async {
    final profiles = await db.query('rest_profiles', columns: ['officer_count']);
    for (final row in profiles) {
      final n = row['officer_count'] as int;
      final rows = await db.query(
        'rest_profile_blocks',
        where: 'profile_officer_count=?',
        whereArgs: [n],
        orderBy: 'block_number',
      );
      final looksGenerated = rows.isNotEmpty &&
          rows.every((r) => (r['capacity'] as int? ?? 1) == 1) &&
          rows.length == n;
      if (looksGenerated && n != 3) {
        await _replaceProfileBlocks(db, n, _defaultProfileBlocks());
      }
    }
  }
  String _hhmm(int h) => '${h.toString().padLeft(2, '0')}:00';
  String _defaultStart(int number, int count) {
    final h = ((6 - count * 2 + (number - 1) * 2) % 24 + 24) % 24;
    return _hhmm(h);
  }
  String _defaultEnd(int number, int count) {
    final h = (((6 - count * 2 + (number - 1) * 2) + 2) % 24 + 24) % 24;
    return _hhmm(h);
  }

  Future<void> _replaceProfileBlocks(Database db, int officerCount, List<RestBlock> blocks) async {
    await db.delete('rest_profile_blocks', where: 'profile_officer_count=?', whereArgs: [officerCount]);
    for (final block in blocks) {
      await db.insert('rest_profile_blocks', {
        'profile_officer_count': officerCount,
        'block_number': block.number,
        'start': block.start,
        'end': block.end,
        'capacity': block.capacity.clamp(0, 99),
      });
    }
  }

  Future<void> _insertDefaultRestSettings(Database db) async {
    final values = {
      'rest_block_count': '3',
      'rest1_start': '22:00', 'rest1_end': '01:00',
      'rest2_start': '01:00', 'rest2_end': '03:30',
      'rest3_start': '03:30', 'rest3_end': '06:00',
      'rest1_capacity': '1', 'rest2_capacity': '1', 'rest3_capacity': '1',
    };
    for (final e in values.entries) {
      await db.insert('settings', {'key': e.key, 'value': e.value}, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  Future<void> _insertDefaultDeveloperSettings(Database db) async {
    final values = {
      'developer_name': 'Nelson Grateron',
      'developer_contact': 'Correo: Nelson_the_master@hotmail.com · Teléfono: 0424-591-2742',
      'developer_email': 'Nelson_the_master@hotmail.com',
      'developer_phone': '0424-591-2742',
    };
    for (final e in values.entries) {
      await db.insert('settings', {'key': e.key, 'value': e.value}, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  Database get db => _db!;

  Future<List<Officer>> officers() async => (await db.query('officers', orderBy: 'name COLLATE NOCASE')).map(Officer.fromMap).toList();

  Future<void> addOfficer(String name, {String alias = '', Set<int> daysOff = const {}}) async {
    final clean = name.trim();
    if (clean.isEmpty) return;
    final cleanAlias = alias.trim();
    await db.insert(
      'officers',
      {'name': clean, 'alias': cleanAlias, 'color': '', 'active': 1},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    final rows = await db.query('officers', where: 'name=?', whereArgs: [clean], limit: 1);
    if (rows.isNotEmpty) await setWeeklyDaysOff(rows.first['id'] as int, daysOff);
  }

  Future<bool> officerNameExists(String name, {int? excludingId}) async {
    final clean = name.trim();
    if (clean.isEmpty) return false;
    final rows = await db.query('officers', where: 'name=?', whereArgs: [clean], limit: 1);
    if (rows.isEmpty) return false;
    return excludingId == null || (rows.first['id'] as int) != excludingId;
  }

  Future<void> updateOfficer({
    required int id,
    required String name,
    required String alias,
    required String colorHex,
  }) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) return;
    await db.update(
      'officers',
      {
        'name': cleanName,
        'alias': alias.trim(),
        'color': colorHex.trim(),
      },
      where: 'id=?',
      whereArgs: [id],
    );
  }

  Future<void> setOfficerActive(int id, bool active) async =>
      db.update('officers', {'active': active ? 1 : 0}, where: 'id=?', whereArgs: [id]);

  Future<void> setOfficerAlias(int id, String alias) async =>
      db.update('officers', {'alias': alias.trim()}, where: 'id=?', whereArgs: [id]);

  Future<void> setOfficerColor(int id, String colorHex) async =>
      db.update('officers', {'color': colorHex.trim()}, where: 'id=?', whereArgs: [id]);

  /// Permanently removes an officer and their current configuration/history
  /// records. The UI asks for confirmation before calling this method.
  Future<void> deleteOfficer(int id) async {
    final batch = db.batch();
    batch.delete('weekly_days_off', where: 'officer_id=?', whereArgs: [id]);
    batch.delete('absences', where: 'officer_id=?', whereArgs: [id]);
    batch.delete('daily_rest', where: 'officer_id=?', whereArgs: [id]);
    batch.delete('weekly_stats', where: 'officer_id=?', whereArgs: [id]);
    batch.delete('assignments', where: 'officer_id=?', whereArgs: [id]);
    batch.delete('officers', where: 'id=?', whereArgs: [id]);
    await batch.commit(noResult: true);
  }

  Future<Set<int>> weeklyDaysOff(int officerId) async =>
      (await db.query('weekly_days_off', columns: ['weekday'], where: 'officer_id=?', whereArgs: [officerId])).map((e) => e['weekday'] as int).toSet();

  Future<Map<int, Set<int>>> weeklyDaysOffForOfficers(List<int> officerIds) async {
    if (officerIds.isEmpty) return {};
    final placeholders = List.filled(officerIds.length, '?').join(',');
    final rows = await db.query('weekly_days_off', where: 'officer_id IN ($placeholders)', whereArgs: officerIds);
    final result = <int, Set<int>>{for (final id in officerIds) id: <int>{}};
    for (final row in rows) result[row['officer_id'] as int]!.add(row['weekday'] as int);
    return result;
  }

  Future<void> setWeeklyDaysOff(int officerId, Set<int> days) async {
    final batch = db.batch();
    batch.delete('weekly_days_off', where: 'officer_id=?', whereArgs: [officerId]);
    for (final day in days) if (day >= 1 && day <= 7) batch.insert('weekly_days_off', {'officer_id': officerId, 'weekday': day});
    await batch.commit(noResult: true);
  }

  Future<String?> _getSettingDirect(Database database, String key) async {
    final rows = await database.query('settings', where: 'key=?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<String> setting(String key, {String fallback = ''}) async =>
      await _getSettingDirect(db, key) ?? fallback;

  Future<void> setSetting(String key, String value) async =>
      db.insert('settings', {'key': key, 'value': value}, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<RestProfile> restProfile(int officerCount) async {
    final n = officerCount.clamp(1, 12).toInt();
    await _ensureRestProfile(db, n);
    final rows = await db.query('rest_profile_blocks', where: 'profile_officer_count=?', whereArgs: [n], orderBy: 'block_number');
    final blocks = rows.map((r) => RestBlock(
      number: r['block_number'] as int,
      start: r['start'] as String,
      end: r['end'] as String,
      capacity: r['capacity'] as int? ?? 1,
    )).toList();
    return RestProfile(officerCount: n, blocks: blocks);
  }

  Future<List<RestProfile>> restProfiles({int minOfficers = 1, int maxOfficers = 12}) async {
    final lo = minOfficers.clamp(1, 12).toInt();
    final hi = maxOfficers.clamp(lo, 12).toInt();
    final result = <RestProfile>[];
    for (var n = lo; n <= hi; n++) result.add(await restProfile(n));
    return result;
  }

  Future<List<RestBlock>> restBlocks({int? officerCount}) async {
    final n = officerCount ?? 3;
    return (await restProfile(n)).blocks;
  }

  Future<void> setRestBlock(int officerCount, int number, String start, String end, {int? capacity}) async {
    await _ensureRestProfile(db, officerCount);
    final values = <String, Object?>{'start': start, 'end': end};
    if (capacity != null) values['capacity'] = capacity.clamp(0, 99);
    await db.update('rest_profile_blocks', values, where: 'profile_officer_count=? AND block_number=?', whereArgs: [officerCount, number]);
    await db.update('rest_profiles', {'updated_at': DateTime.now().millisecondsSinceEpoch}, where: 'officer_count=?', whereArgs: [officerCount]);
  }

  Future<void> setRestBlockCapacity(int officerCount, int number, int capacity) async =>
      setRestBlock(officerCount, number, (await restProfile(officerCount)).blocks[number - 1].start, (await restProfile(officerCount)).blocks[number - 1].end, capacity: capacity);

  Future<void> setRestBlockCount(int officerCount, int count) async {
    final n = officerCount.clamp(1, 12).toInt();
    final target = count.clamp(1, n).toInt();
    await _ensureRestProfile(db, n);
    final current = (await restProfile(n)).blocks;
    if (target > current.length) {
      for (var i = current.length + 1; i <= target; i++) {
        await db.insert('rest_profile_blocks', {
          'profile_officer_count': n, 'block_number': i,
          'start': _defaultStart(i, target), 'end': _defaultEnd(i, target), 'capacity': 1,
        });
      }
    } else if (target < current.length) {
      await db.delete('rest_profile_blocks', where: 'profile_officer_count=? AND block_number>?', whereArgs: [n, target]);
    }
    await db.update('rest_profiles', {'updated_at': DateTime.now().millisecondsSinceEpoch}, where: 'officer_count=?', whereArgs: [n]);
  }

  Future<void> addRestBlock({int officerCount = 3}) async {
    final current = await restProfile(officerCount);
    await setRestBlockCount(officerCount, current.blocks.length + 1);
  }

  Future<void> removeRestBlock(int number, {int officerCount = 3}) async {
    final current = await restProfile(officerCount);
    if (current.blocks.length <= 1 || number < 1 || number > current.blocks.length) return;
    await db.delete('rest_profile_blocks', where: 'profile_officer_count=? AND block_number=?', whereArgs: [officerCount, number]);
    final remaining = current.blocks.where((b) => b.number != number).toList();
    await _replaceProfileBlocks(db, officerCount, [for (var i = 0; i < remaining.length; i++) RestBlock(number: i + 1, start: remaining[i].start, end: remaining[i].end, capacity: remaining[i].capacity)]);
  }

  Future<void> markAbsence(int officerId, String date) async => db.insert('absences', {'officer_id': officerId, 'date': date}, conflictAlgorithm: ConflictAlgorithm.ignore);
  Future<void> clearAbsence(int officerId, String date) async => db.delete('absences', where: 'officer_id=? AND date=?', whereArgs: [officerId, date]);
  Future<bool> hasAbsence(int officerId, String date) async => (await db.query('absences', columns: ['id'], where: 'officer_id=? AND date=?', whereArgs: [officerId, date], limit: 1)).isNotEmpty;
  Future<Set<int>> absentIds(String date) async => (await db.query('absences', where: 'date=?', whereArgs: [date])).map((e) => e['officer_id'] as int).toSet();

  Future<void> clearAssignmentsForDate(String date) async {
    await db.delete('assignments', where: 'date=?', whereArgs: [date]);
    await db.delete('daily_rest', where: 'date=?', whereArgs: [date]);
  }

  Future<void> saveAssignments(List<Assignment> list, Map<String, int> officerIds) async {
    final batch = db.batch();
    for (final a in list) {
      final id = officerIds[a.officer];
      if (id == null) continue;
      batch.insert('assignments', {'date': a.date, 'officer_id': id, 'hour': a.hour, 'long_route': a.longRoute ? 1 : 0, 'rest_block': a.restBlock}, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<void> saveDailyRest(String date, Map<int, int> restByOfficer) async {
    final batch = db.batch();
    batch.delete('daily_rest', where: 'date=?', whereArgs: [date]);
    for (final e in restByOfficer.entries) batch.insert('daily_rest', {'date': date, 'officer_id': e.key, 'rest_block': e.value});
    await batch.commit(noResult: true);
  }

  Future<Map<int, int>> dailyRestForDate(String date) async {
    final rows = await db.query('daily_rest', where: 'date=?', whereArgs: [date]);
    return {for (final r in rows) r['officer_id'] as int: r['rest_block'] as int};
  }

  Future<List<Map<String, Object?>>> dailyRestForWeek(String startDate, String endDate) async => db.rawQuery('''
    SELECT r.date, r.officer_id, r.rest_block, o.name FROM daily_rest r JOIN officers o ON o.id=r.officer_id
    WHERE r.date BETWEEN ? AND ? ORDER BY r.date, o.name COLLATE NOCASE''', [startDate, endDate]);

  Future<void> saveWeeklyStats(String week, Map<int, WeeklyStats> stats) async {
    final batch = db.batch();
    for (final e in stats.entries) {
      batch.insert('weekly_stats', {
        'week': week, 'officer_id': e.key, 'routes': e.value.routes, 'long_routes': e.value.longRoutes,
        'rest1': e.value.restCount(1), 'rest2': e.value.restCount(2), 'rest3': e.value.restCount(3),
        'rest_counts': jsonEncode(e.value.restCounts),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  List<int> _decodeRestCounts(Map<String, Object?> row) {
    final raw = row['rest_counts'] as String?;
    if (raw != null && raw.isNotEmpty) {
      try { return (jsonDecode(raw) as List).map((e) => (e as num).toInt()).toList(); } catch (_) {}
    }
    return [row['rest1'] as int? ?? 0, row['rest2'] as int? ?? 0, row['rest3'] as int? ?? 0];
  }

  Future<Map<int, WeeklyStats>> weeklyStats(String week) async {
    final rows = await db.query('weekly_stats', where: 'week=?', whereArgs: [week]);
    return {for (final r in rows) r['officer_id'] as int: WeeklyStats(routes: r['routes'] as int? ?? 0, longRoutes: r['long_routes'] as int? ?? 0, restCounts: _decodeRestCounts(r))};
  }

  Future<List<Map<String, Object?>>> assignmentsForDate(String date) async => db.rawQuery('''
    SELECT a.hour, a.long_route, a.rest_block, o.name FROM assignments a JOIN officers o ON o.id=a.officer_id
    WHERE a.date=? ORDER BY CASE WHEN a.hour >= 20 THEN a.hour ELSE a.hour + 24 END''', [date]);

  Future<List<Map<String, Object?>>> assignmentsForWeek(String startDate, String endDate) async => db.rawQuery('''
    SELECT a.date, a.hour, a.long_route, a.rest_block, o.id AS officer_id, o.name FROM assignments a JOIN officers o ON o.id=a.officer_id
    WHERE a.date BETWEEN ? AND ? ORDER BY a.date, CASE WHEN a.hour >= 20 THEN a.hour ELSE a.hour + 24 END''', [startDate, endDate]);
}
