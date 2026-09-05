import 'package:flutter/material.dart';

class AppColors {
  static const Color navy = Color(0xFF1B2A4A);
  static const Color navyLight = Color(0xFF243558);
  static const Color yellow = Color(0xFFF5C300);
  static const Color yellowDark = Color(0xFFE0B000);
  static const Color white = Color(0xFFFFFFFF);
  static const Color offWhite = Color(0xFFF5F5F5);
  static const Color grey = Color(0xFF9E9E9E);
  static const Color greyLight = Color(0xFFE0E0E0);
  static const Color red = Color(0xFFE53935);
  static const Color green = Color(0xFF43A047);
  static const Color cardBorder = Color(0xFF2E3F63);
}

class AppTextStyles {
  static const String fontFamily = 'Georgia';

  static const TextStyle heading1 = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.bold,
    color: AppColors.white,
    letterSpacing: 0.5,
  );

  static const TextStyle heading2 = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.bold,
    color: AppColors.white,
    letterSpacing: 0.3,
  );

  static const TextStyle heading3 = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: AppColors.white,
  );

  static const TextStyle body = TextStyle(
    fontSize: 14,
    color: AppColors.white,
    height: 1.5,
  );

  static const TextStyle bodyGrey = TextStyle(
    fontSize: 14,
    color: AppColors.grey,
    height: 1.5,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 12,
    color: AppColors.grey,
  );

  static const TextStyle buttonText = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.bold,
    color: AppColors.navy,
    letterSpacing: 1,
  );

  static const TextStyle buttonTextWhite = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.bold,
    color: AppColors.white,
    letterSpacing: 1,
  );

  static const TextStyle yellowBold = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.bold,
    color: AppColors.yellow,
    letterSpacing: 1,
  );
}

class AppTheme {
  static ThemeData get theme => ThemeData(
        scaffoldBackgroundColor: AppColors.navy,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.yellow,
          secondary: AppColors.navyLight,
          surface: AppColors.navyLight,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.navy,
          elevation: 0,
          iconTheme: IconThemeData(color: AppColors.white),
          titleTextStyle: TextStyle(
            color: AppColors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.yellow,
            foregroundColor: AppColors.navy,
            minimumSize: const Size(double.infinity, 52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            textStyle: AppTextStyles.buttonText,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.white,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide:
                const BorderSide(color: AppColors.yellow, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.red, width: 1),
          ),
          hintStyle: const TextStyle(color: AppColors.grey),
          labelStyle: const TextStyle(color: AppColors.grey),
        ),
      );
}