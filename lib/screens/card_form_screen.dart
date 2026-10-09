import 'package:flutter/material.dart';

import '../catalogue_repository.dart';
import '../models/card_record.dart';
import '../models/folder.dart';
import '../widgets/card_image.dart';

// ============================================================================
// CARD FORM: one form reused for Add (card == null) and Edit (card != null)
// ============================================================================
// Summary: Validates a trimmed nonempty title, exactly one supported suit,
// and an existing folder ID before any write. Notes default to '' and a blank
// image reference is stored as SQL NULL. On success it pops with a result
// message; Cancel (or Back) pops with null and writes nothing. On a failed
// write the user's input stays in the form.
class CardFormScreen extends StatefulWidget {
  final CatalogueRepository repo;
  final int initialFolderId;
  final CardRecord? card;

  const CardFormScreen({
    super.key,
    required this.repo,
    required this.initialFolderId,
    this.card,
  });

  @override
  State<CardFormScreen> createState() => _CardFormScreenState();
}

class _CardFormScreenState extends State<CardFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _notesController;
  late final TextEditingController _imageController;
  String? _suit;
  int? _folderId;

  List<Folder> _folders = [];
  bool _loadingFolders = true;
  bool _busy = false;
  String? _error;

  bool get _editing => widget.card != null;

  @override
  void initState() {
    super.initState();
    final card = widget.card;
    _titleController = TextEditingController(text: card?.title ?? '');
    _notesController = TextEditingController(text: card?.notes ?? '');
    _imageController = TextEditingController(text: card?.imageRef ?? '');
    _suit = card?.suit;
    _folderId = card?.folderId ?? widget.initialFolderId;
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadFolders());
  }

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    _imageController.dispose();
    super.dispose();
  }

  // The folder picker lists real folder IDs from the database.
  Future<void> _loadFolders() async {
    try {
      final folders = await widget.repo.getFoldersWithCounts();
      if (!mounted) return;
      setState(() {
        _folders = folders;
        _loadingFolders = false;
        if (!folders.any((f) => f.id == _folderId)) _folderId = null;
      });
    } catch (error, stackTrace) {
      debugPrint('Folder list for form failed: $error\n$stackTrace');
      if (!mounted) return;
      setState(() {
        _loadingFolders = false;
        _error = 'Could not load folders ($error).';
      });
    }
  }

  // --------------------------------------------------------------------------
  // VALIDATION
  // --------------------------------------------------------------------------
  String? _validateTitle(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Enter a title (spaces alone do not count).';
    }
    return null;
  }

  String? _validateSuit(String? value) {
    if (value == null || !kSuits.contains(value)) {
      return 'Choose one suit: Hearts, Diamonds, Clubs, or Spades.';
    }
    return null;
  }

  String? _validateFolder(int? value) {
    if (value == null || !_folders.any((f) => f.id == value)) {
      return 'Choose an existing folder.';
    }
    return null;
  }

  // --------------------------------------------------------------------------
  // SAVE
  // --------------------------------------------------------------------------
  Future<void> _save() async {
    if (_busy) return;
    if (!_formKey.currentState!.validate()) {
      setState(() => _error = 'Not saved: fix the highlighted field(s).');
      return; // invalid input never reaches the database
    }
    final image = _imageController.text.trim();
    final card = CardRecord(
      id: widget.card?.id,
      title: _titleController.text.trim(),
      suit: _suit!,
      notes: _notesController.text.trim(),
      imageRef: image.isEmpty ? null : image,
      folderId: _folderId!,
    );

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final String message;
      if (!_editing) {
        final id = await widget.repo.insertCard(card);
        message = 'Added card "${card.title}" with ID $id to folder ID '
            '${card.folderId}.';
      } else {
        final updated = await widget.repo.updateCard(card);
        if (updated == 0) {
          // Zero rows is not success: the card was deleted elsewhere.
          message = 'Card ID ${card.id} no longer exists; nothing was updated.';
        } else {
          message = 'Updated card ID ${card.id}: $updated row affected.'
              '${card.folderId != widget.card!.folderId ? ' Moved to folder ID ${card.folderId}.' : ''}';
        }
      }
      if (!mounted) return;
      Navigator.pop(context, message);
    } catch (error, stackTrace) {
      debugPrint('Card write failed: $error\n$stackTrace');
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Save failed ($error). Your input was kept.';
      });
    }
  }

  // --------------------------------------------------------------------------
  // UI
  // --------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final card = widget.card;
    return PopScope(
      canPop: !_busy, // do not leave mid-write
      child: Scaffold(
        appBar: AppBar(
          title: Text(_editing ? 'Edit card ID ${card!.id}' : 'Add card'),
        ),
        body: SafeArea(
          child: _loadingFolders
              ? const Center(child: CircularProgressIndicator())
              : Form(
                  key: _formKey,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // Live preview of the image reference (or fallback).
                      Center(
                        child: ValueListenableBuilder<TextEditingValue>(
                          valueListenable: _imageController,
                          builder: (_, value, _) => CardImage(
                            imageRef: value.text,
                            suit: _suit ?? '',
                            size: 96,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        key: const Key('cardTitleField'),
                        controller: _titleController,
                        enabled: !_busy,
                        decoration: const InputDecoration(
                          labelText: 'Title *',
                          border: OutlineInputBorder(),
                        ),
                        validator: _validateTitle,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        key: const Key('cardSuitField'),
                        initialValue: _suit,
                        decoration: const InputDecoration(
                          labelText: 'Suit *',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          for (final s in kSuits)
                            DropdownMenuItem(
                                value: s, child: Text('${kSuitSymbols[s]} $s')),
                        ],
                        onChanged: _busy
                            ? null
                            : (value) => setState(() => _suit = value),
                        validator: _validateSuit,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int>(
                        key: const Key('cardFolderField'),
                        initialValue: _folderId,
                        decoration: const InputDecoration(
                          labelText: 'Folder *',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          for (final f in _folders)
                            DropdownMenuItem(
                                value: f.id,
                                child: Text('${f.name} (ID ${f.id})')),
                        ],
                        onChanged: _busy
                            ? null
                            : (value) => setState(() => _folderId = value),
                        validator: _validateFolder,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        key: const Key('cardNotesField'),
                        controller: _notesController,
                        enabled: !_busy,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Notes (optional)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        key: const Key('cardImageField'),
                        controller: _imageController,
                        enabled: !_busy,
                        decoration: const InputDecoration(
                          labelText: 'Image reference (optional)',
                          helperText: 'e.g. assets/cards/card_back.png or an '
                              'https:// URL. Blank = suit placeholder.',
                          helperMaxLines: 2,
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_error != null)
                        Text(
                          _error!,
                          key: const Key('cardFormError'),
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error),
                        ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              key: const Key('cardCancelButton'),
                              onPressed:
                                  _busy ? null : () => Navigator.pop(context),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton.icon(
                              key: const Key('cardSaveButton'),
                              onPressed: _busy ? null : _save,
                              icon: Icon(_editing ? Icons.save : Icons.add),
                              label: Text(_busy
                                  ? 'Saving…'
                                  : (_editing ? 'Save' : 'Add')),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
