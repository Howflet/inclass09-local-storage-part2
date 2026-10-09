import 'dart:convert';

import 'package:flutter/material.dart';

import '../database_helper.dart';

// ============================================================================
// DIAGNOSTICS SCREEN: read-only schema evidence for T1
// ============================================================================
// Summary: Shows PRAGMA user_version, PRAGMA foreign_keys on the app's open
// connection, the cards foreign key / index lists, and the Part I rows. It
// only reads; it never changes data or PRAGMA settings. The same text is also
// written to the debug log so it can be saved as evidence.
class DiagnosticsScreen extends StatefulWidget {
  final DatabaseHelper helper;

  const DiagnosticsScreen({super.key, required this.helper});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  String? _text;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final info = await widget.helper.diagnostics();
      final text = const JsonEncoder.withIndent('  ').convert(info);
      debugPrint('DB DIAGNOSTICS\n$text');
      if (!mounted) return;
      setState(() => _text = text);
    } catch (error, stackTrace) {
      debugPrint('Diagnostics failed: $error\n$stackTrace');
      if (!mounted) return;
      setState(() => _error = 'Diagnostics failed ($error).');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Database diagnostics')),
      body: SafeArea(
        child: _error != null
            ? Center(child: Text(_error!))
            : _text == null
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: SelectableText(
                      _text!,
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 12),
                    ),
                  ),
      ),
    );
  }
}
