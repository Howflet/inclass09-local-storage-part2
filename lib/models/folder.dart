// ============================================================================
// Folder model (parent row in `folders`)
// ============================================================================
// Summary: Typed view of one folder row. `cardCount` is not a column; it is
// filled only by the repository's LEFT JOIN query and ignored by toMap().
class Folder {
  final int? id; // null until SQLite assigns one on insert
  final String name;
  final String createdAt; // ISO-8601 string
  final int cardCount;

  const Folder({
    this.id,
    required this.name,
    required this.createdAt,
    this.cardCount = 0,
  });

  factory Folder.fromMap(Map<String, Object?> map) {
    return Folder(
      id: map['id'] as int,
      name: map['name'] as String,
      createdAt: map['created_at'] as String,
      cardCount: (map['card_count'] as int?) ?? 0,
    );
  }

  // Omits `id` when it is null so SQLite generates it.
  Map<String, Object?> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'created_at': createdAt,
    };
  }
}
