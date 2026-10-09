import 'package:sqflite/sqflite.dart';

import 'database_helper.dart';
import 'models/card_record.dart';
import 'models/folder.dart';

// ============================================================================
// Catalogue repository: the only place the folder/card screens reach SQL.
// ============================================================================
// Summary: Every value from the user is bound with `?` placeholders
// (whereArgs / insert maps); nothing is concatenated into a SQL string. Every
// update/delete targets an integer ID and returns the affected-row count so
// the UI can treat 0 as "not found" rather than success.

// Thrown when a folder name already exists (UNIQUE constraint).
class DuplicateFolderNameException implements Exception {
  final String name;
  const DuplicateFolderNameException(this.name);

  @override
  String toString() => 'A folder named "$name" already exists.';
}

// Result of deleting a folder: parent rows removed, children removed by the
// cascade, and children still pointing at that ID afterward (should be 0).
class FolderDeleteResult {
  final int foldersDeleted;
  final int cardsCascaded;
  final int orphansRemaining;

  const FolderDeleteResult(
      this.foldersDeleted, this.cardsCascaded, this.orphansRemaining);
}

class CatalogueRepository {
  final DatabaseHelper helper;

  CatalogueRepository(this.helper);

  Database get _db => helper.database;

  // ---------------------------------------------------------------- folders

  // Returns the new folder ID. Never uses ConflictAlgorithm.replace: replacing
  // a parent would delete it and cascade to its cards.
  Future<int> insertFolder(String name) async {
    final folder = Folder(
      name: name,
      createdAt: DateTime.now().toIso8601String(),
    );
    try {
      return await _db.insert(DatabaseHelper.foldersTable, folder.toMap());
    } on DatabaseException catch (e) {
      if (e.isUniqueConstraintError()) {
        throw DuplicateFolderNameException(name);
      }
      rethrow;
    }
  }

  // LEFT JOIN keeps empty folders with a count of 0.
  Future<List<Folder>> getFoldersWithCounts() async {
    final rows = await _db.rawQuery('''
SELECT f.id, f.name, f.created_at, COUNT(c.id) AS card_count
FROM ${DatabaseHelper.foldersTable} f
LEFT JOIN ${DatabaseHelper.cardsTable} c ON c.folder_id = f.id
GROUP BY f.id
ORDER BY f.name COLLATE NOCASE ASC, f.id ASC
''');
    return rows.map(Folder.fromMap).toList();
  }

  Future<Folder?> getFolder(int id) async {
    final rows = await _db.query(
      DatabaseHelper.foldersTable,
      where: 'id = ?',
      whereArgs: [id],
    );
    return rows.isEmpty ? null : Folder.fromMap(rows.first);
  }

  // Counts the children, deletes the parent (the FK cascade removes the
  // children), then re-checks for leftovers, all in one transaction.
  Future<FolderDeleteResult> deleteFolder(int id) async {
    return _db.transaction((txn) async {
      final children = Sqflite.firstIntValue(await txn.rawQuery(
              'SELECT COUNT(*) FROM ${DatabaseHelper.cardsTable} '
              'WHERE folder_id = ?',
              [id])) ??
          0;
      final deleted = await txn.delete(
        DatabaseHelper.foldersTable,
        where: 'id = ?',
        whereArgs: [id],
      );
      final orphans = Sqflite.firstIntValue(await txn.rawQuery(
              'SELECT COUNT(*) FROM ${DatabaseHelper.cardsTable} '
              'WHERE folder_id = ?',
              [id])) ??
          0;
      return FolderDeleteResult(
          deleted, deleted == 0 ? 0 : children - orphans, orphans);
    });
  }

  // ------------------------------------------------------------------ cards

  Future<List<CardRecord>> getCards(int folderId) async {
    final rows = await _db.query(
      DatabaseHelper.cardsTable,
      where: 'folder_id = ?',
      whereArgs: [folderId],
      orderBy: 'title COLLATE NOCASE ASC, id ASC',
    );
    return rows.map(CardRecord.fromMap).toList();
  }

  Future<CardRecord?> getCard(int id) async {
    final rows = await _db.query(
      DatabaseHelper.cardsTable,
      where: 'id = ?',
      whereArgs: [id],
    );
    return rows.isEmpty ? null : CardRecord.fromMap(rows.first);
  }

  // Returns the new card ID. A folder_id that does not exist is rejected by
  // the foreign key (foreign_keys = ON).
  Future<int> insertCard(CardRecord card) async {
    return _db.insert(DatabaseHelper.cardsTable, card.toMap());
  }

  // Returns the number of rows changed (1, or 0 if the ID no longer exists).
  Future<int> updateCard(CardRecord card) async {
    final id = card.id;
    if (id == null) {
      throw ArgumentError('updateCard needs a card with an id');
    }
    return _db.update(
      DatabaseHelper.cardsTable,
      card.toMap()..remove('id'),
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteCard(int id) async {
    return _db.delete(
      DatabaseHelper.cardsTable,
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
