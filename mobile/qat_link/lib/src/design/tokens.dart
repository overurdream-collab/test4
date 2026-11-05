import 'package:flutter/material.dart';

abstract final class QColors {
  static const brightGreen = Color(0xFF12C85A);
  static const freshGreen = Color(0xFF32E875);
  static const lightGreen = Color(0xFF70F5A4);
  static const softMint = Color(0xFFE6FBEF);
  static const pureWhite = Color(0xFFFFFFFF);
  static const pearlWhite = Color(0xFFF8FCF9);
  static const charcoal = Color(0xFF26352D);
  static const neutralGray = Color(0xFF84918A);
  static const premiumGold = Color(0xFFD8B75C);

  static const pendingBg = Color(0xFFFAEEDA);
  static const pendingFg = Color(0xFF8A5A00);
  static const approvedBg = Color(0xFFEAF3DE);
  static const approvedFg = Color(0xFF2C6A1E);
  static const rejectedBg = Color(0xFFFCEBEB);
  static const rejectedFg = Color(0xFFB3261E);
  static const editBg = Color(0xFFFAECE7);
  static const editFg = Color(0xFF9C3D15);
  static const localBg = Color(0xFFEDF0EE);
  static const localFg = Color(0xFF56615B);

  static const night = Color(0xFF0C1510);
  static const nightSurface = Color(0xFF14231B);
  static const nightCard = Color(0xFF1A2C22);
  static const nightText = Color(0xFFF2FBF5);
  static const nightMuted = Color(0xFFA7B8AD);

  static const gradient = LinearGradient(
    begin: Alignment.topRight,
    end: Alignment.bottomLeft,
    colors: [brightGreen, freshGreen, lightGreen],
  );

  static const softGradient = LinearGradient(
    begin: Alignment.topRight,
    end: Alignment.bottomLeft,
    colors: [softMint, pureWhite],
  );

  static const brandGlow = <BoxShadow>[
    BoxShadow(color: Color(0x3312C85A), blurRadius: 32, offset: Offset(0, 14)),
  ];
}

abstract final class QSpace {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
  static const huge = 48.0;
}

abstract final class QRadius {
  static const sm = 10.0;
  static const md = 16.0;
  static const lg = 22.0;
  static const xl = 30.0;
  static const pill = 999.0;
}

abstract final class QDuration {
  static const fast = Duration(milliseconds: 160);
  static const normal = Duration(milliseconds: 280);
  static const slow = Duration(milliseconds: 520);
}
