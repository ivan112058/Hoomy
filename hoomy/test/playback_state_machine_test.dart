import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:hoomy/data/subsonic/models.dart';
import 'package:hoomy/player/playback_state_machine.dart';

import 'fake_player_engine.dart';

/// 播放状态机（S2）：队列推进、循环、随机与当前曲目切换的规则。
/// 全部用假引擎驱动，不依赖音频设备，也不引用具体音频库。
void main() {
  /// 造 [count] 首可辨认的歌曲：`s0`、`s1`……
  List<SubsonicSong> songs(int count) => [
        for (var i = 0; i < count; i++) SubsonicSong(id: 's$i', title: '歌曲 $i'),
      ];

  /// [count] 首歌曲的 id 集合。
  Set<String> idSet(int count) => songs(count).map((s) => s.id).toSet();

  /// 假引擎 → 状态机的固定接线：曲目 id 直接放进 stream uri 的查询串。
  /// 传入 [seed] 固定随机顺序，使随机相关断言可复现。
  ({FakePlayerEngine engine, PlaybackStateMachine machine}) build({int? seed}) {
    final engine = FakePlayerEngine();
    final machine = PlaybackStateMachine(
      engine,
      (id) => Uri.parse('http://nas.local:4533/rest/stream?id=$id&format=raw'),
      random: seed == null ? null : Random(seed),
    );
    return (engine: engine, machine: machine);
  }

  /// 让 [count] 首曲目逐个自然播完，返回依次播放的曲目 id。
  Future<List<String>> playThrough(
    PlaybackStateMachine machine,
    FakePlayerEngine engine,
    int count,
  ) async {
    final ids = <String>[machine.state.currentSong!.id];
    for (var i = 1; i < count; i++) {
      engine.complete();
      await pumpEventQueue();
      ids.add(machine.state.currentSong!.id);
    }
    return ids;
  }

  test('空队列：没有当前曲目，切歌不加载也不报错', () async {
    final (:engine, :machine) = build();

    expect(machine.state.queue, isEmpty);
    expect(machine.state.currentSong, isNull);

    await machine.next();
    await machine.previous();

    expect(engine.loadedIds, isEmpty);
  });

  test('playQueue：起点曲目成为当前曲目，队列为传入的上下文并开始播放', () async {
    final (:engine, :machine) = build();

    await machine.playQueue(songs(5), startIndex: 2);

    expect(machine.state.queue.map((s) => s.id), ['s0', 's1', 's2', 's3', 's4']);
    expect(machine.state.currentIndex, 2);
    expect(machine.state.currentSong?.id, 's2');
    expect(engine.loadedIds, ['s2']);
    expect(engine.playCount, 1);
  });

  test('循环关闭：一曲播完自动推进到下一首', () async {
    final (:engine, :machine) = build();
    await machine.playQueue(songs(3));

    engine.complete();
    await pumpEventQueue();

    expect(machine.state.currentSong?.id, 's1');
    expect(engine.loadedIds, ['s0', 's1']);
    expect(engine.playCount, 2);
  });

  test('循环关闭：最后一首播完停止，不回到第一首', () async {
    final (:engine, :machine) = build();
    await machine.playQueue(songs(3), startIndex: 2);

    engine.complete();
    await pumpEventQueue();

    expect(machine.state.currentSong?.id, 's2');
    expect(engine.loadedIds, ['s2']);
    expect(engine.playCount, 1);
  });

  test('全部循环：最后一首播完回到第一首', () async {
    final (:engine, :machine) = build();
    await machine.playQueue(songs(3), startIndex: 2);
    machine.setRepeatMode(RepeatMode.all);

    engine.complete();
    await pumpEventQueue();

    expect(machine.state.currentSong?.id, 's0');
    expect(engine.lastLoadedId, 's0');
    expect(engine.playCount, 2);
  });

  test('单曲循环：播完重播同一首，不推进索引也不重新加载', () async {
    final (:engine, :machine) = build();
    await machine.playQueue(songs(3), startIndex: 1);
    machine.setRepeatMode(RepeatMode.one);

    engine.complete();
    await pumpEventQueue();

    expect(machine.state.currentIndex, 1);
    expect(machine.state.currentSong?.id, 's1');
    expect(engine.loadedIds, ['s1']);
    expect(engine.seeks, [Duration.zero]);
    expect(engine.playCount, 2);
  });

  test('单曲队列：循环关闭播完停止；全部循环与单曲循环重播这一首', () async {
    final off = build();
    await off.machine.playQueue(songs(1));
    off.engine.complete();
    await pumpEventQueue();
    expect(off.machine.state.currentSong?.id, 's0');
    expect(off.engine.loadedIds, ['s0'], reason: '循环关闭时不应重新加载');

    final one = build();
    await one.machine.playQueue(songs(1));
    one.machine.setRepeatMode(RepeatMode.one);
    one.engine.complete();
    await pumpEventQueue();
    expect(one.engine.seeks, [Duration.zero]);
    expect(one.engine.playCount, 2);

    final all = build();
    await all.machine.playQueue(songs(1));
    all.machine.setRepeatMode(RepeatMode.all);
    all.engine.complete();
    await pumpEventQueue();
    expect(all.engine.loadedIds, ['s0', 's0']);
    expect(all.engine.playCount, 2);
  });

  test('手动切歌按队列顺序移动；到头且不循环时无操作', () async {
    final (:engine, :machine) = build();
    await machine.playQueue(songs(3), startIndex: 1);

    await machine.next();
    expect(machine.state.currentSong?.id, 's2');
    await machine.next(); // 已在末尾
    expect(machine.state.currentSong?.id, 's2');

    await machine.previous();
    expect(machine.state.currentSong?.id, 's1');
    await machine.previous();
    expect(machine.state.currentSong?.id, 's0');
    await machine.previous(); // 已在开头
    expect(machine.state.currentSong?.id, 's0');

    expect(engine.loadedIds, ['s1', 's2', 's1', 's0']);
    expect(engine.playCount, 4);
  });

  test('全部循环：手动下一首在末尾回到第一首，手动上一首在开头回到最后一首', () async {
    final (:engine, :machine) = build();
    await machine.playQueue(songs(3), startIndex: 2);
    machine.setRepeatMode(RepeatMode.all);

    await machine.next();
    expect(machine.state.currentSong?.id, 's0');

    await machine.previous();
    expect(machine.state.currentSong?.id, 's2');

    expect(engine.loadedIds, ['s2', 's0', 's2']);
  });

  test('单曲循环只改自动落点：手动切歌仍按顺序换歌', () async {
    final (:engine, :machine) = build();
    await machine.playQueue(songs(3), startIndex: 1);
    machine.setRepeatMode(RepeatMode.one);

    await machine.next();
    expect(machine.state.currentSong?.id, 's2');

    await machine.previous();
    expect(machine.state.currentSong?.id, 's1');
    expect(engine.seeks, isEmpty, reason: '手动切歌不应触发单曲重播');
  });

  test('play/pause 透传到引擎', () async {
    final (:engine, :machine) = build();

    await machine.pause();
    await machine.play();

    expect(engine.pauseCount, 1);
    expect(engine.playCount, 1);
  });

  test('队列状态变化推送到 stateStream', () async {
    final (:engine, :machine) = build();
    final seen = <String?>[];
    final subscription =
        machine.stateStream.listen((state) => seen.add(state.currentSong?.id));

    await machine.playQueue(songs(3));
    await machine.next();
    await pumpEventQueue();
    await subscription.cancel();

    expect(seen, ['s0', 's1']);
  });

  test('随机：起点是点击的那首，一轮内每首恰好一次；循环关闭时一轮走完停止', () async {
    final (:engine, :machine) = build(seed: 7);
    machine.setShuffle(true);
    await machine.playQueue(songs(8), startIndex: 0);

    final ids = await playThrough(machine, engine, 8);

    expect(ids.first, 's0');
    expect(ids, hasLength(8));
    expect(ids.toSet(), idSet(8));

    final loadedBefore = engine.loadedIds.length;
    engine.complete();
    await pumpEventQueue();
    expect(engine.loadedIds, hasLength(loadedBefore), reason: '一轮走完应停止，不重新加载');
    expect(machine.state.currentSong?.id, ids.last);
  });

  test('随机 + 全部循环：一轮结束后开新一轮，且不与上一首立刻重复', () async {
    final (:engine, :machine) = build(seed: 11);
    machine.setShuffle(true);
    machine.setRepeatMode(RepeatMode.all);
    await machine.playQueue(songs(4), startIndex: 0);

    final firstPass = await playThrough(machine, engine, 4);
    expect(firstPass.toSet(), hasLength(4));

    engine.complete();
    await pumpEventQueue();

    final secondPassFirst = machine.state.currentSong!.id;
    expect(idSet(4), contains(secondPassFirst));
    expect(secondPassFirst, isNot(firstPass.last));
  });

  test('随机关闭后回到自然序，并保持当前曲目', () async {
    final (:engine, :machine) = build(seed: 3);
    machine.setShuffle(true);
    await machine.playQueue(songs(4), startIndex: 2);
    expect(machine.state.currentSong?.id, 's2');

    machine.setShuffle(false);

    expect(machine.state.shuffle, isFalse);
    expect(machine.state.currentSong?.id, 's2');
    await machine.next();
    expect(machine.state.currentSong?.id, 's3');
    await machine.previous();
    expect(machine.state.currentSong?.id, 's2');
    await machine.previous();
    expect(machine.state.currentSong?.id, 's1');
  });

  test('随机下手动切歌与自动推进遵循同一份随机顺序', () async {
    final manual = build(seed: 5);
    manual.machine.setShuffle(true);
    await manual.machine.playQueue(songs(6), startIndex: 0);

    final auto = build(seed: 5);
    auto.machine.setShuffle(true);
    await auto.machine.playQueue(songs(6), startIndex: 0);

    final manualIds = <String>[manual.machine.state.currentSong!.id];
    for (var i = 1; i < 6; i++) {
      await manual.machine.next();
      manualIds.add(manual.machine.state.currentSong!.id);
    }
    final autoIds = await playThrough(auto.machine, auto.engine, 6);

    expect(manualIds, autoIds);
    expect(manualIds.toSet(), hasLength(6));
  });

  test('随机 + 循环关闭：一轮走完后手动切下一首无操作', () async {
    final (:engine, :machine) = build(seed: 9);
    machine.setShuffle(true);
    await machine.playQueue(songs(3), startIndex: 0);

    await machine.next();
    await machine.next();
    final last = machine.state.currentSong?.id;
    await machine.next();
    expect(machine.state.currentSong?.id, last);

    expect(engine.loadedIds, hasLength(3));
  });

  test('playQueue 空列表：清空当前曲目并暂停引擎', () async {
    final (:engine, :machine) = build();
    await machine.playQueue(songs(3));

    await machine.playQueue(const []);

    expect(machine.state.queue, isEmpty);
    expect(machine.state.currentSong, isNull);
    expect(machine.state.currentIndex, -1);
    expect(engine.pauseCount, 1);
  });

  test('起点下标越界时收敛到合法范围', () async {
    final (:engine, :machine) = build();

    await machine.playQueue(songs(3), startIndex: 99);

    expect(machine.state.currentIndex, 2);
    expect(engine.loadedIds, ['s2']);
  });

  test('引擎对同一曲目重复上报播完时只推进一首', () async {
    final (:engine, :machine) = build();
    await machine.playQueue(songs(3));

    engine.complete();
    engine.complete();
    await pumpEventQueue();

    expect(machine.state.currentSong?.id, 's1');
    expect(engine.loadedIds, ['s0', 's1']);
  });

  test('播放中途打开随机：当前曲目保留，其余排成随后的新的一轮', () async {
    final (:engine, :machine) = build(seed: 13);
    await machine.playQueue(songs(4), startIndex: 1);

    machine.setShuffle(true);

    expect(machine.state.currentSong?.id, 's1');
    final ids = <String>[machine.state.currentSong!.id];
    for (var i = 0; i < 3; i++) {
      await machine.next();
      ids.add(machine.state.currentSong!.id);
    }

    expect(ids.first, 's1');
    expect(ids.toSet(), idSet(4));
    expect(ids.sublist(1).toSet(), {'s0', 's2', 's3'});
  });

  test('dispose 释放引擎', () async {
    final (:engine, :machine) = build();
    await machine.playQueue(songs(1));

    await machine.dispose();

    expect(engine.disposed, isTrue);
  });
}
