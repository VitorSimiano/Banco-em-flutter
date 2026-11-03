import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/category.dart';
import '../models/note.dart';
import '../models/sync_status.dart';

/// Acesso ao banco local (SQLite). É um Singleton: toda a aplicação usa a
/// mesma conexão. Aqui só existe SQL; as regras de sincronização ficam no
/// `NotesRepository`.
class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();

  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) {
      return _database!;
    }
    _database = await _initDB('bloco_notas.db');
    return _database!;
  }

  Future<Database> _initDB(String fileName) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, fileName);

    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE notes(
        id TEXT PRIMARY KEY,
        uid TEXT NOT NULL,
        title TEXT NOT NULL,
        content TEXT NOT NULL,
        category_id TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        archived INTEGER NOT NULL DEFAULT 0,
        deleted_at INTEGER,
        sync_status INTEGER NOT NULL DEFAULT 1
      )
    ''');
    await db.execute('CREATE INDEX idx_notes_uid ON notes(uid)');

    await db.execute('''
      CREATE TABLE categories(
        id TEXT PRIMARY KEY,
        uid TEXT NOT NULL,
        name TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        sync_status INTEGER NOT NULL DEFAULT 1
      )
    ''');
    await db.execute('CREATE INDEX idx_categories_uid ON categories(uid)');

    await db.execute('''
      CREATE TABLE meta(
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }

  // ---------------------------------------------------------------- Notas

  /// Insere ou substitui a nota (mesmo ID).
  Future<void> upsertNote(Note note) async {
    final db = await database;
    await db.insert(
      'notes',
      note.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Todas as linhas do usuário, inclusive lixeira e exclusões pendentes.
  /// Usado pela sincronização.
  Future<List<Note>> getAllNotes(String uid) async {
    final db = await database;
    final rows = await db.query('notes', where: 'uid = ?', whereArgs: [uid]);
    return rows.map(Note.fromMap).toList();
  }

  /// Notas para exibição, já filtradas pela visão (ativas, arquivadas ou
  /// lixeira), categoria e ordenação. Linhas com exclusão pendente ficam ocultas.
  Future<List<Note>> getNotes(
    String uid, {
    NoteView view = NoteView.active,
    String? categoryId,
    NoteSort sort = NoteSort.updatedDesc,
  }) async {
    final db = await database;

    final where = StringBuffer('uid = ? AND sync_status != ?');
    final args = <Object?>[uid, SyncStatus.pendingDelete];

    switch (view) {
      case NoteView.active:
        where.write(' AND deleted_at IS NULL AND archived = 0');
        break;
      case NoteView.archived:
        where.write(' AND deleted_at IS NULL AND archived = 1');
        break;
      case NoteView.trash:
        where.write(' AND deleted_at IS NOT NULL');
        break;
    }

    if (categoryId != null) {
      where.write(' AND category_id = ?');
      args.add(categoryId);
    }

    final rows = await db.query(
      'notes',
      where: where.toString(),
      whereArgs: args,
      orderBy: sort.orderBy,
    );
    return rows.map(Note.fromMap).toList();
  }

  Future<List<Note>> getNotesByCategory(String uid, String categoryId) async {
    final db = await database;
    final rows = await db.query(
      'notes',
      where: 'uid = ? AND category_id = ?',
      whereArgs: [uid, categoryId],
    );
    return rows.map(Note.fromMap).toList();
  }

  /// Marca a nota como sincronizada, mas somente se ela não foi editada
  /// enquanto o envio estava em andamento (compara `updated_at`).
  Future<void> markNoteSynced(String id, int updatedAt) async {
    final db = await database;
    await db.update(
      'notes',
      {'sync_status': SyncStatus.synced},
      where: 'id = ? AND updated_at = ?',
      whereArgs: [id, updatedAt],
    );
  }

  Future<void> deleteNoteRow(String id) async {
    final db = await database;
    await db.delete('notes', where: 'id = ?', whereArgs: [id]);
  }

  /// Quantidade de registros (notas + categorias) aguardando envio.
  Future<int> countPending(String uid) async {
    final db = await database;
    final notes = Sqflite.firstIntValue(
      await db.rawQuery(
        'SELECT COUNT(*) FROM notes WHERE uid = ? AND sync_status != ?',
        [uid, SyncStatus.synced],
      ),
    );
    final categories = Sqflite.firstIntValue(
      await db.rawQuery(
        'SELECT COUNT(*) FROM categories WHERE uid = ? AND sync_status != ?',
        [uid, SyncStatus.synced],
      ),
    );
    return (notes ?? 0) + (categories ?? 0);
  }

  // ----------------------------------------------------------- Categorias

  Future<void> upsertCategory(Category category) async {
    final db = await database;
    await db.insert(
      'categories',
      category.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Category?> getCategory(String id) async {
    final db = await database;
    final rows = await db.query(
      'categories',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : Category.fromMap(rows.first);
  }

  /// Categorias para exibição (sem as que aguardam exclusão).
  Future<List<Category>> getCategories(String uid) async {
    final db = await database;
    final rows = await db.query(
      'categories',
      where: 'uid = ? AND sync_status != ?',
      whereArgs: [uid, SyncStatus.pendingDelete],
      orderBy: 'name COLLATE NOCASE ASC',
    );
    return rows.map(Category.fromMap).toList();
  }

  Future<List<Category>> getAllCategories(String uid) async {
    final db = await database;
    final rows = await db.query(
      'categories',
      where: 'uid = ?',
      whereArgs: [uid],
    );
    return rows.map(Category.fromMap).toList();
  }

  Future<void> markCategorySynced(String id, int updatedAt) async {
    final db = await database;
    await db.update(
      'categories',
      {'sync_status': SyncStatus.synced},
      where: 'id = ? AND updated_at = ?',
      whereArgs: [id, updatedAt],
    );
  }

  Future<void> deleteCategoryRow(String id) async {
    final db = await database;
    await db.delete('categories', where: 'id = ?', whereArgs: [id]);
  }

  // ----------------------------------------------------------------- Meta

  Future<String?> getMeta(String key) async {
    final db = await database;
    final rows = await db.query(
      'meta',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<void> setMeta(String key, String value) async {
    final db = await database;
    await db.insert(
      'meta',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
