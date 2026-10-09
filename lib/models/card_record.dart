// ============================================================================
// CardRecord model (child row in `cards`)
// ============================================================================
// Summary: Named CardRecord so it does not collide with Material's Card widget.
// `folderId` is the foreign key to folders.id; `imageRef` is nullable and is
// only a reference (asset path or URL), never the image bytes.

// The only suit values the form accepts and the database stores.
const List<String> kSuits = ['Hearts', 'Diamonds', 'Clubs', 'Spades'];

const Map<String, String> kSuitSymbols = {
  'Hearts': '♥',
  'Diamonds': '♦',
  'Clubs': '♣',
  'Spades': '♠',
};

class CardRecord {
  final int? id; // null until SQLite assigns one on insert
  final String title;
  final String suit;
  final String notes; // '' when omitted, never null
  final String? imageRef; // SQL NULL when omitted
  final int folderId;

  const CardRecord({
    this.id,
    required this.title,
    required this.suit,
    this.notes = '',
    this.imageRef,
    required this.folderId,
  });

  String get suitSymbol => kSuitSymbols[suit] ?? '?';

  factory CardRecord.fromMap(Map<String, Object?> map) {
    return CardRecord(
      id: map['id'] as int,
      title: map['title'] as String,
      suit: map['suit'] as String,
      notes: (map['notes'] as String?) ?? '',
      imageRef: map['image_ref'] as String?,
      folderId: map['folder_id'] as int,
    );
  }

  // Omits `id` when it is null so SQLite generates it. image_ref is always
  // written, so clearing it in the form stores NULL rather than keeping the
  // old value.
  Map<String, Object?> toMap() {
    return {
      if (id != null) 'id': id,
      'title': title,
      'suit': suit,
      'notes': notes,
      'image_ref': imageRef,
      'folder_id': folderId,
    };
  }
}
