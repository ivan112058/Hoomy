import 'package:flutter/material.dart';

/// Hoomy 视觉 token，逐值对齐 `CONTEXT.md` 的「视觉与交互约定」
/// 与 SmartisanMusic-Revived（commit `428ac08`，ADR-0003）。
///
/// 浅色为参考项目的日间原值；深色沿用其自创的炭灰色板。
/// 强调色深浅通用，不随主题切换。
abstract final class HoomyColors {
  // 强调色（浅深通用）

  /// 播放态红。
  static const playingRed = Color(0xFFE64040);

  /// 交互蓝：也是列表行按下时的整行底色。
  static const interactionBlue = Color(0xFF5C89F2);

  /// 歌词高亮蓝。
  static const lyricHighlightBlue = Color(0xFF4A69B3);

  /// 按下时前景（文字与图标）统一变白。
  static const pressedForeground = Color(0xFFFFFFFF);

  // 浅色

  static const lightPageBackground = Color(0xFFFFFFFF);
  static const lightCard = Color(0xFFFFFFFF);
  static const lightSurfaceRaised = Color(0xFFF7F8F9);
  static const lightTextPrimary = Color(0xCC000000);
  static const lightTextSecondary = Color(0x66000000);
  static const lightDivider = Color(0xFFEBEBEB);

  // 深色（炭灰色板）

  static const darkPageBackground = Color(0xFF25282D);
  static const darkTitleBar = Color(0xFF292C31);
  static const darkCard = Color(0xFF34373C);
  static const darkSurfaceRaised = Color(0xFF41464D);
  static const darkTextPrimary = Color(0xFFF2F2F2);
  static const darkTextSecondary = Color(0xFF9FA1A4);
  static const darkDivider = Color(0xFF3A3D42);
}

/// 尺寸 token。
abstract final class HoomyDimens {
  /// 标题栏高度。
  static const titleBarHeight = 50.0;

  /// 标题栏标题字号。
  static const titleFontSize = 20.0;

  /// 列表行高（不含封面缩略图）。
  static const listRowHeight = 60.0;

  /// 列表标题字号。
  static const listTitleFontSize = 16.0;

  /// 列表副标题与时长字号。
  static const listSubtitleFontSize = 13.0;

  /// 分隔线粗细。
  static const dividerThickness = 0.67;

  /// 专辑网格固定列数，不随屏宽改变。
  static const albumGridColumns = 3;
}

/// 一套主题内的语义色板。
///
/// 让部件读「卡片底」「次文字」之类的语义，而不是硬编码某个色值；
/// 浅深两套由 [light] / [dark] 提供，[of] 在没有扩展时退回浅色
/// （widget 测试与默认 [ThemeData] 都是这种情形）。
@immutable
class HoomyPalette extends ThemeExtension<HoomyPalette> {
  const HoomyPalette({
    required this.pageBackground,
    required this.titleBar,
    required this.card,
    required this.surfaceRaised,
    required this.textPrimary,
    required this.textSecondary,
    required this.divider,
  });

  static const light = HoomyPalette(
    pageBackground: HoomyColors.lightPageBackground,
    titleBar: HoomyColors.lightPageBackground,
    card: HoomyColors.lightCard,
    surfaceRaised: HoomyColors.lightSurfaceRaised,
    textPrimary: HoomyColors.lightTextPrimary,
    textSecondary: HoomyColors.lightTextSecondary,
    divider: HoomyColors.lightDivider,
  );

  static const dark = HoomyPalette(
    pageBackground: HoomyColors.darkPageBackground,
    titleBar: HoomyColors.darkTitleBar,
    card: HoomyColors.darkCard,
    surfaceRaised: HoomyColors.darkSurfaceRaised,
    textPrimary: HoomyColors.darkTextPrimary,
    textSecondary: HoomyColors.darkTextSecondary,
    divider: HoomyColors.darkDivider,
  );

  /// 页面底色。
  final Color pageBackground;

  /// 标题栏底色（也是底部导航栏底色）。
  final Color titleBar;

  /// 卡片/面板底色。
  final Color card;

  /// 较高的表面（占位、选中指示等）。
  final Color surfaceRaised;

  /// 主文字。
  final Color textPrimary;

  /// 次文字（副标题、时长）。
  final Color textSecondary;

  /// 分隔线。
  final Color divider;

  /// 按下时的整行底色。
  Color get pressedBackground => HoomyColors.interactionBlue;

  /// 按下时的前景色。
  Color get pressedForeground => HoomyColors.pressedForeground;

  /// 播放态强调色。
  Color get playing => HoomyColors.playingRed;

  /// 歌词当前行高亮色。
  Color get lyricHighlight => HoomyColors.lyricHighlightBlue;

  /// 取当前主题的色板；未注册扩展时退回浅色。
  static HoomyPalette of(BuildContext context) =>
      Theme.of(context).extension<HoomyPalette>() ?? light;

  @override
  HoomyPalette copyWith({
    Color? pageBackground,
    Color? titleBar,
    Color? card,
    Color? surfaceRaised,
    Color? textPrimary,
    Color? textSecondary,
    Color? divider,
  }) {
    return HoomyPalette(
      pageBackground: pageBackground ?? this.pageBackground,
      titleBar: titleBar ?? this.titleBar,
      card: card ?? this.card,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      divider: divider ?? this.divider,
    );
  }

  @override
  HoomyPalette lerp(HoomyPalette? other, double t) {
    if (other == null) return this;
    return HoomyPalette(
      pageBackground: Color.lerp(pageBackground, other.pageBackground, t)!,
      titleBar: Color.lerp(titleBar, other.titleBar, t)!,
      card: Color.lerp(card, other.card, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
    );
  }
}

/// 浅色主题（默认）。
ThemeData hoomyLightTheme() => _build(
      brightness: Brightness.light,
      palette: HoomyPalette.light,
    );

/// 深色主题（跟随系统或手动切换）。
ThemeData hoomyDarkTheme() => _build(
      brightness: Brightness.dark,
      palette: HoomyPalette.dark,
    );

/// 直角：界面基本无圆角（列表、标题栏、按钮）。
const _square = RoundedRectangleBorder();

ThemeData _build({
  required Brightness brightness,
  required HoomyPalette palette,
}) {
  final scheme = ColorScheme.fromSeed(
    seedColor: HoomyColors.playingRed,
    brightness: brightness,
  ).copyWith(
    primary: HoomyColors.playingRed,
    onPrimary: Colors.white,
    surface: palette.card,
    secondaryContainer: palette.surfaceRaised,
    onSecondaryContainer: palette.textSecondary,
  );

  final buttonShape = WidgetStatePropertyAll<OutlinedBorder>(_square);

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: palette.pageBackground,
    // 参考项目用位图 selector 做按压反馈，没有涟漪；这里统一关掉。
    splashFactory: NoSplash.splashFactory,
    dividerColor: palette.divider,
    dividerTheme: DividerThemeData(
      color: palette.divider,
      thickness: HoomyDimens.dividerThickness,
      space: HoomyDimens.dividerThickness,
    ),
    textTheme: (brightness == Brightness.light
            ? Typography.blackCupertino
            : Typography.whiteCupertino)
        .apply(
      bodyColor: palette.textPrimary,
      displayColor: palette.textPrimary,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: palette.titleBar,
      foregroundColor: palette.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: HoomyDimens.titleBarHeight,
      centerTitle: false,
      shape: _square,
      titleTextStyle: TextStyle(
        fontSize: HoomyDimens.titleFontSize,
        fontWeight: FontWeight.w700,
        color: palette.textPrimary,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: palette.titleBar,
      // 参考项目的底栏没有胶囊指示器，选中态靠图标转播放红、文字加深。
      indicatorColor: Colors.transparent,
      indicatorShape: _square,
      surfaceTintColor: Colors.transparent,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? HoomyColors.playingRed
              : palette.textSecondary,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: HoomyDimens.listSubtitleFontSize,
          fontWeight: FontWeight.w500,
          color: states.contains(WidgetState.selected)
              ? palette.textPrimary
              : palette.textSecondary,
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(style: ButtonStyle(shape: buttonShape)),
    outlinedButtonTheme: OutlinedButtonThemeData(style: ButtonStyle(shape: buttonShape)),
    textButtonTheme: TextButtonThemeData(style: ButtonStyle(shape: buttonShape)),
    elevatedButtonTheme: ElevatedButtonThemeData(style: ButtonStyle(shape: buttonShape)),
    iconButtonTheme: IconButtonThemeData(style: ButtonStyle(shape: buttonShape)),
    cardTheme: CardThemeData(shape: _square),
    dialogTheme: DialogThemeData(shape: _square),
    bottomSheetTheme: BottomSheetThemeData(shape: _square),
    snackBarTheme: SnackBarThemeData(shape: _square),
    chipTheme: ChipThemeData(shape: _square),
    inputDecorationTheme: InputDecorationTheme(
      hintStyle: TextStyle(color: palette.textSecondary),
      border: UnderlineInputBorder(borderSide: BorderSide(color: palette.divider)),
    ),
    extensions: [palette],
  );
}
