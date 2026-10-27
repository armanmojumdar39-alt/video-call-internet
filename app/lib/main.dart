import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_state.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState()..init(),
      child: const ConnectoApp(),
    ),
  );
}

class ConnectoApp extends StatelessWidget {
  const ConnectoApp({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return MaterialApp(
      title: 'Connecto',
      debugShowCheckedModeBanner: false,
      navigatorKey: state.navKey,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: !state.ready
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : state.loggedIn
              ? const HomeScreen()
              : const LoginScreen(),
    );
  }
}
