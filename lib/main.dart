import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'services/db.dart';
import 'widgets/app_chrome.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppDb.instance.init();
  runApp(const GuardiasApp());
}

class GuardiasApp extends StatelessWidget {
  const GuardiasApp({super.key});

  @override
  Widget build(BuildContext context) {
    const navy = kBrandNavy;
    const gold = kBrandGold;

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Control de Guardias',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: navy,
          primary: navy,
          secondary: gold,
          surface: Colors.white,
        ),
        scaffoldBackgroundColor: kBrandBackground,
        appBarTheme: const AppBarTheme(
          backgroundColor: navy,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
          toolbarHeight: 72,
        ),
        cardTheme: CardThemeData(
          elevation: 1,
          margin: EdgeInsets.zero,
          color: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF4F7FA),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: navy,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(13),
            ),
          ),
        ),
        navigationBarTheme: const NavigationBarThemeData(
          backgroundColor: Colors.white,
          indicatorColor: Color(0xFFE7F0FB),
          elevation: 3,
          labelTextStyle: WidgetStatePropertyAll(
            TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
          ),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
