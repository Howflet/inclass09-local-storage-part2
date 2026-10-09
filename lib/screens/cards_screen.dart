import 'package:flutter/material.dart';

import '../catalogue_repository.dart';
import '../models/card_record.dart';
import '../models/folder.dart';
import '../widgets/card_image.dart';
import 'card_form_screen.dart';

// ============================================================================
// CARDS SCREEN: the cards of ONE folder, queried by that folder's integer ID
// ============================================================================
// Summary: Receives only a folder ID. The folder header and the card list are
// both re-read from SQLite (repo.getFolder / repo.getCards(folderId)) after
// every write. Tapping a card opens the shared Add/Edit form in Edit mode.
class CardsScreen extends StatefulWidget {
  final CatalogueRepository repo;
  final int folderId;

  const CardsScreen({super.key, required this.repo, required this.folderId});

  @override
  State<CardsScreen> createState() => _CardsScreenState();
}

class _CardsScreenState extends State<CardsScreen> {
  Folder? _folder;
  List<CardRecord> _cards = [];
  bool _loading = true;
  bool _busy = false;
  String? _readError;
  String? _feedback;

  CatalogueRepository get _repo => widget.repo;
  int get _folderId => widget.folderId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  // --------------------------------------------------------------------------
  // READ
  // --------------------------------------------------------------------------
  Future<bool> _load() async {
    setState(() {
      _loading = true;
      _readError = null;
    });
    try {
      final folder = await _repo.getFolder(_folderId);
      final cards = await _repo.getCards(_folderId);
      debugPrint('getCards(folder_id = $_folderId) -> ${cards.length} row(s)');
      if (!mounted) return false;
      setState(() {
        _folder = folder;
        _cards = cards;
        _loading = false;
        if (folder == null) {
          _readError = 'Folder ID $_folderId no longer exists.';
        }
      });
      return folder != null;
    } catch (error, stackTrace) {
      debugPrint('Card read failed: $error\n$stackTrace');
      if (!mounted) return false;
      setState(() {
        _loading = false;
        _readError = 'Could not read cards ($error). Tap Refresh to retry.';
      });
      return false;
    }
  }

  Future<void> _refresh() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final ok = await _load();
      if (ok && mounted) {
        setState(() => _feedback = 'Refreshed: ${_cards.length} card(s) in '
            'folder ID $_folderId.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // --------------------------------------------------------------------------
  // ADD / EDIT: the form does the write and returns its result message, or
  // null when cancelled. This screen only re-reads afterward.
  // --------------------------------------------------------------------------
  Future<void> _openForm({CardRecord? card}) async {
    if (_busy) return;
    final message = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => CardFormScreen(
          repo: _repo,
          initialFolderId: _folderId,
          card: card,
        ),
      ),
    );
    if (!mounted) return;
    if (message == null) {
      setState(() => _feedback = card == null
          ? 'Add card cancelled; nothing was written.'
          : 'Edit of card ID ${card.id} cancelled; nothing was written.');
      final ok = await _load();
      if (!ok && mounted) {
        setState(() => _feedback = '$_feedback Refresh failed.');
      }
      return;
    }
    setState(() => _busy = true);
    try {
      final ok = await _load();
      if (!mounted) return;
      setState(() => _feedback = ok
          ? message
          : '$message Saved, but refresh failed. Tap Refresh '
              '(do not save again).');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // --------------------------------------------------------------------------
  // DELETE: confirm with ID + title, then delete by ID.
  // --------------------------------------------------------------------------
  Future<void> _confirmDelete(CardRecord card) async {
    if (_busy) return;
    final id = card.id!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete card?'),
        content: Text('Delete card ID $id, "${card.title}" '
            '(${card.suit})? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (confirmed != true) {
      setState(() =>
          _feedback = 'Delete of card ID $id cancelled; nothing was written.');
      return;
    }

    setState(() => _busy = true);
    try {
      int deleted;
      try {
        deleted = await _repo.deleteCard(id);
      } catch (error, stackTrace) {
        debugPrint('Card delete failed: $error\n$stackTrace');
        if (mounted) setState(() => _feedback = 'Delete failed ($error).');
        return;
      }
      final ok = await _load();
      if (!mounted) return;
      setState(() => _feedback = (deleted == 0
              ? 'Card ID $id was not found; nothing deleted.'
              : 'Deleted card ID $id: $deleted row affected.') +
          (ok ? '' : ' Refresh failed; tap Refresh.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // --------------------------------------------------------------------------
  // UI
  // --------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final folder = _folder;
    return Scaffold(
      appBar: AppBar(
        title: Text(folder == null ? 'Folder ID $_folderId' : folder.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _busy ? null : _refresh,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: (_busy || folder == null) ? null : () => _openForm(),
        icon: const Icon(Icons.add_card),
        label: const Text('Add card'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_feedback != null)
                Text(_feedback!, key: const Key('cardFeedback')),
              const SizedBox(height: 4),
              Text(
                'Folder ID $_folderId · cards: ${_cards.length}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Divider(),
              Expanded(child: _buildList()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildList() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_readError != null) {
      return Center(
        child: Text(_readError!,
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.error)),
      );
    }
    if (_cards.isEmpty) {
      // Shown only after a successful query that returned zero rows.
      return Center(
        child: Text(
          'No cards in this folder yet (folder ID $_folderId).\n'
          'Tap "Add card" to create one.',
          textAlign: TextAlign.center,
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 88),
      itemCount: _cards.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final card = _cards[index];
        final id = card.id!;
        return ListTile(
          key: Key('card_$id'),
          leading: CardImage(imageRef: card.imageRef, suit: card.suit, size: 36),
          title: Text(card.title),
          subtitle: Text(
            'ID $id · ${card.suitSymbol} ${card.suit}'
            '${card.notes.isEmpty ? '' : ' · ${card.notes}'}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: _busy ? null : () => _openForm(card: card),
          trailing: IconButton(
            icon: const Icon(Icons.delete),
            tooltip: 'Delete card ID $id',
            onPressed: _busy ? null : () => _confirmDelete(card),
          ),
        );
      },
    );
  }
}
