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
    final elevatedButtonStyle = ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF5865F2),
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      ),
    );

    switch (mode) {
      case 'light':
        return ThemeData.light().copyWith(
          scaffoldBackgroundColor: const Color(0xFFFFFFFF),
          primaryColor: const Color(0xFF5865F2),
          colorScheme: const ColorScheme.light(
            primary: Color(0xFF5865F2),
            secondary: Color(0xFF43B581),
            surface: Color(0xFFF2F3F5),
            surfaceVariant: Color(0xFFE3E5E8),
          ),
          appBarTheme: const AppBarTheme(backgroundColor: Color(0xFFF2F3F5), foregroundColor: Colors.black, elevation: 0),
          elevatedButtonTheme: elevatedButtonStyle,
          dividerColor: const Color(0xFFE3E5E8),
        );
      case 'midnight':
        return ThemeData.dark().copyWith(
          scaffoldBackgroundColor: const Color(0xFF0B1416),
          primaryColor: const Color(0xFF3B82F6),
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF3B82F6),
            secondary: Color(0xFF10B981),
            surface: Color(0xFF152329),
            surfaceVariant: Color(0xFF0A1014),
          ),
          appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF152329), elevation: 0),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3B82F6),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
          dividerColor: const Color(0xFF1F2937),
        );
      case 'ocean':
        return ThemeData.dark().copyWith(
          scaffoldBackgroundColor: const Color(0xFF0F172A),
          primaryColor: const Color(0xFF0EA5E9),
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF0EA5E9),
            secondary: Color(0xFF2DD4BF),
            surface: Color(0xFF1E293B),
            surfaceVariant: Color(0xFF020617),
          ),
          appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF1E293B), elevation: 0),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0EA5E9),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
          dividerColor: const Color(0xFF334155),
        );
      case 'dark':
      default:
        return ThemeData.dark().copyWith(
          scaffoldBackgroundColor: const Color(0xFF313338),
          primaryColor: const Color(0xFF5865F2),
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF5865F2),
            secondary: Color(0xFF43B581),
            surface: Color(0xFF2B2D31),
            surfaceVariant: Color(0xFF1E1F22),
          ),
          appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF2B2D31), elevation: 0),
          elevatedButtonTheme: elevatedButtonStyle,
          dividerColor: const Color(0xFF3F4147),
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

