import 'package:flutter/material.dart';

import 'data/app_prefs.dart';
import 'data/backup.dart';
import 'data/db.dart';
import 'data/lock_store.dart';
import 'data/photos.dart';
import 'data/repository.dart';
import 'state/app_state.dart';
import 'state/device_sync.dart';
import 'state/lock_controller.dart';
import 'ui/home_shell.dart';
import 'ui/lock_screen.dart';
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
    // Load the lock first so nothing shows before the PIN screen.
    final lock = LockController(await LockStore.open());
    await lock.load();
    final prefs = await AppPrefs.open();
    runApp(FinanceApp(state: state, lock: lock, prefs: prefs));
    // Widget and reminders follow the data from here on.
    DeviceSync(state: state, lock: lock, prefs: prefs);
    await state.load();
  } catch (e) {
    runApp(StartupErrorApp(message: e.toString()));
  }
}

class FinanceApp extends StatelessWidget {
  const FinanceApp({
    super.key,
    required this.state,
    required this.lock,
    required this.prefs,
  });

  final AppState state;
  final LockController lock;
  final AppPrefs prefs;

  @override
  Widget build(BuildContext context) {
    return PrefsScope(
      prefs: prefs,
      child: LockScope(
      controller: lock,
      child: AppScope(
        state: state,
        child: MaterialApp(
          title: 'Finance Tracker',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Brightness.light),
          darkTheme: buildTheme(Brightness.dark),
          themeMode: ThemeMode.system,
          home: const HomeShell(),
          // The lock screen sits on top of every page while locked.
          builder: (context, child) => ListenableBuilder(
            listenable: lock,
            builder: (context, _) {
              final locked = lock.locked;
              return Stack(
                children: <Widget>[
                  ExcludeSemantics(
                    excluding: locked,
                    child: child ?? const SizedBox.shrink(),
                  ),
                  if (locked)
                    Positioned.fill(
                      // Its own navigator so the lock screen can show
                      // dialogs and tooltips. HeroControllerScope.none keeps
                      // it from taking the app's hero controller: a hero
                      // controller can serve only one navigator, and when
                      // the lock screen closed it left the main navigator
                      // without one, so pages (Settings…) stopped opening.
                      child: HeroControllerScope.none(
                        child: Navigator(
                          onGenerateRoute: (_) => MaterialPageRoute<void>(
                            builder: (_) => const LockScreen(),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
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
