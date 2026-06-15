import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';
import 'providers/app_state.dart';
import 'screens/login_screen.dart';
import 'screens/main_layout.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  runApp(
    ChangeNotifierProvider(
      create: (context) => AppState()..tryAutoLogin(),
      child: const HarmonyApp(),
    ),
  );
}

class HarmonyApp extends StatelessWidget {
  const HarmonyApp({super.key});

  ThemeData _getThemeData(String mode) {
    switch (mode) {
      case 'light':
        return ThemeData.light().copyWith(
          scaffoldBackgroundColor: const Color(0xFFF2F3F5),
          primaryColor: const Color(0xFF5865F2),
          colorScheme: const ColorScheme.light(
            primary: Color(0xFF5865F2),
            secondary: Color(0xFF43B581),
            surface: Color(0xFFFFFFFF),
          ),
          appBarTheme: const AppBarTheme(backgroundColor: Color(0xFFE3E5E8), foregroundColor: Colors.black),
        );
      case 'midnight':
        return ThemeData.dark().copyWith(
          scaffoldBackgroundColor: const Color(0xFF0F172A),
          primaryColor: const Color(0xFF3B82F6),
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF3B82F6),
            secondary: Color(0xFF10B981),
            surface: Color(0xFF1E293B),
          ),
          appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF0F172A)),
        );
      case 'ocean':
        return ThemeData.dark().copyWith(
          scaffoldBackgroundColor: const Color(0xFF001F3F),
          primaryColor: const Color(0xFF0074D9),
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF0074D9),
            secondary: Color(0xFF39CCCC),
            surface: Color(0xFF001f3f),
          ),
          appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF001a35)),
        );
      case 'dark':
      default:
        return ThemeData.dark().copyWith(
          scaffoldBackgroundColor: const Color(0xFF36393F),
          primaryColor: const Color(0xFF5865F2),
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF5865F2),
            secondary: Color(0xFF43B581),
            surface: Color(0xFF2F3136),
          ),
          appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF2F3136)),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, child) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Harmony',
          theme: _getThemeData(state.themeMode),
          home: state.currentUser == null
              ? const LoginScreen()
              : const MainLayout(),
        );
      },
    );
  }
}

