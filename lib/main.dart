import 'package:flutter/material.dart';

import 'catalogue_repository.dart';
import 'database_helper.dart';
import 'screens/folders_screen.dart';

// ============================================================================
// 1. MAIN ENTRY POINT (Open/upgrade the database before any UI queries it)
// ============================================================================
// Summary: main() awaits DatabaseHelper.init(), which opens MyDatabase.db at
// version 2 (running onUpgrade for a Part I version-1 file, or onCreate for a
// fresh install). If opening or upgrading fails, an explicit error screen is
// shown instead of an app that pretends to be empty.
// Reference: https://docs.flutter.dev/cookbook/persistence/sqlite
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final helper = DatabaseHelper();
  try {
    await helper.init();
  } catch (error, stackTrace) {
    debugPrint('Database initialization failed: $error\n$stackTrace');
    runApp(MaterialApp(
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Could not open or upgrade local storage ($error). '
              'Your data was not deleted. Restart the app and check the logs.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    ));
    return;
  }
  runApp(CatalogueApp(helper: helper, repo: CatalogueRepository(helper)));
}

// ============================================================================
// 2. ROOT APPLICATION WIDGET
// ============================================================================
// Summary: One DatabaseHelper (also used by the Part I roster) and one
// CatalogueRepository (used by the folder/card screens) for the whole app.
class CatalogueApp extends StatelessWidget {
  final DatabaseHelper helper;
  final CatalogueRepository repo;

  const CatalogueApp({super.key, required this.helper, required this.repo});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Card Catalogue',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.deepOrange, // same autumn accent as Part I
      ),
      home: FoldersScreen(helper: helper, repo: repo),
    );
  }
}
