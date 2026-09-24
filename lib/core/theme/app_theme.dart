import 'package:flutter/material.dart';

// 浅色和深色页面共用一组主题规则。
ThemeData appTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF315F49),
    brightness: brightness,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: brightness == Brightness.light
        ? const Color(0xFFF7F8F5)
        : const Color(0xFF15211F),
  );
}
