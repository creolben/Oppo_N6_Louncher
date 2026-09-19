import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/launcher_bridge.dart';
import '../../core/search_coordinator.dart';
import '../../models/web_search.dart';
import 'answer_body.dart';
import 'comet_orb.dart';

/// The comet web-search surface.
///
/// Deliberately a sibling of `SearchOverlay`, not a variant of it: same scrim,
/// same 50px capsule, same 25px radius, same blur sigma — so muscle memory
/// transfers — but amber instead of cyan, and an answer panel app search never
/// has. The shared silhouette is what makes this feel native rather than
/// bolted on.
class CometSearchSurface extends StatefulWidget {
  final SearchCoordinator coordinator;
  final VoidCallback onClose;

  /// Optional initial query, used by the app-search empty state to escalate a
  /// query the user already typed rather than making them retype it.
  final String? initialQuery;

  const CometSearchSurface({
    super.key,
    required this.coordinator,
    required this.onClose,
    this.initialQuery,
  });

  @override
  State<CometSearchSurface> createState() => _CometSearchSurfaceState();
}

class _CometSearchSurfaceState extends State<CometSearchSurface> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();

  /// Probed once: whether the platform raises a chooser for ACTION_WEB_SEARCH.
  /// Drives honest labelling of the handoff button.
  WebSearchHandoff _handoff = const WebSearchHandoff.unknown();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialQuery ?? '');
    _probeHandoff();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
      if ((widget.initialQuery ?? '').trim().isNotEmpty) {
        widget.coordinator.search(widget.initialQuery!);
      }
    });
  }

  Future<void> _probeHandoff() async {
    final handoff = await LauncherBridge.describeWebSearchHandoff();
    if (!mounted) return;
    setState(() => _handoff = handoff);
  }

  @override
  void dispose() {
    // The coordinator outlives this surface (it belongs to the home screen), so
    // it is not disposed here — but the search THIS surface started must not
    // keep streaming into a torn-down tree. Without this, dismissing the
    // palette mid-answer leaks a timer and a subscription.
    widget.coordinator.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit(String value) {
    final query = value.trim();
    if (query.isEmpty) return;
    HapticFeedback.lightImpact();
    FocusScope.of(context).unfocus();
    widget.coordinator.search(query);
  }

  void _openSource(SearchSource source) {
    HapticFeedback.selectionClick();
    widget.coordinator.openSource(source);
  }

  @override
  Widget build(BuildContext context) {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 20.0, sigmaY: 20.0),
      child: Container(
        color: CometPalette.scrim,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildCapsule(),
              Expanded(
                child: AnimatedBuilder(
                  animation: widget.coordinator,
                  builder: (context, _) => _buildBody(widget.coordinator.result),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCapsule() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16.0, 12.0, 16.0, 8.0),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 50,
              decoration: BoxDecoration(
                color: CometPalette.glass.withValues(alpha: 0.90),
                borderRadius: BorderRadius.circular(25),
                border: Border.all(
                  color: CometPalette.borderCool.withValues(alpha: 0.30),
                  width: 1.2,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x33FFB300),
                    blurRadius: 18,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Row(
                children: [
                  const Padding(
                    padding: EdgeInsets.only(left: 14.0, right: 10.0),
                    child: CometOrb(size: 22, isActive: true),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      textInputAction: TextInputAction.search,
                      onSubmitted: _submit,
                      onChanged: (_) => setState(() {}),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        letterSpacing: 0.4,
                      ),
                      cursorColor: CometPalette.amber,
                      decoration: InputDecoration(
                        hintText: 'Search the cosmos...',
                        hintStyle: TextStyle(
                          color: Colors.white.withValues(alpha: 0.42),
                          fontSize: 14,
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  if (_controller.text.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.clear_rounded, color: Colors.white70, size: 20),
                      tooltip: 'Clear',
                      onPressed: () {
                        _controller.clear();
                        widget.coordinator.reset();
                        setState(() {});
                      },
                    ),
                  Padding(
                    padding: const EdgeInsets.only(right: 6.0),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => _submit(_controller.text),
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: CometPalette.amber.withValues(alpha: 0.16),
                            border: Border.all(
                              color: CometPalette.amber.withValues(alpha: 0.55),
                            ),
                          ),
                          child: const Icon(
                            Icons.arrow_upward_rounded,
                            color: CometPalette.amber,
                            size: 18,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.white, size: 26),
            tooltip: 'Close',
            onPressed: widget.onClose,
          ),
        ],
      ),
    );
  }

  Widget _buildBody(SearchResult result) {
    switch (result.phase) {
      case SearchPhase.idle:
        return _buildIdle();
      case SearchPhase.searching:
        return _buildFlight(result);
      case SearchPhase.streaming:
      case SearchPhase.complete:
        return _buildAnswer(result);
      case SearchPhase.needsKey:
      case SearchPhase.unavailable:
      case SearchPhase.failed:
        return _buildFallback(result);
    }
  }

  Widget _buildIdle() {
    // The idle state teaches the affordance rather than sitting empty, and
    // states the mode honestly when nothing but the handoff is wired up.
    final handoffOnly = widget.coordinator.isHandoffOnly;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CometOrb(size: 64),
            const SizedBox(height: 22),
            const Text(
              'Ask the cosmos',
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              handoffOnly
                  ? 'Type a question to send it to your search app.'
                  : 'Type a question to get an answer with sources.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.48),
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFlight(SearchResult result) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        Row(
          children: [
            const CometOrb(size: 18),
            const SizedBox(width: 10),
            Text(
              'Crossing the void...',
              style: TextStyle(
                color: CometPalette.amber.withValues(alpha: 0.85),
                fontSize: 12.5,
                letterSpacing: 0.7,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _ShimmerLine(widthFactor: 1.0),
        const SizedBox(height: 10),
        _ShimmerLine(widthFactor: 0.92),
        const SizedBox(height: 10),
        _ShimmerLine(widthFactor: 0.64),
      ],
    );
  }

  Widget _buildAnswer(SearchResult result) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        _AnswerPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const CometOrb(size: 16),
                  const SizedBox(width: 8),
                  Text(
                    result.providerName.toUpperCase(),
                    style: TextStyle(
                      color: CometPalette.amber.withValues(alpha: 0.80),
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const Spacer(),
                  if (result.phase == SearchPhase.streaming)
                    Text(
                      'streaming',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.32),
                        fontSize: 10.5,
                        letterSpacing: 0.8,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              AnswerBody(
                answer: result.answer,
                sources: result.sources,
                onCitationTap: _openSource,
              ),
            ],
          ),
        ),
        if (result.sources.isNotEmpty) ...[
          const SizedBox(height: 18),
          Text(
            result.sources.length == 1 ? 'SOURCE' : 'SOURCES',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.34),
              fontSize: 10.5,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.3,
            ),
          ),
          const SizedBox(height: 10),
          ...result.sources.map(
            (source) => _SourceCard(
              source: source,
              onTap: () => _openSource(source),
            ),
          ),
        ],
        const SizedBox(height: 20),
        _buildHandoffRow(result.query),
      ],
    );
  }

  Widget _buildFallback(SearchResult result) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        _AnswerPanel(
          accent: Colors.white24,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    result.phase == SearchPhase.failed
                        ? Icons.error_outline_rounded
                        : Icons.key_off_rounded,
                    color: Colors.white.withValues(alpha: 0.55),
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      result.phase == SearchPhase.failed
                          ? 'Transmission failed'
                          : result.phase == SearchPhase.needsKey
                              ? 'Inline answers are not connected'
                              : 'No inline search provider',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                result.errorMessage ??
                    'Nothing is configured to answer inline yet.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.52),
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _buildHandoffRow(result.query),
      ],
    );
  }

  /// The escape hatch. Label copy is derived from the live probe, so the button
  /// never promises a silent launch on a device that will raise a chooser.
  Widget _buildHandoffRow(String query) {
    final raisesChooser = _handoff.isKnown && _handoff.raisesChooser;
    final label = raisesChooser
        ? 'Choose a search app'
        : 'Open in search app';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: query.trim().isEmpty
                ? null
                : () {
                    HapticFeedback.lightImpact();
                    widget.coordinator.openViaHandoff(query);
                  },
            icon: const Icon(Icons.travel_explore_rounded, size: 18),
            label: Text(label),
            style: OutlinedButton.styleFrom(
              foregroundColor: CometPalette.amber,
              side: BorderSide(
                color: CometPalette.amber.withValues(alpha: 0.45),
              ),
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
        if (raisesChooser && _handoff.handlerCount > 1) ...[
          const SizedBox(height: 8),
          Text(
            '${_handoff.handlerCount} apps can handle this and none is set as '
            'the default, so Android will ask which to use.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.34),
              fontSize: 11.5,
              height: 1.45,
            ),
          ),
        ],
      ],
    );
  }
}

class _AnswerPanel extends StatelessWidget {
  final Widget child;
  final Color accent;

  const _AnswerPanel({required this.child, this.accent = CometPalette.amber});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: CometPalette.panel.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.28), width: 1.1),
        boxShadow: const [
          BoxShadow(color: Color(0x1AFFB300), blurRadius: 22, spreadRadius: 1),
        ],
      ),
      child: child,
    );
  }
}

class _SourceCard extends StatelessWidget {
  final SearchSource source;
  final VoidCallback onTap;

  const _SourceCard({required this.source, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: CometPalette.nodeFill.withValues(alpha: 0.75),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: CometPalette.amber.withValues(alpha: 0.20),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: CometPalette.amber.withValues(alpha: 0.16),
                  ),
                  child: Text(
                    '${source.index}',
                    style: const TextStyle(
                      color: CometPalette.amber,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        source.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        source.displayDomain,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.40),
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.north_east_rounded,
                  size: 15,
                  color: Colors.white.withValues(alpha: 0.35),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ShimmerLine extends StatefulWidget {
  final double widthFactor;

  const _ShimmerLine({required this.widthFactor});

  @override
  State<_ShimmerLine> createState() => _ShimmerLineState();
}

class _ShimmerLineState extends State<_ShimmerLine>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        // A travelling highlight reads as "working" far better than a static
        // grey block, and costs one gradient per line.
        final t = reduceMotion ? 0.5 : _controller.value;
        return FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: widget.widthFactor,
          child: Container(
            height: 11,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              gradient: LinearGradient(
                begin: Alignment(-1.0 + t * 2, 0),
                end: Alignment(1.0 + t * 2, 0),
                colors: [
                  Colors.white.withValues(alpha: 0.05),
                  CometPalette.amber.withValues(alpha: 0.16),
                  Colors.white.withValues(alpha: 0.05),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
