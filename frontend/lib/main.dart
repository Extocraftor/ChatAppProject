import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/app_state.dart';
import 'screens/login_screen.dart';
import 'screens/main_layout.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (context) => AppState(),
      child: const HarmonyApp(),
    ),
  );
}

class HarmonyApp extends StatelessWidget {
  const HarmonyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Harmony',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF36393F),
        primaryColor: const Color(0xFF5865F2),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF5865F2),
          secondary: Color(0xFF43B581),
        ),
      ),
      home: Consumer<AppState>(
        builder: (context, state, child) {
          return state.currentUser == null
              ? const LoginScreen()
              : const MainLayout();
        },
      ),
    );
  }
}

