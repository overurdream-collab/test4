import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/config/app_config.dart';
import 'src/data/qat_link_api.dart';
import 'src/data/session_store.dart';
import 'src/state/app_state.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final baseUri = AppConfig.apiBaseUri;
  final sessionStore = baseUri == null ? null : SecureQatLinkSessionStore();
  final api = baseUri == null
      ? null
      : QatLinkApi(
          baseUri: baseUri,
          onSessionChanged: (session) async {
            await sessionStore?.write(session);
          },
        );
  final state = AppState(
    seed: !AppConfig.useDemoData,
    api: api,
    sessionStore: sessionStore,
  );
  runApp(QatLinkApp(state: state));
}
