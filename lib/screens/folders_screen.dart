import 'package:flutter/material.dart';

import '../catalogue_repository.dart';
import '../database_helper.dart';
import '../models/folder.dart';
import 'cards_screen.dart';
import 'diagnostics_screen.dart';
import 'roster_screen.dart';

// ============================================================================
// FOLDERS SCREEN (home): folder name + card count, create, open, delete
// ============================================================================
// Summary: The list always comes from repo.getFoldersWithCounts() after a
// write. Folders are opened and deleted by integer ID, never by name or list
// position. One _busy flag blocks duplicate actions while a write is pending.
class FoldersScreen extends StatefulWidget {
  final DatabaseHelper helper;
  final CatalogueRepository repo;

  const FoldersScreen({super.key, required this.helper, required this.repo});

  @override
  State<FoldersScreen> createState() => _FoldersScreenState();
}

class _FoldersScreenState extends State<FoldersScreen> {
  List<Folder> _folders = [];
  bool _loading = true;
  bool _busy = false;
  String? _readError;
  String? _feedback;

  CatalogueRepository get _repo => widget.repo;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
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
      final folders = await _repo.getFoldersWithCounts();
      if (!mounted) return false;
      setState(() {
        _folders = folders;
        _loading = false;
      });
      return true;
    } catch (error, stackTrace) {
      debugPrint('Folder read failed: $error\n$stackTrace');
      if (!mounted) return false;
      setState(() {
        _loading = false;
        _readError = 'Could not read folders ($error). Tap Refresh to retry.';
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
        setState(() => _feedback = 'Folders refreshed: ${_folders.length} '
            'folder(s), ${_folders.fold<int>(0, (s, f) => s + f.cardCount)} '
            'card(s).');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // A successful write followed by a failed read is reported as a refresh
  // problem; the write is never repeated.
  Future<void> _reloadAfterWrite(String successMessage) async {
    final ok = await _load();
    if (!mounted) return;
    setState(() => _feedback = ok
        ? successMessage
        : '$successMessage Saved, but refresh failed. Tap Refresh '
            '(do not save again).');
  }

  // --------------------------------------------------------------------------
  // CREATE (the dialog performs the insert so it can keep the typed name on
  // a failed write, e.g. a duplicate name)
  // --------------------------------------------------------------------------
  Future<void> _createFolder() async {
    if (_busy) return;
    final result = await showDialog<_NewFolderResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _NewFolderDialog(repo: _repo),
    );
    if (!mounted) return;
    if (result == null) {
      setState(() => _feedback = 'New folder cancelled; nothing was written.');
      return;
    }
    setState(() => _busy = true);
    try {
      await _reloadAfterWrite(
          'Created folder "${result.name}" with ID ${result.id}.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // --------------------------------------------------------------------------
  // DELETE: confirm with the folder's ID, name, and card count first.
  // --------------------------------------------------------------------------
  Future<void> _confirmDelete(Folder folder) async {
    if (_busy) return;
    final id = folder.id!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete folder?'),
        content: Text(
          'Delete folder ID $id, "${folder.name}"?\n\n'
          'Its ${folder.cardCount} card(s) will also be deleted '
          '(ON DELETE CASCADE). This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(dialogContext).colorScheme.error),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete folder'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (confirmed != true) {
      setState(() => _feedback =
          'Delete of folder ID $id cancelled; nothing was written.');
      return;
    }

    setState(() => _busy = true);
    try {
      final FolderDeleteResult result;
      try {
        result = await _repo.deleteFolder(id);
      } catch (error, stackTrace) {
        debugPrint('Folder delete failed: $error\n$stackTrace');
        if (mounted) setState(() => _feedback = 'Delete failed ($error).');
        return;
      }
      if (!mounted) return;
      if (result.foldersDeleted == 0) {
        final ok = await _load();
        if (!mounted) return;
        setState(() => _feedback =
            'Folder ID $id was not found; nothing deleted.'
            '${ok ? '' : ' Refresh also failed.'}');
        return;
      }
      await _reloadAfterWrite(
          'Deleted folder ID $id: ${result.foldersDeleted} folder row, '
          '${result.cardsCascaded} card(s) cascaded; '
          '${result.orphansRemaining} card(s) still reference ID $id.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openFolder(Folder folder) async {
    if (_busy) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CardsScreen(repo: _repo, folderId: folder.id!),
      ),
    );
    // Counts may have changed inside the folder; drop the old message so it
    // cannot show a stale total.
    if (!mounted) return;
    setState(() => _feedback = null);
    await _load();
  }

  // --------------------------------------------------------------------------
  // UI
  // --------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Card Catalogue'),
        actions: [
          IconButton(
            icon: const Icon(Icons.people),
            tooltip: 'Part I roster',
            onPressed: _busy
                ? null
                : () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => RosterScreen(helper: widget.helper)),
                    ),
          ),
          IconButton(
            icon: const Icon(Icons.storage),
            tooltip: 'Database diagnostics',
            onPressed: _busy
                ? null
                : () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                              DiagnosticsScreen(helper: widget.helper)),
                    ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _busy ? null : _refresh,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : _createFolder,
        icon: const Icon(Icons.create_new_folder),
        label: const Text('New folder'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_feedback != null)
                Text(_feedback!, key: const Key('folderFeedback')),
              const SizedBox(height: 4),
              Text(
                'Folders in database: ${_folders.length}',
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
    if (_folders.isEmpty) {
      return const Center(
        child: Text(
          'No folders yet. Tap "New folder" to start your catalogue.',
          textAlign: TextAlign.center,
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 88), // clear of the FAB
      itemCount: _folders.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final folder = _folders[index];
        final id = folder.id!;
        return ListTile(
          key: Key('folder_$id'),
          leading: const Icon(Icons.folder),
          title: Text(folder.name),
          subtitle: Text('ID $id · ${folder.cardCount} card(s)'),
          onTap: _busy ? null : () => _openFolder(folder),
          trailing: IconButton(
            icon: const Icon(Icons.delete),
            tooltip: 'Delete folder ID $id',
            onPressed: _busy ? null : () => _confirmDelete(folder),
          ),
        );
      },
    );
  }
}

// ============================================================================
// New-folder dialog: validates, inserts, and keeps input on failure
// ============================================================================
class _NewFolderResult {
  final int id;
  final String name;
  const _NewFolderResult(this.id, this.name);
}

class _NewFolderDialog extends StatefulWidget {
  final CatalogueRepository repo;
  const _NewFolderDialog({required this.repo});

  @override
  State<_NewFolderDialog> createState() => _NewFolderDialogState();
}

class _NewFolderDialogState extends State<_NewFolderDialog> {
  final _controller = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _controller.text.trim();
    if (name.isEmpty) {
      // NOT NULL does not reject whitespace, so the UI must.
      setState(() => _error =
          'Enter a folder name (spaces alone do not count). Not saved.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final id = await widget.repo.insertFolder(name);
      if (!mounted) return;
      Navigator.pop(context, _NewFolderResult(id, name));
    } on DuplicateFolderNameException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '$e Not saved; choose a different name.';
      });
    } catch (error, stackTrace) {
      debugPrint('Folder insert failed: $error\n$stackTrace');
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Save failed ($error). Your input was kept.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New folder'),
      content: TextField(
        key: const Key('folderNameField'),
        controller: _controller,
        enabled: !_saving,
        autofocus: true,
        decoration: InputDecoration(
          labelText: 'Folder name',
          border: const OutlineInputBorder(),
          errorText: _error,
          errorMaxLines: 3,
        ),
        onSubmitted: (_) => _save(),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving…' : 'Create'),
        ),
      ],
    );
  }
}
