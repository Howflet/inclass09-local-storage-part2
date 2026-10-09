import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';

class DatabaseHelper {
  static const _databaseName = "MyDatabase.db";
  // Part II: raised from 1 to 2. Same filename, so the existing Part I file is
  // opened and upgraded instead of replaced.
  static const _databaseVersion = 2;
  static const table = 'my_table';
  static const columnId = '_id';
  static const columnName = 'name';
  static const columnAge = 'age';

  // Part II catalogue tables (version 2).
  static const foldersTable = 'folders';
  static const cardsTable = 'cards';
  static const cardsFolderIndex = 'idx_cards_folder_id';

  late Database _db;

  // Shared connection for the catalogue repository. Widgets never use this.
  Database get database => _db;

// this opens the database (and creates it if it doesn't exist)
  Future<void> init() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final path = join(documentsDirectory.path, _databaseName);
    _db = await openDatabase(
      path,
      version: _databaseVersion,
      // Runs before onCreate/onUpgrade on every open. Without this, SQLite
      // ignores the FOREIGN KEY clause and ON DELETE CASCADE does nothing.
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

// Fresh install: build the complete version-2 schema (Part I + catalogue).
// sqflite already wraps onCreate in a transaction, so no nested transaction.
  Future _onCreate(Database db, int version) async {
    await createPartOneTables(db);
    await createCatalogueTables(db);
  }

// Existing install: only add what each older version is missing. The Part I
// table is never dropped or recreated here, so its rows are left untouched.
// Errors are not caught: a failed upgrade rolls back and opening fails visibly.
  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await createCatalogueTables(db);
    }
  }

// SQL code to create the database table (unchanged Part I statement)
  static Future<void> createPartOneTables(Database db) async {
    await db.execute('''
CREATE TABLE $table (
$columnId INTEGER PRIMARY KEY,
$columnName TEXT NOT NULL,
$columnAge INTEGER NOT NULL
)
''');
  }

// Part II: parent folders, child cards, and the folder_id lookup index.
  static Future<void> createCatalogueTables(Database db) async {
    await db.execute('''
CREATE TABLE $foldersTable (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL UNIQUE,
  created_at TEXT NOT NULL
)
''');
    await db.execute('''
CREATE TABLE $cardsTable (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  title TEXT NOT NULL,
  suit TEXT NOT NULL,
  notes TEXT NOT NULL DEFAULT '',
  image_ref TEXT,
  folder_id INTEGER NOT NULL,
  FOREIGN KEY (folder_id) REFERENCES $foldersTable(id) ON DELETE CASCADE
)
''');
    await db.execute(
        'CREATE INDEX $cardsFolderIndex ON $cardsTable(folder_id)');
  }

// Read-only schema diagnostics for T1 evidence (shown on the Diagnostics
// screen). Nothing here writes or changes a PRAGMA setting.
  Future<Map<String, Object?>> diagnostics() async {
    final version = Sqflite.firstIntValue(
        await _db.rawQuery('PRAGMA user_version'));
    final foreignKeys = Sqflite.firstIntValue(
        await _db.rawQuery('PRAGMA foreign_keys'));
    final tables = await _db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' "
        "AND name NOT LIKE 'sqlite_%' AND name != 'android_metadata' "
        'ORDER BY name');
    return {
      'path': _db.path,
      'user_version': version,
      'foreign_keys': foreignKeys,
      'tables': tables.map((r) => r['name']).toList(),
      'foreign_key_list(cards)':
          await _db.rawQuery('PRAGMA foreign_key_list($cardsTable)'),
      'index_list(cards)':
          await _db.rawQuery('PRAGMA index_list($cardsTable)'),
      'part_one_rows': await queryAllRows(),
      'part_one_count': await queryRowCount(),
    };
  }

// Helper methods
// Inserts a row in the database where each key in the
//Map is a column name
// and the value is the column value. The return value
//is the id of the
// inserted row.
  Future<int> insert(Map<String, dynamic> row) async {
    return await _db.insert(table, row);
  }

// All of the rows are returned as a list of maps, where each map is
// a key-value list of columns.
  Future<List<Map<String, dynamic>>> queryAllRows() async {
    // Added: explicit ID order so the UI's ascending-ID list is guaranteed.
    return await _db.query(table, orderBy: '$columnId ASC');
  }

// All of the methods (insert, query, update, delete) can also be done using
// raw SQL commands. This method uses a raw query to give the row count.
  Future<int> queryRowCount() async {
    final results = await _db.rawQuery('SELECT COUNT(*) FROM $table');
    return Sqflite.firstIntValue(results) ?? 0;
  }

// We are assuming here that the id column in the map is set. The other
// column values will be used to update the row.
  Future<int> update(Map<String, dynamic> row) async {
    int id = row[columnId];
    return await _db.update(
      table,
      row,
      where: '$columnId = ?',
      whereArgs: [id],
    );
  }

// Deletes the row specified by the id. The number of affected rows is
// returned. This should be 1 as long as the row exists.
  Future<int> delete(int id) async {
    return await _db.delete(
      table,
      where: '$columnId = ?',
      whereArgs: [id],
    );
  }
}
