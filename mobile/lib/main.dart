import 'package:flutter/material.dart';

import 'core/api_client.dart';
import 'core/app_state.dart';
import 'core/bma_repository.dart';
import 'core/session_store.dart';
import 'screens/home_shell.dart';
import 'screens/login_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final api = ApiClient(sessionStore: SessionStore());
  final state = AppState(api);
  await state.bootstrap();
  runApp(BmaApp(state: state, repository: BmaRepository(api)));
}

class BmaApp extends StatelessWidget {
  const BmaApp({required this.state, required this.repository, super.key});

  final AppState state;
  final BmaRepository repository;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: state,
    builder: (context, _) => MaterialApp(
      title: 'Bình Minh App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff941820)),
        scaffoldBackgroundColor: const Color(0xfff7f4f1),
        useMaterial3: true,
        cardTheme: const CardThemeData(elevation: 0, margin: EdgeInsets.symmetric(vertical: 6)),
        inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
      ),
      home: state.loading
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : state.authenticated
              ? HomeShell(state: state, repository: repository)
              : LoginScreen(state: state),
    ),
  );
}
