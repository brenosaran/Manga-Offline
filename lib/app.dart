import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'core/app_theme.dart';
import 'core/settings_controller.dart';
import 'screens/library_screen.dart';
import 'screens/settings_screen.dart';
import 'services/library_controller.dart';

class MangaOfflineApp extends StatelessWidget {
  const MangaOfflineApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsController>.value(
          value: SettingsController.instance,
        ),
        ChangeNotifierProvider<LibraryController>(
          create: (_) => LibraryController()..load(),
        ),
      ],
      child: Consumer<SettingsController>(
        builder: (context, settings, _) {
          final l10n = settings.l10n;
          return MaterialApp(
            title: l10n.appTitle,
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            locale: Locale(settings.locale),
            supportedLocales: const [Locale('pt'), Locale('en')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: const HomeShell(),
          );
        },
      ),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _screens = <Widget>[
    LibraryScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<SettingsController>().l10n;
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (value) => setState(() => _index = value),
        items: [
          BottomNavigationBarItem(
            icon: const Icon(Icons.menu_book_outlined),
            activeIcon: const Icon(Icons.menu_book),
            label: l10n.library,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.settings_outlined),
            activeIcon: const Icon(Icons.settings),
            label: l10n.settings,
          ),
        ],
      ),
    );
  }
}
