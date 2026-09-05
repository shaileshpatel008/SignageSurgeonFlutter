// lib/core/theme/app_theme.dart
import 'package:flutter/material.dart';

class AppColors {
  static const Color navy = Color(0xFF1C1F26);
  static const Color navyLight = Color(0xFF2A2E38);
  static const Color yellow = Color(0xFFFFC107);
  static const Color yellowDark = Color(0xFFE0A800);
  static const Color white = Color(0xFFFFFFFF);
  static const Color offWhite = Color(0xFFF6F7F9);
  static const Color grey = Color(0xFF6B7280);
  static const Color greyLight = Color(0xFFE5E7EB);
  static const Color red = Color(0xFFE53935);
  static const Color green = Color(0xFF22C55E);
  static const Color cardBorder = Color(0xFFE5E7EB);
  // New: banner-specific navy for image-based promo banners (e.g. Signage Cleaning)
  static const Color bannerNavy = Color(0xFF01225B);
  // Universal accent for all service-request pages (navbar, section markers,
  // current-location button, search icons, rate-chart pill). Applies the
  // same way across Repairing, Rebranding, and every future service.
  static const Color serviceAccent = Color(0xFFFEC107);
}

class AppTextStyles {
  static const String fontFamily = 'Georgia';

  static const TextStyle heading1 = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.bold,
    color: AppColors.navy,
    letterSpacing: 0.5,
  );

  static const TextStyle heading2 = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.bold,
    color: AppColors.navy,
    letterSpacing: 0.3,
  );

  static const TextStyle heading3 = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: AppColors.navy,
  );

  static const TextStyle body = TextStyle(
    fontSize: 14,
    color: AppColors.navy,
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
    color: AppColors.yellowDark,
    letterSpacing: 1,
  );
}

class AppTheme {
  static ThemeData get theme => ThemeData(
        scaffoldBackgroundColor: AppColors.offWhite,
        colorScheme: const ColorScheme.light(
          primary: AppColors.yellow,
          secondary: AppColors.navy,
          surface: AppColors.white,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.offWhite,
          elevation: 0,
          iconTheme: IconThemeData(color: AppColors.navy),
          titleTextStyle: TextStyle(
            color: AppColors.navy,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.red,
            foregroundColor: AppColors.white,
            minimumSize: const Size(double.infinity, 52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            textStyle: AppTextStyles.buttonTextWhite,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.white,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.greyLight),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.greyLight),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.yellow, width: 2),
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