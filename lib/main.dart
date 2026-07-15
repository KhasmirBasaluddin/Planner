import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import 'core/constants.dart';
import 'core/drift/app_database.dart';
import 'core/theme.dart';
import 'features/planner/planner_page.dart';

void main() {
  runApp(const PlannerApp());
}

class PlannerApp extends StatefulWidget {
  const PlannerApp({super.key, this.database});

  final AppDatabase? database;

  @override
  State<PlannerApp> createState() => _PlannerAppState();
}

class _PlannerAppState extends State<PlannerApp> {
  late final AppDatabase _database;
  late final bool _ownsDatabase;

  @override
  void initState() {
    super.initState();
    _ownsDatabase = widget.database == null;
    _database = widget.database ?? AppDatabase();
  }

  @override
  void dispose() {
    if (_ownsDatabase) {
      _database.close();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: appName,
      theme: buildAppTheme(),
      localizationsDelegates: FlutterQuillLocalizations.localizationsDelegates,
      home: PlannerPage(database: _database),
    );
  }
}
