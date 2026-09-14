/// 收藏目标的三种粒度。`star`/`unstar` 用不同的 id 参数区分它们。
enum StarKind { song, album, artist }

/// 一个收藏目标：粒度 + 服务端 id。
///
/// 用记录而非三选一的 id 参数：记录按值相等，界面可以拿它当互斥键与查找键，
/// 不必自己拼字符串。
typedef StarTarget = ({StarKind kind, String id});

StarTarget songStar(String id) => (kind: StarKind.song, id: id);
StarTarget albumStar(String id) => (kind: StarKind.album, id: id);
StarTarget artistStar(String id) => (kind: StarKind.artist, id: id);
