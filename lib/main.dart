import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wpe_summit_attendance_2026/UI/homescreen.dart';
import 'package:wpe_summit_attendance_2026/location_access.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Strategic Business Development Conclave FY - 2027',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color.fromARGB(255, 34, 101, 75),
        scaffoldBackgroundColor: const Color(0xFFF4FBF6),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          foregroundColor: Color.fromARGB(255, 37, 103, 77),
          elevation: 0,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: const Color.fromARGB(255, 41, 99, 77),
            foregroundColor: Colors.white,
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color.fromARGB(255, 34, 87, 67),
            side: const BorderSide(color: Color(0xFFB9E6C7)),
          ),
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: Color(0xFF173B2D),
        ),
      ),
      routes: {'/home': (context) => const Homepage()},
      home: const SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    unawaited(_prepareApp());
  }

  Future<void> _prepareApp() async {
    await Future.wait<void>([
      Future<void>.delayed(const Duration(milliseconds: 1500)),
      LocationAccess.requestInitialPermission(),
    ]);

    if (!mounted) {
      return;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const Homepage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4FBF6),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset('asset/zigma_blueplanet_logo.png', height: 76),
                  const SizedBox(width: 14),
                  Image.asset('asset/unicel.png', height: 54),
                ],
              ),
              const SizedBox(height: 24),
              const Text(
                'Strategic Business Development Conclave FY - 2027',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF163A2B),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: Color(0xFF4F6B5D),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
