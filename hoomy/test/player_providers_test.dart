import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hoomy/data/session/session_providers.dart';
import 'package:hoomy/player/just_audio_player_engine.dart';
import 'package:hoomy/player/player_providers.dart';

/// 票据 04：播放层与会话解耦。
///
/// 会话只提供两个地址函数（歌曲播放地址、封面地址），播放引擎本身与会话无关；
/// 未登录时外壳不挂载，也就没人读播放控制器，引擎不会被构造。
void main() {
  // 用 testWidgets 而不是 test：默认实现会构造 `just_audio` 的 `AudioPlayer`，
  // 需要先初始化测试绑定。
  testWidgets('播放引擎不依赖会话：容器里没有会话也构造得出来', (tester) async {
    final container = ProviderContainer(
      overrides: [
        // 任何读取会话的尝试都会抛：引擎若偷偷依赖会话，这条用例就会红。
        sessionOrNullProvider.overrideWith((ref) => throw StateError('播放引擎不该读会话')),
        sessionProvider.overrideWith((ref) => throw StateError('播放引擎不该读会话')),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(playerEngineProvider), isA<JustAudioPlayerEngine>());
  });
}
