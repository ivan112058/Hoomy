import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hoomy/core/theme/hoomy_theme.dart';
import 'package:hoomy/features/shared/hoomy_list_row.dart';

/// 视觉与交互约定的行为接缝。
///
/// 票据 03 的最终验收以真机目视为准；这里钉住**可自动观察的部分**：
/// 行的几何尺寸、按下态的整行底色与前景切换、副标题拼接、分隔线整宽、
/// 专辑固定列数，以及主题里逐值声明的色值。观感仍由人工在真机上确认。
void main() {
  Widget harness(Widget child, {bool dark = false}) => MaterialApp(
        theme: dark ? hoomyDarkTheme() : hoomyLightTheme(),
        home: Scaffold(body: child),
      );

  Color? titleColor(WidgetTester tester, String text) =>
      tester.widget<Text>(find.text(text)).style?.color;

  Color? rowBackground(WidgetTester tester) => tester
      .widget<ColoredBox>(find
          .descendant(
            of: find.byType(HoomyListRow).first,
            matching: find.byType(ColoredBox),
          )
          .first)
      .color;

  group('列表行', () {
    testWidgets('60dp 高，标题 16sp、副标题 13sp', (tester) async {
      await tester.pumpWidget(harness(
        const HoomyListRow(title: '晴天', subtitle: '周杰伦 - 叶惠美'),
      ));

      expect(tester.getSize(find.byType(HoomyListRow)).height, 60);
      expect(tester.widget<Text>(find.text('晴天')).style?.fontSize, 16);
      expect(tester.widget<Text>(find.text('周杰伦 - 叶惠美')).style?.fontSize, 13);
    });

    testWidgets('按下时整行蓝底，标题、副标题与图标变白', (tester) async {
      await tester.pumpWidget(harness(
        HoomyListRow(
          title: '晴天',
          subtitle: '周杰伦 - 叶惠美',
          onTap: () {},
          trailing: (state) => Icon(
            Icons.star,
            key: const Key('row-icon'),
            color: state.pressed ? Colors.white : null,
          ),
        ),
      ));

      // 未按下：无底色，文字用主/次文字色。
      expect(rowBackground(tester), Colors.transparent);
      expect(titleColor(tester, '晴天'), HoomyColors.lightTextPrimary);
      expect(titleColor(tester, '周杰伦 - 叶惠美'), HoomyColors.lightTextSecondary);

      final gesture = await tester.startGesture(tester.getCenter(find.text('晴天')));
      await tester.pump();

      // 按下：整行交互蓝，标题、副标题、图标全部变白。
      expect(rowBackground(tester), HoomyColors.interactionBlue);
      expect(titleColor(tester, '晴天'), Colors.white);
      expect(titleColor(tester, '周杰伦 - 叶惠美'), Colors.white);
      expect(tester.widget<Icon>(find.byKey(const Key('row-icon'))).color, Colors.white);

      await gesture.up();
      await tester.pump(const Duration(milliseconds: 64));

      // 抬起后恢复。
      expect(rowBackground(tester), Colors.transparent);
      expect(titleColor(tester, '晴天'), HoomyColors.lightTextPrimary);
    });

    testWidgets('同帧完成的快速点击仍可见一瞬按压态', (tester) async {
      await tester.pumpWidget(harness(
        HoomyListRow(title: '晴天', onTap: () {}),
      ));

      // 按下与抬起之间不 pump，模拟同一帧内完成的点击。
      final gesture = await tester.startGesture(tester.getCenter(find.text('晴天')));
      await gesture.up();
      await tester.pump();

      expect(rowBackground(tester), HoomyColors.interactionBlue);

      await tester.pump(const Duration(milliseconds: 64));
      expect(rowBackground(tester), Colors.transparent);
    });

    testWidgets('未显式着色的行首图标在按下时也变白', (tester) async {
      await tester.pumpWidget(harness(
        const HoomyListRow(
          title: '设置',
          leading: Icon(Icons.settings_outlined, key: Key('row-leading')),
        ),
      ));

      final gesture = await tester.startGesture(tester.getCenter(find.text('设置')));
      await tester.pump();

      final icon = tester.widget<Icon>(find.byKey(const Key('row-leading')));
      expect(icon.color, isNull, reason: '图标不带显式色，应继承行内 IconTheme');
      final iconTheme = IconTheme.of(tester.element(find.byKey(const Key('row-leading'))));
      expect(iconTheme.color, Colors.white);

      await gesture.up();
    });

    testWidgets('列表滚动取消按压态，行不会整段滑动保持蓝色', (tester) async {
      await tester.pumpWidget(harness(
        ListView(
          children: [
            for (var i = 0; i < 30; i++)
              HoomyListRow(title: i == 0 ? '晴天' : '歌曲 $i', onTap: () {}),
          ],
        ),
      ));

      final gesture = await tester.startGesture(tester.getCenter(find.text('晴天')));
      await tester.pump();
      await gesture.moveBy(const Offset(0, -50));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 64));

      expect(rowBackground(tester), Colors.transparent);
      await gesture.up();
    });

    testWidgets('深色主题下按下同样是交互蓝与白前景', (tester) async {
      await tester.pumpWidget(harness(
        const HoomyListRow(title: '晴天', subtitle: '周杰伦 - 叶惠美'),
        dark: true,
      ));

      expect(titleColor(tester, '晴天'), HoomyColors.darkTextPrimary);
      expect(titleColor(tester, '周杰伦 - 叶惠美'), HoomyColors.darkTextSecondary);

      final gesture = await tester.startGesture(tester.getCenter(find.text('晴天')));
      await tester.pump();

      expect(rowBackground(tester), HoomyColors.interactionBlue);
      expect(titleColor(tester, '晴天'), Colors.white);

      await gesture.up();
    });
  });

  group('主题 token', () {
    test('浅色：页底、主次文字、分隔线逐值对齐', () {
      final theme = hoomyLightTheme();
      final palette = theme.extension<HoomyPalette>()!;
      expect(theme.scaffoldBackgroundColor, const Color(0xFFFFFFFF));
      expect(palette.titleBar, const Color(0xFFFFFFFF));
      expect(palette.surfaceRaised, const Color(0xFFF7F8F9));
      expect(palette.textPrimary, const Color(0xCC000000));
      expect(palette.textSecondary, const Color(0x66000000));
      expect(palette.divider, const Color(0xFFEBEBEB));
    });

    test('深色：页底、卡片、主次文字、分隔线逐值对齐', () {
      final theme = hoomyDarkTheme();
      final palette = theme.extension<HoomyPalette>()!;
      expect(theme.scaffoldBackgroundColor, const Color(0xFF25282D));
      expect(palette.titleBar, const Color(0xFF292C31));
      expect(palette.card, const Color(0xFF34373C));
      expect(palette.surfaceRaised, const Color(0xFF41464D));
      expect(palette.textPrimary, const Color(0xFFF2F2F2));
      expect(palette.textSecondary, const Color(0xFF9FA1A4));
      expect(palette.divider, const Color(0xFF3A3D42));
    });

    test('强调色浅深通用：播放红、交互蓝、歌词高亮蓝', () {
      for (final theme in [hoomyLightTheme(), hoomyDarkTheme()]) {
        final palette = theme.extension<HoomyPalette>()!;
        expect(palette.playing, const Color(0xFFE64040));
        expect(palette.pressedBackground, const Color(0xFF5C89F2));
        expect(palette.lyricHighlight, const Color(0xFF4A69B3));
      }
    });

    test('分隔线 0.67dp，界面基本无圆角', () {
      for (final theme in [hoomyLightTheme(), hoomyDarkTheme()]) {
        expect(theme.dividerTheme.thickness, 0.67);
        expect(theme.dividerTheme.space, 0.67);
        for (final shape in [
          theme.filledButtonTheme.style?.shape,
          theme.outlinedButtonTheme.style?.shape,
          theme.textButtonTheme.style?.shape,
          theme.elevatedButtonTheme.style?.shape,
        ]) {
          expect(_radius(shape), 0, reason: '按钮必须直角');
        }
        expect((theme.navigationBarTheme.indicatorShape as RoundedRectangleBorder?)
            ?.borderRadius, BorderRadius.zero);
      }
    });

    testWidgets('标题栏实际渲染高度 50dp、标题 20sp', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: hoomyLightTheme(),
        home: Scaffold(appBar: AppBar(title: const Text('歌曲')), body: const SizedBox()),
      ));

      expect(tester.getSize(find.byType(AppBar)).height, 50);
      // AppBar 经 DefaultTextStyle 施加标题样式，读渲染段落的最终样式。
      final title = tester.renderObject<RenderParagraph>(find.text('歌曲'));
      expect(title.text.style?.fontSize, 20);
    });

    testWidgets('分隔线渲染为整宽、0.67dp 细线', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: hoomyLightTheme(),
        home: const Scaffold(
          body: SizedBox(width: 320, child: Divider()),
        ),
      ));

      expect(tester.getSize(find.byType(Divider)).width, 320);
      expect(tester.getSize(find.byType(Divider)).height, 0.67);
    });
  });
}

double _radius(WidgetStateProperty<OutlinedBorder?>? shape) {
  final border = shape?.resolve(<WidgetState>{});
  return border is RoundedRectangleBorder
      ? (border.borderRadius as BorderRadius).topLeft.x
      : -1;
}
