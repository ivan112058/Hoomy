import 'package:flutter/material.dart';

/// Smartisan 风格设计 token。
/// 色值移植自 SmartisanMusic-Revived（浅色为原版，深色为其自创炭灰系）。
abstract final class HoomyColors {
  // 强调色（浅深通用）
  static const playingRed = Color(0xFFE64040);
  static const highlightRed = Color(0xFFC14352);
  static const pressBlue = Color(0xFF4A69B3);
  static const actionBlue = Color(0xFF5C89F2);
  static const actionRed = Color(0xFFE65C53);

  static const lightDivider = Color(0xFFEBEBEB);
  static const darkDivider = Color(0xFF3C3F44);
}

ThemeData hoomyLightTheme() => _build(
      brightness: Brightness.light,
      scaffold: const Color(0xFFFFFFFF),
      titleBar: const Color(0xFFFFFFFF),
      surface: const Color(0xFFF7F7F7),
      textPrimary: const Color(0xCC000000),
      textSecondary: const Color(0x66000000),
      divider: HoomyColors.lightDivider,
    );

ThemeData hoomyDarkTheme() => _build(
      brightness: Brightness.dark,
      scaffold: const Color(0xFF25282D),
      titleBar: const Color(0xFF292C31),
      surface: const Color(0xFF34373C),
      textPrimary: const Color(0xFFF2F2F2),
      textSecondary: const Color(0x99F2F2F2),
      divider: HoomyColors.darkDivider,
    );

ThemeData _build({
  required Brightness brightness,
  required Color scaffold,
  required Color titleBar,
  required Color surface,
  required Color textPrimary,
  required Color textSecondary,
  required Color divider,
}) {
  final scheme = ColorScheme.fromSeed(
    seedColor: HoomyColors.playingRed,
    brightness: brightness,
  ).copyWith(
    surface: scaffold,
    secondaryContainer: surface,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scaffold,
    splashFactory: InkRipple.splashFactory,
    dividerColor: divider,
    textTheme: (brightness == Brightness.light
            ? Typography.blackCupertino
            : Typography.whiteCupertino)
        .apply(
      bodyColor: textPrimary,
      displayColor: textPrimary,
    ),
    listTileTheme: ListTileThemeData(
      textColor: textPrimary,
      iconColor: textSecondary,
      shape: const RoundedRectangleBorder(),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: titleBar,
      foregroundColor: textPrimary,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: textPrimary,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: titleBar,
      indicatorColor: surface,
      labelTextStyle: const WidgetStatePropertyAll(
        TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      hintStyle: TextStyle(color: textSecondary),
      border: UnderlineInputBorder(borderSide: BorderSide(color: divider)),
    ),
    extensions: [
      _HoomySheet(
        titleBar: titleBar,
        textPrimary: textPrimary,
        textSecondary: textSecondary,
      ),
    ],
  );
}

/// 需要在 Theme 之外传递的颜色，挂在 ThemeExtension 上。
class _HoomySheet extends ThemeExtension<_HoomySheet> {
  const _HoomySheet({
    required this.titleBar,
    required this.textPrimary,
    required this.textSecondary,
  });

  final Color titleBar;
  final Color textPrimary;
  final Color textSecondary;

  @override
  _HoomySheet copyWith({Color? titleBar, Color? textPrimary, Color? textSecondary}) =>
      _HoomySheet(
        titleBar: titleBar ?? this.titleBar,
        textPrimary: textPrimary ?? this.textPrimary,
        textSecondary: textSecondary ?? this.textSecondary,
      );

  @override
  _HoomySheet lerp(_HoomySheet? other, double t) => other == null
      ? this
      : _HoomySheet(
          titleBar: Color.lerp(titleBar, other.titleBar, t)!,
          textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
          textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
        );
}
