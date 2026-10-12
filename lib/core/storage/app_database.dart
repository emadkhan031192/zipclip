import 'package:sqflite/sqflite.dart';

import '../engine/download_store.dart';
import '../models/media.dart';

/// sqflite-backed [DownloadStore]: download queue/tasks + saved-file history.
class AppDatabase implements DownloadStore {
  AppDatabase._(this._db);

  final Database _db;

  static Future<AppDatabase> open(String path) async {
    final db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE tasks(
            id TEXT PRIMARY KEY,
            normalized_url TEXT NOT NULL,
            original_url TEXT NOT NULL,
            title TEXT NOT NULL,
            author TEXT NOT NULL,
            thumb_source TEXT NOT NULL,
            format TEXT NOT NULL,
            quality_label TEXT NOT NULL,
            stream_url TEXT NOT NULL,
            container TEXT NOT NULL,
            status TEXT NOT NULL,
            bytes_done INTEGER NOT NULL,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            duration_ms INTEGER,
            total_bytes INTEGER,
            segments_json TEXT,
            file_uri TEXT,
            error TEXT,
            elapsed_ms INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE history(
            id TEXT PRIMARY KEY,
            normalized_url TEXT NOT NULL,
            original_url TEXT NOT NULL,
            title TEXT NOT NULL,
            author TEXT NOT NULL,
            thumb_path TEXT NOT NULL,
            format TEXT NOT NULL,
            quality_label TEXT NOT NULL,
            size_bytes INTEGER NOT NULL,
            file_uri TEXT NOT NULL,
            saved_at INTEGER NOT NULL,
            duration_ms INTEGER
          )
        ''');
        await db.execute(
            'CREATE INDEX idx_history_url ON history(normalized_url)',);
        await db.execute(
            'CREATE INDEX idx_history_saved ON history(saved_at DESC)',);
      },
    );
    return AppDatabase._(db);
  }

  Future<void> close() => _db.close();

  @override
  Future<void> saveTask(StoredTask task) async {
    await _db.insert('tasks', task.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,);
  }

  @override
  Future<void> updateTask(StoredTask task) async {
    await _db.update('tasks', task.toMap(),
        where: 'id = ?', whereArgs: [task.id],);
  }

  @override
  Future<StoredTask?> getTask(String id) async {
    final rows =
        await _db.query('tasks', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return StoredTask.fromMap(rows.first);
  }

  @override
  Future<List<StoredTask>> listTasks() async {
    final rows =
        await _db.query('tasks', orderBy: 'created_at DESC');
    return rows.map(StoredTask.fromMap).toList();
  }

  @override
  Future<void> deleteTask(String id) async {
    await _db.delete('tasks', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> addHistory(SavedItem item) async {
    await _db.insert('history', item.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,);
  }

  @override
  Future<SavedItem?> findByUrl(String normalizedUrl) async {
    final rows = await _db.query(
      'history',
      where: 'normalized_url = ?',
      whereArgs: [normalizedUrl],
      orderBy: 'saved_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return SavedItem.fromMap(rows.first);
  }

  @override
  Future<List<SavedItem>> listHistory(
      {SaveFormat? format, int? limit,}) async {
    final rows = await _db.query(
      'history',
      where: format == null ? null : 'format = ?',
      whereArgs: format == null ? null : [format.name],
      orderBy: 'saved_at DESC',
      limit: limit,
    );
    return rows.map(SavedItem.fromMap).toList();
  }

  @override
  Future<void> deleteHistory(String id) async {
    await _db.delete('history', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> clearHistory() async {
    await _db.delete('history');
  }

  @override
  Future<int> historyCount() async {
    final rows =
        await _db.rawQuery('SELECT COUNT(*) AS c FROM history');
    return ((rows.first['c'] as num?) ?? 0).toInt();
  }
}
