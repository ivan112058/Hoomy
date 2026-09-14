import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hoomy/core/theme/hoomy_theme.dart';
import 'package:hoomy/data/subsonic/models.dart';
import 'package:hoomy/features/player/mini_player_bar.dart';
import 'package:hoomy/features/player/playback_listenable.dart';
import 'package:hoomy/features/shared/cover_art.dart';
import 'package:hoomy/player/playback_controller.dart';
import 'package:hoomy/player/player_engine.dart';
import 'package:hoomy/player/player_providers.dart';

import 'fake_player_engine.dart';

/// 票据 08 的界面验收：迷你播放条的呈现与控制。
///
/// 迷你播放条只读 [PlaybackController] 的合并快照；这里用 [FakePlayerEngine]
/// 驱动一个真实控制器，于是「引擎状态 → 条上显示什么」可以完整断言，
/// 不依赖音频设备，也不需要 `subsonicClientProvider`（封面走占位）。
void main() {
  Uri resolveUri(String id) =>
      Uri.parse('http://nas.local:4533/rest/stream.view?id=$id&format=raw');

  const sunshine = SubsonicSong(
    id: 's1',
    title: '晴天',
    artist: '周杰伦',
    album: '叶惠美',
    durationSec: 269,
  );
  const father = SubsonicSong(
    id: 's2',
    title: '以父之名',
    artist: '周杰伦',
    album: '叶惠美',
    durationSec: 259,
  );

  /// 迷你播放条 + 可注入的点击回调；形如主壳里的挂法。
  Widget harness(
    PlaybackController controller, {
    VoidCallback? onTap,
  }) => ProviderScope(
    overrides: [playerControllerProvider.overrideWithValue(controller)],
    child: MaterialApp(
      theme: hoomyLightTheme(),
      home: Scaffold(
        body: const SizedBox.expand(),
        bottomNavigationBar: MiniPlayerBar(onTap: onTap),
      ),
    ),
  );

  /// 新控制器；`addTearDown` 保证每个用例都不留悬挂订阅。
  PlaybackController newController(FakePlayerEngine engine) {
    final controller = PlaybackController(engine: engine, streamUriOf: resolveUri);
    addTearDown(controller.dispose);
    return controller;
  }

  testWidgets('没有当前曲目时不渲染，也不占位', (tester) async {
    final engine = FakePlayerEngine();
    final controller = newController(engine);

    await tester.pumpWidget(harness(controller));
    await tester.pumpAndSettle();

    expect(find.text('晴天'), findsNothing);
    expect(find.byType(MiniPlayerBar), findsOneWidget);
    // 内容不占位：整个迷你条的高度为 0。
    expect(tester.getSize(find.byType(MiniPlayerBar)).height, 0);

    // 有曲目后清空队列（例如系统 stop），迷你条重新收起、退回不占位。
    await controller.playQueue(const [sunshine]);
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(MiniPlayerBar)).height, greaterThan(0));

    await controller.playQueue(const []);
    await tester.pumpAndSettle();
    expect(find.text('晴天'), findsNothing);
    expect(tester.getSize(find.byType(MiniPlayerBar)).height, 0);
  });

  testWidgets('有当前曲目时显示封面、歌名与歌手，且不显示进度', (tester) async {
    final engine = FakePlayerEngine();
    final controller = newController(engine);

    await tester.pumpWidget(harness(controller));
    await tester.pumpAndSettle();
    await controller.playQueue(const [sunshine, father]);
    await tester.pumpAndSettle();

    expect(find.text('晴天'), findsOneWidget);
    expect(find.text('周杰伦'), findsOneWidget);
    expect(find.byType(CoverArt), findsOneWidget);
    expect(tester.getSize(find.byType(CoverArt)), const Size(40, 40));
    // 刻意不显示进度：没有进度条，也没有时间文字。
    expect(find.byType(Slider), findsNothing);
    expect(find.text('0:00'), findsNothing);
  });

  testWidgets('收藏按钮反映当前曲目的收藏状态且已接线（票据 12）', (tester) async {
    final engine = FakePlayerEngine();
    final controller = newController(engine);

    await tester.pumpWidget(harness(controller));
    await tester.pumpAndSettle();
    await controller.playQueue(const [sunshine]);
    await tester.pumpAndSettle();

    // 未收藏：空心星，且可点（乐观更新与回滚封在 StarButton 里）。
    expect(find.byIcon(Icons.star_border), findsOneWidget);
    final star = tester.widget<IconButton>(
      find.ancestor(
        of: find.byIcon(Icons.star_border),
        matching: find.byType(IconButton),
      ),
    );
    expect(star.onPressed, isNotNull, reason: '收藏写路径已由票据 12 接线');

    // 已收藏：实心星。
    await controller.playQueue(const [
      SubsonicSong(id: 's9', title: '已收藏', starred: '2026-09-01T00:00:00Z'),
    ]);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.star), findsOneWidget);
    expect(find.byIcon(Icons.star_border), findsNothing);
  });

  testWidgets('上一首、下一首、播放／暂停与当前播放状态一致', (tester) async {
    final engine = FakePlayerEngine();
    final controller = newController(engine);

    await tester.pumpWidget(harness(controller));
    await tester.pumpAndSettle();
    await controller.playQueue(const [sunshine, father]);
    await tester.pumpAndSettle();

    // 正在播第一首：按钮显示「暂停」。
    expect(find.byTooltip('暂停'), findsOneWidget);
    expect(find.byTooltip('播放'), findsNothing);

    await tester.tap(find.byTooltip('下一首'));
    await tester.pumpAndSettle();
    expect(engine.lastLoadedId, 's2');
    expect(find.text('以父之名'), findsOneWidget);

    await tester.tap(find.byTooltip('上一首'));
    await tester.pumpAndSettle();
    expect(engine.lastLoadedId, 's1');

    await tester.tap(find.byTooltip('暂停'));
    await tester.pumpAndSettle();
    expect(engine.pauseCount, 1);
    // 暂停后按钮变为「播放」。
    expect(find.byTooltip('播放'), findsOneWidget);

    await tester.tap(find.byTooltip('播放'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('暂停'), findsOneWidget);
    // 1 次开播 + 换歌 2 次（下一首、上一首各重载一次）+ 1 次从暂停继续。
    expect(engine.playCount, 4);
  });

  testWidgets('切换曲目时内容即时更新', (tester) async {
    final engine = FakePlayerEngine();
    final controller = newController(engine);

    await tester.pumpWidget(harness(controller));
    await tester.pumpAndSettle();
    await controller.playQueue(const [sunshine, father]);
    await tester.pumpAndSettle();
    expect(find.text('晴天'), findsOneWidget);

    await controller.next();
    await tester.pumpAndSettle();

    expect(find.text('晴天'), findsNothing);
    expect(find.text('以父之名'), findsOneWidget);
  });

  testWidgets('播放状态变化时图标即时更新', (tester) async {
    final engine = FakePlayerEngine();
    final controller = newController(engine);

    await tester.pumpWidget(harness(controller));
    await tester.pumpAndSettle();
    await controller.playQueue(const [sunshine]);
    await tester.pumpAndSettle();
    expect(find.byTooltip('暂停'), findsOneWidget);

    // 来自引擎的状态（例如系统媒体键暂停）同样即时反映。
    engine.emitState(
      const PlayerEngineState(playing: false, status: PlayerEngineStatus.ready),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('播放'), findsOneWidget);
    expect(find.byTooltip('暂停'), findsNothing);
  });

  testWidgets('点迷你条触发展开回调', (tester) async {
    final engine = FakePlayerEngine();
    final controller = newController(engine);
    var taps = 0;

    await tester.pumpWidget(harness(controller, onTap: () => taps++));
    await tester.pumpAndSettle();
    await controller.playQueue(const [sunshine]);
    await tester.pumpAndSettle();

    await tester.tap(find.text('晴天'));
    await tester.pumpAndSettle();
    expect(taps, 1);

    // 条上的控制按钮不冒泡成「展开」。
    await tester.tap(find.byTooltip('下一首'));
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets('无歌手时退回专辑，两者都没有则不占副标题行', (tester) async {
    final engine = FakePlayerEngine();
    final controller = newController(engine);

    await tester.pumpWidget(harness(controller));
    await tester.pumpAndSettle();
    await controller.playQueue(const [
      SubsonicSong(id: 's3', title: '无歌手', album: '某专辑'),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('某专辑'), findsOneWidget);

    await controller.playQueue(const [SubsonicSong(id: 's4', title: '光秃秃')]);
    await tester.pumpAndSettle();
    expect(find.text('光秃秃'), findsOneWidget);
  });

  testWidgets('系统字号放大时条随内容长高，不把文字挤出边界', (tester) async {
    final engine = FakePlayerEngine();
    final controller = newController(engine);

    // 电视上系统字号会放大到 1.3（票据 06 记的底部溢出就出在这种场景）。
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
        child: harness(controller),
      ),
    );
    await tester.pumpAndSettle();
    await controller.playQueue(const [sunshine]);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byType(MiniPlayerBar)).height,
      greaterThanOrEqualTo(MiniPlayerBar.height),
    );
  });

  testWidgets('进度通知不带着迷你条重建', (tester) async {
    final engine = FakePlayerEngine();
    final controller = newController(engine);
    final rebuilds = _BuildCounter();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [playerControllerProvider.overrideWithValue(controller)],
        child: MaterialApp(
          home: Scaffold(
            body: PlaybackListenable(
              // 与迷你条同一口径（`PlaybackSession.identity`）：只关心
              // 「哪首、在不在播」。
              select: (controller) => controller.session.identity,
              builder: (context, controller) {
                rebuilds.count++;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await controller.playQueue(const [sunshine, father]);
    await tester.pumpAndSettle();
    final settled = rebuilds.count;

    // 进度每 ~200ms 推一次，但挑出的值没变：不该重建。
    engine.emitPosition(const Duration(seconds: 1));
    engine.emitPosition(const Duration(seconds: 2));
    await tester.pump();
    expect(rebuilds.count, settled, reason: '进度通知不应带着选中边界重建');

    // 换歌改变了挑出的值：必须重建。
    await controller.next();
    await tester.pumpAndSettle();
    expect(rebuilds.count, greaterThan(settled));
  });

  testWidgets('不传 select 时任何通知都重建（默认路径）', (tester) async {
    final engine = FakePlayerEngine();
    final controller = newController(engine);
    final rebuilds = _BuildCounter();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [playerControllerProvider.overrideWithValue(controller)],
        child: MaterialApp(
          home: Scaffold(
            body: PlaybackListenable(
              builder: (context, controller) {
                rebuilds.count++;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final settled = rebuilds.count;

    // 进度通知也重建 —— 这正是「不传 select」的约定，与上一条用例相反。
    engine.emitPosition(const Duration(seconds: 1));
    await tester.pump();
    expect(rebuilds.count, greaterThan(settled));
  });
}

/// 只用来数重建次数的可变计数盒：`PlaybackListenable` 的 builder 每跑一次就 +1。
class _BuildCounter {
  int count = 0;
}
