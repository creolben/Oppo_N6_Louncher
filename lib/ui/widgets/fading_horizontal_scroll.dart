import 'package:flutter/material.dart';

/// Horizontal chip row that fades whichever edge still has content off-screen.
///
/// A scrollable row whose last chip is sliced in half by the panel edge reads
/// as a broken layout; the same row under an edge fade reads as scrollable.
/// When [center] is set and the chips fit, the row is centred so a short bar
/// does not look left-stuck.
class FadingHorizontalScroll extends StatefulWidget {
  const FadingHorizontalScroll({
    super.key,
    required this.children,
    this.fadeWidth = 36.0,
    this.fadeColor = const Color(0xFF020306),
    this.center = false,
  });

  final List<Widget> children;
  final double fadeWidth;

  /// Colour the edge fades resolve to. Must match the surface behind the row.
  final Color fadeColor;

  /// Centre the row when it is narrower than the viewport.
  final bool center;

  @override
  State<FadingHorizontalScroll> createState() => _FadingHorizontalScrollState();
}

class _FadingHorizontalScrollState extends State<FadingHorizontalScroll> {
  final ScrollController _controller = ScrollController();
  bool _leading = false;
  bool _trailing = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_sync);
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void dispose() {
    _controller.removeListener(_sync);
    _controller.dispose();
    super.dispose();
  }

  /// Overflow depends on layout, so it is re-checked after each frame and the
  /// fades are only rebuilt when the answer actually changes.
  void _sync() {
    if (!mounted || !_controller.hasClients) return;
    final leading = _controller.position.extentBefore > 2.0;
    final trailing = _controller.position.extentAfter > 2.0;
    if (leading != _leading || trailing != _trailing) {
      setState(() {
        _leading = leading;
        _trailing = trailing;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());

    return Stack(
      children: [
        LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            controller: _controller,
            scrollDirection: Axis.horizontal,
            physics: const ClampingScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: Row(
                mainAxisAlignment: widget.center
                    ? MainAxisAlignment.center
                    : MainAxisAlignment.start,
                children: widget.children,
              ),
            ),
          ),
        ),
        if (_leading) _edgeFade(Alignment.centerLeft),
        if (_trailing) _edgeFade(Alignment.centerRight),
      ],
    );
  }

  Widget _edgeFade(Alignment alignment) {
    final isLeading = alignment == Alignment.centerLeft;
    return Positioned(
      top: 0,
      bottom: 0,
      left: isLeading ? 0 : null,
      right: isLeading ? null : 0,
      width: widget.fadeWidth,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: isLeading ? Alignment.centerLeft : Alignment.centerRight,
              end: isLeading ? Alignment.centerRight : Alignment.centerLeft,
              colors: [
                widget.fadeColor,
                widget.fadeColor.withValues(alpha: 0.0),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
