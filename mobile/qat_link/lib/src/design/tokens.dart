import 'package:flutter/material.dart';

abstract final class QColors {
  static const brightGreen = Color(0xFF176B70);
  static const freshGreen = Color(0xFF64C0AB);
  static const lightGreen = Color(0xFFA7DCCB);
  static const softMint = Color(0xFFD9F0F6);
  static const pureWhite = Color(0xFFFFFFFF);
  static const pearlWhite = Color(0xFFF1F8FA);
  static const charcoal = Color(0xFF0F172A);
  static const neutralGray = Color(0xFF64748B);
  static const premiumGold = Color(0xFFD8B75C);
  static const danger = Color(0xFFEF4444);
  static const dangerSoft = Color(0xFFFFE4E6);

  static const pendingBg = Color(0xFFFEF3C7);
  static const pendingFg = Color(0xFFB45309);
  static const approvedBg = Color(0xFFDCFCE7);
  static const approvedFg = Color(0xFF15803D);
  static const rejectedBg = Color(0xFFFEE2E2);
  static const rejectedFg = Color(0xFFB91C1C);
  static const editBg = Color(0xFFFFEDD5);
  static const editFg = Color(0xFFC2410C);
  static const localBg = Color(0xFFF1F5F9);
  static const localFg = Color(0xFF475569);

  static const night = Color(0xFF0F172A);
  static const nightSurface = Color(0xFF162032);
  static const nightCard = Color(0xFF1E293B);
  static const nightText = Color(0xFFF8FAFC);
  static const nightMuted = Color(0xFF94A3B8);

  static const gradient = LinearGradient(
    begin: Alignment.topRight,
    end: Alignment.bottomLeft,
    colors: [brightGreen, freshGreen],
  );

  static const addGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFF7777), danger],
  );

  static const softGradient = LinearGradient(
    begin: Alignment.topRight,
    end: Alignment.bottomLeft,
    colors: [softMint, pureWhite],
  );

  static const brandGlow = <BoxShadow>[
    BoxShadow(color: Color(0x33176B70), blurRadius: 32, offset: Offset(0, 14)),
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
