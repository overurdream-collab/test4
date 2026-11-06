import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'design/components.dart';
import 'design/theme.dart';
import 'state/app_state.dart';
import 'screens/auth/login_screen.dart';
import 'screens/shared/home_shell.dart';

class QatLinkApp extends StatefulWidget {
  const QatLinkApp({super.key, this.state});

  final AppState? state;

  @override
  State<QatLinkApp> createState() => _QatLinkAppState();
}

class _QatLinkAppState extends State<QatLinkApp> {
  late final AppState _state = widget.state ?? AppState();

  @override
  void initState() {
    super.initState();
    if (_state.isRemote) unawaited(_state.bootstrap());
  }

  @override
  void dispose() {
    if (widget.state == null) _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _state,
      builder: (context, _) {
        return QScope(
          state: _state,
          child: MaterialApp(
            title: 'QAT LINK • قات لينك',
            debugShowCheckedModeBanner: false,
            theme: QTheme.light(),
            darkTheme: QTheme.dark(),
            themeMode: _state.themeMode,
            locale: const Locale('ar'),
            supportedLocales: const [Locale('ar'), Locale('en')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            builder: (context, child) {
              return Directionality(
                textDirection: TextDirection.rtl,
                child: child ?? const SizedBox.shrink(),
              );
            },
            home: _state.loggedIn ? const HomeShell() : const LoginScreen(),
          ),
        );
      },
    );
  }
}
