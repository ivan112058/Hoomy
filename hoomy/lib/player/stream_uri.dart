/// 由曲目 id 得到可播放的音频地址。
///
/// 生产由**会话**提供（`Session.streamUri`，`stream` 端点含 `format=raw` 与
/// `u`/`t`/`s` 认证查询串）。把它单独放在这里，是为了让播放状态机与协议层
/// 互不引用：状态机只知道「给我一个 id，还我一个地址」。
typedef StreamUriResolver = Uri Function(String songId);
