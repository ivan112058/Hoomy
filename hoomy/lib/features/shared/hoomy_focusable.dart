import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/platform/form_factor.dart';
import '../../core/theme/hoomy_theme.dart';

/// 「按下 / 聚焦」两态的高亮状态。
///
/// [highlighted] 是两者的并集：TV 上用聚焦替代按压反馈，两者共用同一套视觉 ——
/// 整块铺交互蓝、文字与图标变白（ADR-0013 决策 2）。[background] 与 [foreground]
/// 就是这套视觉的**唯一**落点，各处不要再手写同样的三元表达式。
///
/// 刻意**不含鼠标悬停**：ADR-0013 决策 2 的口径是「按下**或聚焦**」（Android TV
/// 没有指针，TV 语境里的「悬停反馈」由聚焦承担）。并入悬停会让手机／iPad 上
/// 指到一行就整行变蓝，那是手机形态里没有过的行为。
@immutable
class HoomyHighlight {
  const HoomyHighlight({required this.pressed, required this.focused});

  /// 手机形态的按压态。
  final bool pressed;

  /// TV 形态的焦点态（本节点自身拿到主焦点，不含后代）。
  final bool focused;

  /// 是否处于高亮：按下或聚焦任一成立。
  bool get highlighted => pressed || focused;

  /// 高亮时的整块底色；未高亮用 [normal]（默认透明）。
  Color background(HoomyPalette palette, [Color normal = Colors.transparent]) =>
      highlighted ? palette.pressedBackground : normal;

  /// 高亮时的前景（文字与图标）色；未高亮用 [normal]。
  Color foreground(HoomyPalette palette, Color normal) =>
      highlighted ? palette.pressedForeground : normal;
}

/// 队列重排的「左键 = 上移」意图（ADR-0013 决策 4）。
class HoomyMovePreviousIntent extends Intent {
  const HoomyMovePreviousIntent();
}

/// 队列重排的「右键 = 下移」意图（ADR-0013 决策 4）。
class HoomyMoveNextIntent extends Intent {
  const HoomyMoveNextIntent();
}

/// 「右键进入行内动作」意图：把焦点交给自身子树里的第一个可聚焦元素
/// （行尾收藏星标这类嵌在行内的动作）。
class HoomyEnterDescendantsIntent extends Intent {
  const HoomyEnterDescendantsIntent();
}

/// 上键改判意图（左侧导航栏首尾循环用）。
class HoomyMoveUpIntent extends Intent {
  const HoomyMoveUpIntent();
}

/// 下键改判意图（左侧导航栏首尾循环用）。
class HoomyMoveDownIntent extends Intent {
  const HoomyMoveDownIntent();
}

/// 把「可点元素」变成「可聚焦元素」的**唯一落点**。
///
/// D-pad 的方向键遍历、滚入视口由 Flutter 的 `Focus` 与遍历策略承担；本部件
/// 只负责三件事：
///
/// 1. 确认键（TV 遥控器中央键映射为 [LogicalKeyboardKey.select]）触发 [onTap]；
/// 2. 聚焦与悬停汇入 [HoomyHighlight]，供调用方画出与按压一致的反馈；
/// 3. 可选地把左右键改判为「上移 / 下移」（[onMovePrevious] / [onMoveNext]），
///    这是队列重排的 D-pad 路径，规则仍落在控制器上，界面不重复实现。
///
/// 刻意**不用** `InkWell`：它会自建焦点节点，聚焦落在它身上、外层拿不到
/// 「已聚焦」这一事实，就画不出「整块铺蓝」。但也因此不能直接用
/// `FocusableActionDetector` —— 它在方向导航模式下会把 `canRequestFocus`
/// 强制为真，无法把一个行排除出焦点序列（例如不可点的纯展示行）。
class HoomyFocusable extends StatefulWidget {
  const HoomyFocusable({
    super.key,
    required this.builder,
    this.onTap,
    this.onMovePrevious,
    this.onMoveNext,
    this.onMoveUp,
    this.onMoveDown,
    this.enterDescendantsOnRight = false,
    this.focusNode,
    this.autofocus = false,
  });

  /// 内容构建器，拿到当前高亮状态。
  final Widget Function(BuildContext context, HoomyHighlight highlight)
  builder;

  /// 点击 / 确认键回调；为 null 时本元素不进入焦点序列。
  final VoidCallback? onTap;

  /// 左键回调（队列里=上移）；为 null 时不改判左键。
  final VoidCallback? onMovePrevious;

  /// 右键回调（队列里=下移）；为 null 时不改判右键。
  final VoidCallback? onMoveNext;

  /// 上键回调；为 null 时不改判上键（走默认的方向遍历）。
  final VoidCallback? onMoveUp;

  /// 下键回调；为 null 时不改判下键（走默认的方向遍历）。
  final VoidCallback? onMoveDown;

  /// 外部提供的焦点节点。
  ///
  /// 左侧导航栏要在首尾之间循环，就得能**指名**把焦点交给另一项；所以首项与
  /// 「设置」的节点由导航栏自己持有并在此注入。提供时节点归调用方所有，本部件
  /// 不创建也不释放它；节点在整个生命周期内必须稳定（不做热替换）。
  final FocusNode? focusNode;

  /// 右键优先进入**自身子树里**的可聚焦元素（行尾收藏星标这类行内动作）。
  ///
  /// 方向导航只把「中心点在当前 rect 之外」的节点算作候选
  /// （`_sortAndFilterHorizontally`），而嵌在行内的星标永远落在行的 rect **之内**，
  /// 几何算法够不到它 —— 于是「行是可聚焦的」这件事反过来把星标挡在了外面。
  /// 这里显式改判一次右键，把焦点交给子树里的第一个可聚焦元素；
  /// 左键不必特殊处理：几何算法在反方向上能命中整行。
  ///
  /// [onMoveNext] 非空时以调用方语义（队列重排的「下移」）为准，本项不生效。
  final bool enterDescendantsOnRight;

  /// 是否在挂载时自动取得焦点。
  final bool autofocus;

  @override
  State<HoomyFocusable> createState() => _HoomyFocusableState();
}

class _HoomyFocusableState extends State<HoomyFocusable> {
  /// 与 Android pressed-state 时长一致：同帧完成的点击也至少可见一瞬。
  static const _minPressedDuration = Duration(milliseconds: 64);

  /// 自建节点；调用方注入了 [HoomyFocusable.focusNode] 时保持为 null。
  FocusNode? _createdNode;

  late final FocusNode _node =
      widget.focusNode ?? (_createdNode = FocusNode(debugLabel: 'HoomyFocusable'));

  bool _pressed = false;
  bool _focused = false;
  Timer? _releaseTimer;

  /// 是否可聚焦：有任意一个动作才进焦点序列。
  bool get _focusable =>
      widget.onTap != null ||
      widget.onMovePrevious != null ||
      widget.onMoveNext != null ||
      widget.onMoveUp != null ||
      widget.onMoveDown != null ||
      widget.enterDescendantsOnRight;

  @override
  void initState() {
    super.initState();
    // 只认**自身**的主焦点：后代（如行尾收藏星标）拿到焦点时，整行不该跟着
    // 铺蓝，否则嵌套的可点元素会互相点亮。
    _node.addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    _releaseTimer?.cancel();
    _node.removeListener(_handleFocusChange);
    // 注入了外部节点时归调用方释放。
    _createdNode?.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    final focused = _node.hasPrimaryFocus;
    if (focused != _focused) setState(() => _focused = focused);
  }

  void _handlePressStart() {
    _releaseTimer?.cancel();
    _releaseTimer = null;
    if (!_pressed) setState(() => _pressed = true);
  }

  void _handlePressEnd() {
    if (!_pressed) return;
    _releaseTimer?.cancel();
    _releaseTimer = Timer(_minPressedDuration, () {
      if (mounted) setState(() => _pressed = false);
    });
  }

  void _activate() => widget.onTap?.call();

  /// 把焦点交给子树里的第一个可聚焦元素；没有就什么都不做。
  void _focusFirstDescendant() {
    for (final node in _node.traversalDescendants) {
      node.requestFocus();
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final onMovePrevious = widget.onMovePrevious;
    final onMoveNext = widget.onMoveNext;
    final onMoveUp = widget.onMoveUp;
    final onMoveDown = widget.onMoveDown;
    // 队列重排占用了右键；只有在没人认领右键时才做「进入行内动作」。
    final enterDescendants =
        widget.enterDescendantsOnRight && onMoveNext == null;
    final shortcuts = <ShortcutActivator, Intent>{
      if (onMovePrevious != null)
        const SingleActivator(LogicalKeyboardKey.arrowLeft):
            const HoomyMovePreviousIntent(),
      if (onMoveNext != null)
        const SingleActivator(LogicalKeyboardKey.arrowRight):
            const HoomyMoveNextIntent()
      else if (enterDescendants)
        const SingleActivator(LogicalKeyboardKey.arrowRight):
            const HoomyEnterDescendantsIntent(),
      if (onMoveUp != null)
        const SingleActivator(LogicalKeyboardKey.arrowUp):
            const HoomyMoveUpIntent(),
      if (onMoveDown != null)
        const SingleActivator(LogicalKeyboardKey.arrowDown):
            const HoomyMoveDownIntent(),
    };
    final actions = <Type, Action<Intent>>{
      // 只在真的有动作时接确认键：否则纯展示行会「吃掉」确认键，
      // 盖住后代（例如行尾收藏星标）自己的动作。
      if (widget.onTap != null)
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            _activate();
            return null;
          },
        ),
      if (onMovePrevious != null)
        HoomyMovePreviousIntent: CallbackAction<HoomyMovePreviousIntent>(
          onInvoke: (_) {
            onMovePrevious();
            return null;
          },
        ),
      if (onMoveNext != null)
        HoomyMoveNextIntent: CallbackAction<HoomyMoveNextIntent>(
          onInvoke: (_) {
            onMoveNext();
            return null;
          },
        ),
      if (enterDescendants)
        HoomyEnterDescendantsIntent: CallbackAction<HoomyEnterDescendantsIntent>(
          onInvoke: (_) {
            _focusFirstDescendant();
            return null;
          },
        ),
      if (onMoveUp != null)
        HoomyMoveUpIntent: CallbackAction<HoomyMoveUpIntent>(
          onInvoke: (_) {
            onMoveUp();
            return null;
          },
        ),
      if (onMoveDown != null)
        HoomyMoveDownIntent: CallbackAction<HoomyMoveDownIntent>(
          onInvoke: (_) {
            onMoveDown();
            return null;
          },
        ),
    };

    Widget child = Focus(
      focusNode: _node,
      autofocus: widget.autofocus,
      canRequestFocus: _focusable,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // 用 tap 回调而不是 Listener：列表滚动时拖拽手势胜出会触发
        // onTapCancel，行不会在整段滑动里一直保持蓝色。
        onTapDown: (_) => _handlePressStart(),
        onTapUp: (_) => _handlePressEnd(),
        onTapCancel: _handlePressEnd,
        onTap: widget.onTap,
        child: widget.builder(
          context,
          HoomyHighlight(pressed: _pressed, focused: _focused),
        ),
      ),
    );
    child = Actions(actions: actions, child: child);
    if (shortcuts.isNotEmpty) {
      child = Shortcuts(shortcuts: shortcuts, child: child);
    }
    return child;
  }
}

/// 让 D-pad 的上下键能**离开**输入框（TV 上必办）。
///
/// 文本框会吞掉上下键（`DoNothingAndStopPropagationTextIntent`），否则焦点一旦
/// 进到搜索框或登录表单就再也出不来，「登录」按钮与曲目列表都够不到。这里把
/// 上下键改判成不忽略文本框的方向遍历意图（`ignoreTextFields: false`），
/// `EditableText` 自己的动作就会把焦点交给相邻控件。左右键仍留给光标。
///
/// 只在 TV 形态下生效：手机形态不需要键盘导航，保持系统默认行为。
class HoomyTextFieldEscape extends StatelessWidget {
  const HoomyTextFieldEscape({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!HoomyFormFactorScope.isTv(context)) return child;
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.arrowDown): DirectionalFocusIntent(
          TraversalDirection.down,
          ignoreTextFields: false,
        ),
        SingleActivator(LogicalKeyboardKey.arrowUp): DirectionalFocusIntent(
          TraversalDirection.up,
          ignoreTextFields: false,
        ),
      },
      child: child,
    );
  }
}
