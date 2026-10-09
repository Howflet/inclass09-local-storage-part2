import 'package:flutter/material.dart';

import '../database_helper.dart';

// ============================================================================
// PART I ROSTER SCREEN (unchanged from In-Class 08; moved out of main.dart)
// ============================================================================
// Summary: Holds only screen state (rows read back from SQLite, the count,
// loading/busy flags, messages, and the selected row's ID). Every list update
// comes from re-querying the database after a write, never from editing a
// cached list in memory.
// Reference: https://pub.dev/packages/sqflite
class RosterScreen extends StatefulWidget {
  final DatabaseHelper helper;

  const RosterScreen({super.key, required this.helper});

  @override
  State<RosterScreen> createState() => _RosterScreenState();
}

class _RosterScreenState extends State<RosterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _ageController = TextEditingController();

  // --- Data read back from the database ---
  List<Map<String, dynamic>> _rows = [];
  int _count = 0;

  // --- Status flags / messages ---
  bool _loading = true; // true while a read is in progress
  bool _busy = false; // one flag guards every database action
  String? _readError; // last read failure (Refresh doubles as Retry)
  String? _feedback; // text result of the last action

  // ID of the row being edited; null means the form is in Add mode.
  int? _selectedId;

  DatabaseHelper get _helper => widget.helper;

  @override
  void initState() {
    super.initState();
    // First load is started here, not in build(). It runs right after the
    // first frame because setState() is not allowed during initState itself.
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    super.dispose();
  }

  // --------------------------------------------------------------------------
  // READ: query rows + count. Returns true when the read succeeded.
  // --------------------------------------------------------------------------
  Future<bool> _load() async {
    setState(() {
      _loading = true;
      _readError = null;
    });
    try {
      final rows = await _helper.queryAllRows();
      final count = await _helper.queryRowCount();
      if (!mounted) return false;
      setState(() {
        _rows = rows;
        _count = count;
        _loading = false;
      });
      return true;
    } catch (error, stackTrace) {
      debugPrint('Read failed: $error\n$stackTrace');
      if (!mounted) return false;
      setState(() {
        _loading = false;
        _readError = 'Could not read the roster ($error). Tap Refresh to retry.';
      });
      return false;
    }
  }

  // Refresh button / first load: a read only, never repeats a write.
  Future<void> _refresh() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final ok = await _load();
      if (ok && mounted) {
        setState(() => _feedback = 'Roster refreshed: $_count guest(s).');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // After a successful write, re-read. A failed re-read is reported as a
  // refresh problem, not as a failed save.
  Future<void> _reloadAfterWrite(String successMessage) async {
    final ok = await _load();
    if (!mounted) return;
    setState(() {
      _feedback = ok
          ? successMessage
          : '$successMessage Saved, but refresh failed. Tap Refresh.';
    });
  }

  // --------------------------------------------------------------------------
  // VALIDATION: trimmed nonempty name; integer age 0-130 inclusive.
  // --------------------------------------------------------------------------
  String? _validateName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Enter a name (spaces alone do not count).';
    }
    return null;
  }

  String? _validateAge(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Enter an age.';
    final age = int.tryParse(text);
    if (age == null) return 'Age must be a whole number (no letters or decimals).';
    if (age < 0 || age > 130) return 'Age must be between 0 and 130.';
    return null;
  }

  void _clearForm() {
    _formKey.currentState?.reset();
    _nameController.clear();
    _ageController.clear();
    _selectedId = null;
  }

  // --------------------------------------------------------------------------
  // CREATE / UPDATE: one form, two modes chosen by _selectedId.
  // --------------------------------------------------------------------------
  Future<void> _submit() async {
    if (_busy) return;
    if (!_formKey.currentState!.validate()) {
      setState(() => _feedback = 'Not saved: fix the highlighted field(s).');
      return; // invalid input never reaches the database
    }
    final name = _nameController.text.trim();
    final age = int.parse(_ageController.text.trim()); // validated above
    final editingId = _selectedId;

    setState(() => _busy = true);
    try {
      String message;
      try {
        if (editingId == null) {
          // Omit _id so SQLite generates it.
          final id = await _helper.insert({
            DatabaseHelper.columnName: name,
            DatabaseHelper.columnAge: age,
          });
          message = 'Added "$name" (age $age) with ID $id.';
        } else {
          final updated = await _helper.update({
            DatabaseHelper.columnId: editingId,
            DatabaseHelper.columnName: name,
            DatabaseHelper.columnAge: age,
          });
          if (updated == 0) {
            // Row vanished: no success message; clear selection and reload.
            if (!mounted) return;
            setState(() => _clearForm());
            final ok = await _load();
            if (!mounted) return;
            setState(() => _feedback =
                'Guest ID $editingId no longer exists; nothing was updated.'
                '${ok ? '' : ' Refresh also failed.'}');
            return;
          }
          message = 'Updated ID $editingId: $updated row affected.';
        }
      } catch (error, stackTrace) {
        // Write failed: keep the user's input so they can retry.
        debugPrint('Write failed: $error\n$stackTrace');
        if (mounted) {
          setState(() => _feedback = 'Save failed ($error). Your input was kept.');
        }
        return;
      }
      // Write succeeded: clear the form, then refresh from the database.
      if (!mounted) return;
      setState(() => _clearForm());
      await _reloadAfterWrite(message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _startEdit(Map<String, dynamic> row) {
    setState(() {
      _selectedId = row[DatabaseHelper.columnId] as int;
      _nameController.text = row[DatabaseHelper.columnName] as String;
      _ageController.text = '${row[DatabaseHelper.columnAge]}';
      _feedback = 'Editing ID $_selectedId. Save or Cancel edit.';
    });
  }

  void _cancelEdit() {
    final id = _selectedId;
    setState(() {
      _clearForm();
      _feedback = 'Edit of ID $id cancelled; nothing was written.';
    });
  }

  // --------------------------------------------------------------------------
  // DELETE: confirm with the row's ID/name, then delete by ID.
  // --------------------------------------------------------------------------
  Future<void> _confirmDelete(Map<String, dynamic> row) async {
    if (_busy) return;
    final id = row[DatabaseHelper.columnId] as int;
    final name = row[DatabaseHelper.columnName] as String;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete guest?'),
        content: Text('Delete ID $id, "$name"? This cannot be undone.'),
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
      setState(() => _feedback = 'Delete of ID $id cancelled; nothing was written.');
      return;
    }

    setState(() => _busy = true);
    try {
      int deleted;
      try {
        deleted = await _helper.delete(id);
      } catch (error, stackTrace) {
        debugPrint('Delete failed: $error\n$stackTrace');
        if (mounted) setState(() => _feedback = 'Delete failed ($error).');
        return;
      }
      if (!mounted) return;
      // If the deleted row was being edited, drop that selection.
      if (_selectedId == id) setState(() => _clearForm());
      if (deleted == 0) {
        final ok = await _load();
        if (!mounted) return;
        setState(() => _feedback = 'Guest ID $id was not found; nothing deleted.'
            '${ok ? '' : ' Refresh also failed.'}');
        return;
      }
      await _reloadAfterWrite('Deleted ID $id: $deleted row affected.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // --------------------------------------------------------------------------
  // UI
  // --------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final editing = _selectedId != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fall Festival Roster'),
        actions: [
          IconButton(
            key: const Key('refreshButton'),
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _busy ? null : _refresh,
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // --- Add/Edit form (one form reused for both modes) ---
              Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      editing ? 'Editing guest ID $_selectedId' : 'Add a guest',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      key: const Key('nameField'),
                      controller: _nameController,
                      enabled: !_busy,
                      decoration: const InputDecoration(
                        labelText: 'Name',
                        border: OutlineInputBorder(),
                      ),
                      validator: _validateName,
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      key: const Key('ageField'),
                      controller: _ageController,
                      enabled: !_busy,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Age (0-130)',
                        border: OutlineInputBorder(),
                      ),
                      validator: _validateAge,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            key: const Key('submitButton'),
                            onPressed: _busy ? null : _submit,
                            icon: Icon(editing ? Icons.save : Icons.person_add),
                            label: Text(editing ? 'Save' : 'Add'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            key: const Key('cancelEditButton'),
                            onPressed: (_busy || !editing) ? null : _cancelEdit,
                            child: const Text('Cancel edit'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _busy ? null : _refresh,
                            child: const Text('Refresh'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // --- Feedback + count ---
              if (_feedback != null)
                Text(_feedback!, key: const Key('feedbackText')),
              const SizedBox(height: 4),
              Text(
                'Guests in database: $_count',
                key: const Key('countText'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Divider(),

              // --- List / loading / error / empty ---
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
    if (_rows.isEmpty) {
      // Shown only after a successful empty query.
      return const Center(
        child: Text(
          'No festival guests yet. The pumpkins are waiting!',
          textAlign: TextAlign.center,
        ),
      );
    }
    return ListView.separated(
      itemCount: _rows.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final row = _rows[index];
        final id = row[DatabaseHelper.columnId] as int;
        return ListTile(
          key: Key('row_$id'),
          selected: id == _selectedId,
          leading: CircleAvatar(child: Text('$id')),
          title: Text('${row[DatabaseHelper.columnName]}'),
          subtitle: Text('ID $id · Age ${row[DatabaseHelper.columnAge]}'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.edit),
                tooltip: 'Edit ID $id',
                onPressed: _busy ? null : () => _startEdit(row),
              ),
              IconButton(
                icon: const Icon(Icons.delete),
                tooltip: 'Delete ID $id',
                onPressed: _busy ? null : () => _confirmDelete(row),
              ),
            ],
          ),
        );
      },
    );
  }
}
