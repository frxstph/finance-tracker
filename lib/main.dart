import 'package:flutter/material.dart';

import 'data/backup.dart';
import 'data/db.dart';
import 'data/photos.dart';
import 'data/repository.dart';
import 'state/app_state.dart';
import 'ui/home_shell.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final db = await openAppDatabase();
    final photos = await PhotoStore.open();
    final repo = Repository(db);
    final state = AppState(
      repository: repo,
      photos: photos,
      backup: BackupService(repo, photos),
    );
    runApp(FinanceApp(state: state));
    await state.load();
  } catch (e) {
    runApp(StartupErrorApp(message: e.toString()));
  }
}

class FinanceApp extends StatelessWidget {
  const FinanceApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: state,
      child: MaterialApp(
        title: 'Finance Tracker',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: ThemeMode.system,
        home: const HomeShell(),
      ),
    );
  }
}

class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('The app could not start.\n\n$message'),
          ),
        ),
      ),
    );
  }
}
