import 'dart:async';

import 'package:just_audio/just_audio.dart';

import 'player_engine.dart';

/// [PlayerEngine] 的默认实现：内核是 `just_audio`（ADR-0010）。
///
/// 职责边界：本类只把 `just_audio` 的 `Player` 翻译成 [PlayerEngine] 的
/// 能力与流，不含队列、循环、随机等业务规则（那些在 `PlaybackStateMachine`）。
/// `just_audio` 的 `Player` 不出现在本文件之外。
///
/// **认证走 URL 查询串**（Subsonic 原生方式），因此 [load] 不传 `headers`：
/// `stream` 地址由 `SubsonicClient.streamUri` 生成，已带 `format=raw` 与
/// `u`/`t`/`s` 认证参数（ADR-0001 / ADR-0010）。
///
/// 错误一律经 [errorStream] 上报，不抛出：调用方是状态机，它没有呈现错误的位置。
class JustAudioPlayerEngine implements PlayerEngine {
  /// 构造即开始转发内核事件（订阅只在这里建立一次，重复构造不会重复订阅）。
  JustAudioPlayerEngine({AudioPlayer? player})
    : _player = player ?? AudioPlayer() {
    _playerStateSub = _player.playerStateStream.listen(_onPlayerState);
    _durationSub = _player.durationStream.listen((Duration? d) {
      _duration = d;
      _emit(_player.playerState);
    });
    _playerErrorSub = _player.errorStream.listen(_emitError);
  }

  final AudioPlayer _player;

  /// 位置转发：`just_audio` 已在暂停时不推进位置，无需额外过滤。
  late final Stream<Duration> _position = _player.positionStream;

  final _state = StreamController<PlayerEngineState>.broadcast(sync: true);
  final _completion = StreamController<void>.broadcast(sync: true);
  final _errors = StreamController<PlayerEngineError>.broadcast(sync: true);

  late final StreamSubscription<PlayerState> _playerStateSub;
  late final StreamSubscription<PlayerException> _playerErrorSub;
  late final StreamSubscription<Duration?> _durationSub;

  /// 最近一次已知时长：`just_audio` 的时长流会随加载更新，而播放状态里要带上它。
  Duration? _duration;
  bool _disposed = false;

  /// 从「已播完」重新开始时必须先回到起点：`completed` 状态下
  /// `just_audio` 的 `play()` 是空操作，不 seek 就会一直停在结尾。
  bool _completed = false;

  @override
  Stream<Duration> get positionStream => _position;

  @override
  Stream<PlayerEngineState> get stateStream => _state.stream;

  @override
  Stream<void> get completionStream => _completion.stream;

  @override
  Stream<PlayerEngineError> get errorStream => _errors.stream;

  void _onPlayerState(PlayerState state) {
    if (state.processingState == ProcessingState.completed && !_completed) {
      _completed = true;
      // 先发状态（界面能立刻看到「已播完」），再发事件（状态机据此推进队列）。
      // `just_audio` 在 completed 时 `playing` 仍为 true（它没有「停止」态），
      // 这里以 `playing: false` 呈现「已经没在出声了」。
      _emit(state, playingOverride: false);
      if (!_completion.isClosed) _completion.add(null);
      return;
    }
    if (state.processingState != ProcessingState.completed) _completed = false;
    _emit(state);
  }

  void _emit(PlayerState state, {bool? playingOverride}) {
    if (_state.isClosed) return;
    _state.add(
      PlayerEngineState(
        playing: playingOverride ?? state.playing,
        status: _statusOf(state.processingState),
        duration: _duration,
      ),
    );
  }

  PlayerEngineStatus _statusOf(ProcessingState processing) =>
      switch (processing) {
        ProcessingState.idle => PlayerEngineStatus.idle,
        ProcessingState.loading ||
        ProcessingState.buffering => PlayerEngineStatus.loading,
        ProcessingState.ready => PlayerEngineStatus.ready,
        ProcessingState.completed => PlayerEngineStatus.completed,
      };

  @override
  Future<void> load(Uri uri) async {
    if (_disposed) return;
    _completed = false;
    _duration = null;
    _emit(PlayerState(false, ProcessingState.loading));
    try {
      // 不传 headers：认证在 URL 查询串里（ADR-0010）。
      //
      // 显式用 ProgressiveAudioSource + `preferPreciseDurationAndTiming`：
      // iOS 的 AVFoundation 默认按估算做「时间 ↔ 字节」映射，VBR FLAC 上
      // 会让 seek 落在目标之前 5–30 秒（just_audio #440，ADR-0010 记录的
      // FLAC 风险）。该开关映射为 `AVURLAssetPreferPreciseDurationAndTimingKey`，
      // 要求按文件真实时间轴解析，代价是加载时多读一点索引。Android 侧忽略
      // 这个 Darwin 选项，行为不变。
      await _player.setAudioSource(
        ProgressiveAudioSource(
          uri,
          options: const ProgressiveAudioSourceOptions(
            darwinAssetOptions: DarwinAssetOptions(
              preferPreciseDurationAndTiming: true,
            ),
          ),
        ),
      );
    } on PlayerException catch (e) {
      _emitError(e);
    } on PlayerInterruptedException {
      // 连续换歌时旧的加载请求被打断，属于正常流程，不是播放失败。
    } catch (e) {
      _emitErrorText(e);
    }
  }

  @override
  Future<void> play() async {
    if (_disposed) return;
    if (_completed) {
      _completed = false;
      await _player.seek(Duration.zero);
    }
    try {
      await _player.play();
    } on PlayerException catch (e) {
      _emitError(e);
    } on PlayerInterruptedException {
      // 被下一次操作打断：正常流程。
    } catch (e) {
      _emitErrorText(e);
    }
  }

  @override
  Future<void> pause() async {
    if (_disposed) return;
    try {
      await _player.pause();
    } on PlayerInterruptedException {
      // 正常流程。
    } catch (e) {
      _emitErrorText(e);
    }
  }

  @override
  Future<void> seek(Duration position) async {
    if (_disposed) return;
    _completed = false;
    try {
      await _player.seek(position);
    } on PlayerException catch (e) {
      _emitError(e);
    } on PlayerInterruptedException {
      // 正常流程。
    } catch (e) {
      _emitErrorText(e);
    }
  }

  @override
  Future<void> setVolume(double volume) async {
    if (_disposed) return;
    try {
      await _player.setVolume(volume);
    } on PlayerException catch (e) {
      _emitError(e);
    } catch (e) {
      _emitErrorText(e);
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _playerStateSub.cancel();
    await _durationSub.cancel();
    await _playerErrorSub.cancel();
    await _player.dispose();
    await _state.close();
    await _completion.close();
    await _errors.close();
  }

  /// 把内核异常翻译成用户能读懂的文案；原始描述留在 [PlayerEngineError.detail]。
  ///
  /// [`code`] 的含义随平台而异：iOS/macOS 是 `NSError.code`，Android 是
  /// `ExoPlaybackException.type`，Web 是 `MediaError.code`（见 just_audio 文档），
  /// 因此只对两边都稳定的 0–4 给出具体文案，其余退回通用文案。
  void _emitError(PlayerException e) {
    final detail = e.toString();
    final text = switch (e.code) {
      0 => '播放失败，可能是不支持的音频格式或文件已损坏',
      1 => '无法连接到服务器',
      2 => '服务器返回了无效的音频数据',
      3 || 4 => '音频解码失败',
      _ => '播放失败',
    };
    _reportError(PlayerEngineError(text, detail: detail));
  }

  void _emitErrorText(Object e) =>
      _reportError(PlayerEngineError('播放失败', detail: e.toString()));

  /// 上报一次错误。与 `_emit` 一样守住已关闭的流：dispose 之后迟到的内核事件
  /// 不能再往里写。
  void _reportError(PlayerEngineError error) {
    if (_errors.isClosed) return;
    _errors.add(error);
  }
}
