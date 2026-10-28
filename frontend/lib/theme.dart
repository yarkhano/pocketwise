import 'package:flutter/material.dart';

const Color brandColor = Color(0xFF2256D8);
const Color incomeColor = Color(0xFF087F5B);
const Color expenseColor = Color(0xFFBE3445);
const Color warningColor = Color(0xFF9A6500);
const Color pageBackground = Color(0xFFF5F7FB);

const List<int> categoryColors = [
  0xFF2563EB,
  0xFF087F5B,
  0xFF9333EA,
  0xFFE76F00,
  0xFFBE3445,
  0xFF0891B2,
];

const Map<String, IconData> categoryIcons = {
  'food': Icons.restaurant_rounded,
  'transport': Icons.directions_bus_rounded,
  'shopping': Icons.shopping_bag_rounded,
  'bills': Icons.receipt_long_rounded,
  'education': Icons.school_rounded,
  'health': Icons.favorite_rounded,
  'salary': Icons.work_rounded,
  'allowance': Icons.account_balance_wallet_rounded,
  'other': Icons.category_rounded,
};

IconData categoryIcon(String key) {
  return categoryIcons[key] ?? Icons.category_rounded;
}

ThemeData pocketWiseTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: brandColor,
    brightness: Brightness.light,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: pageBackground,
    appBarTheme: const AppBarTheme(
      backgroundColor: pageBackground,
      foregroundColor: Color(0xFF172B4D),
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 16,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFDCE2ED)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFDCE2ED)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: brandColor, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 50),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: brandColor,
      foregroundColor: Colors.white,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: scheme.primaryContainer,
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
    ),
    dividerTheme: const DividerThemeData(
      color: Color(0xFFE5E9F1),
      thickness: 1,
    ),
  );
}