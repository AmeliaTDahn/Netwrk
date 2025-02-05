import 'package:flutter/material.dart';
import '../screens/main_screen.dart';

class NetwrkApp extends StatelessWidget {
  const NetwrkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Netwrk',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.light(
          primary: const Color(0xFF2196F3),    // Light blue
          secondary: const Color(0xFF1565C0),   // Dark blue
          surface: Colors.white,
          background: const Color(0xFFFAFAFA),  // Very light grey
          onBackground: Colors.black87,
        ),
        // Keep all the existing theme configurations
        textTheme: const TextTheme(
          titleLarge: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.5,
          ),
          titleMedium: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w500,
            letterSpacing: -0.5,
          ),
          bodyLarge: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w400,
            letterSpacing: 0.1,
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
            letterSpacing: -0.5,
          ),
        ),
      ),
      home: const MainScreen(initialIndex: 0), // Use the existing MainScreen
      debugShowCheckedModeBanner: false,
    );
  }
} 