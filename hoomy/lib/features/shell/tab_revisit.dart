/// 一级导航「切回即失效」的判定（票据 05）。
///
/// 「Tab」在这里指两端的一级导航项：手机上是底部 Tab，TV 上是侧边导航栏的一格
///（术语表只把「底部 Tab」限定给 iOS，此处不作导航结构解）。
///
/// 只回答一件事：某个 Tab **刚被展示**时，这算不算「切回」—— 调用方据此决定
/// 要不要使它的取数失效并重取。
///
/// - **首次展示不算**：冷启动进入的 Tab 只取一次，切到一个没看过的 Tab 也不重取。
/// - **从别的 Tab 回到曾经展示过的 Tab 才算**：这正是「切走再切回」。
///
/// 「展示」跟着**内容切换**走（ADR-0013 的聚焦即切换：焦点停在哪个 Tab，右侧就
/// 展示哪个），不跟确认键走 —— 否则用户焦点停在「我喜欢的歌曲」上看到的仍是旧数据。
/// dwell 由调用方保证：TV 上焦点停住 ≈250ms 才来问本类（快速扫过不算切回，否则
/// 扫一遍导航栏会打出一串请求）；手机外壳没有焦点预览，底部 Tab 索引一变就算展示过。
class TabRevisit {
  TabRevisit(int showingIndex) : _showing = showingIndex, _seen = {showingIndex};

  /// 当前展示的 Tab。
  int _showing;

  /// 曾经展示过的 Tab；首次展示不失效，靠它区分。
  final Set<int> _seen;

  /// [index] 刚被展示：返回 true 表示这是「切回」，调用方应使它失效。
  bool show(int index) {
    if (index == _showing) return false;
    final revisited = _seen.contains(index);
    _seen.add(index);
    _showing = index;
    return revisited;
  }
}
