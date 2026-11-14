import 'package:flutter/material.dart';

@immutable
class XuColors extends ThemeExtension<XuColors> {
  const XuColors({
    required this.canvas,
    required this.sidebar,
    required this.topbar,
    required this.selection,
    required this.muted,
    required this.secondaryText,
    required this.border,
  });

  final Color canvas, sidebar, topbar, selection, muted, secondaryText, border;

  static const light = XuColors(
    canvas: Color(0xfff2f4f0),
    sidebar: Color(0xfff1f2ee),
    topbar: Color(0xfffdfdfd),
    selection: Color(0xffd9e0db),
    muted: Color(0xffedf0ec),
    secondaryText: Color(0xff6c6d6b),
    border: Color(0xffd8dad6),
  );
  static const dark = XuColors(
    canvas: Color(0xff1d2422),
    sidebar: Color(0xff202925),
    topbar: Color(0xff252e2b),
    selection: Color(0xff304640),
    muted: Color(0xff2c3934),
    secondaryText: Color(0xffbcc8c3),
    border: Color(0xff4a5752),
  );

  static XuColors of(BuildContext context) =>
      Theme.of(context).extension<XuColors>()!;

  @override
  XuColors copyWith({
    Color? canvas,
    Color? sidebar,
    Color? topbar,
    Color? selection,
    Color? muted,
    Color? secondaryText,
    Color? border,
  }) => XuColors(
    canvas: canvas ?? this.canvas,
    sidebar: sidebar ?? this.sidebar,
    topbar: topbar ?? this.topbar,
    selection: selection ?? this.selection,
    muted: muted ?? this.muted,
    secondaryText: secondaryText ?? this.secondaryText,
    border: border ?? this.border,
  );

  @override
  XuColors lerp(ThemeExtension<XuColors>? other, double t) {
    if (other is! XuColors) return this;
    return XuColors(
      canvas: Color.lerp(canvas, other.canvas, t)!,
      sidebar: Color.lerp(sidebar, other.sidebar, t)!,
      topbar: Color.lerp(topbar, other.topbar, t)!,
      selection: Color.lerp(selection, other.selection, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      secondaryText: Color.lerp(secondaryText, other.secondaryText, t)!,
      border: Color.lerp(border, other.border, t)!,
    );
  }
}

class XuTheme {
  static ThemeData build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final colors = dark ? XuColors.dark : XuColors.light;
    final accent = dark ? const Color(0xff8ac7b8) : const Color(0xff21504b);
    final foreground = dark ? const Color(0xfff3f6f2) : const Color(0xff1f1f1f);
    final scheme =
        ColorScheme.fromSeed(
          seedColor: accent,
          brightness: brightness,
        ).copyWith(
          primary: accent,
          onPrimary: dark ? colors.canvas : Colors.white,
          surface: dark ? const Color(0xff26302d) : Colors.white,
          onSurface: foreground,
          outline: colors.border,
          outlineVariant: colors.border,
          surfaceContainerLow: colors.sidebar,
          surfaceContainer: colors.muted,
        );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: colors.canvas,
      cardColor: scheme.surface,
      fontFamily: '.AppleSystemUIFont',
      extensions: [colors],
      textTheme: TextTheme(
        headlineMedium: TextStyle(
          fontSize: 30,
          fontWeight: FontWeight.w600,
          color: foreground,
        ),
        titleLarge: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: foreground,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: foreground,
        ),
        bodyMedium: TextStyle(fontSize: 14, color: foreground),
        bodySmall: TextStyle(fontSize: 13, color: colors.secondaryText),
        labelSmall: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: colors.secondaryText,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 40),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colors.border),
        ),
      ),
      dividerTheme: DividerThemeData(color: colors.border, thickness: 1),
    );
  }
}
