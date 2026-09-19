import 'package:flutter/material.dart';

import '../../models/web_search.dart';

/// A run of answer text, or a citation marker pointing at a [SearchSource].
///
/// Modelling citations as segments rather than letting the widget hand-roll
/// string splitting is what makes them tappable and testable. A streaming
/// answer can end mid-marker — `"...as reported [1"` — and the parser below is
/// what stops that from rendering as broken text.
sealed class AnswerSegment {
  const AnswerSegment();
}

class AnswerText extends AnswerSegment {
  final String text;
  const AnswerText(this.text);
}

class AnswerCitation extends AnswerSegment {
  /// The 1-based source number, matching [SearchSource.index].
  final int number;
  const AnswerCitation(this.number);
}

/// Parses `[1]` style markers out of answer prose.
///
/// Pure and static so the streaming behaviour can be tested without a widget
/// tree. Unmatched markers (no corresponding source) are left as literal text
/// rather than rendered as dead links — a citation that goes nowhere is worse
/// than no citation.
List<AnswerSegment> parseAnswerSegments(
  String answer,
  List<SearchSource> sources,
) {
  if (answer.isEmpty) return const [];

  final valid = sources.map((s) => s.index).toSet();
  final segments = <AnswerSegment>[];
  final buffer = StringBuffer();

  // Matches a complete [n] marker. A partially streamed marker like "[1" has no
  // closing bracket and so is deliberately left in the text buffer, where it
  // renders as harmless prose until the next chunk completes it.
  final marker = RegExp(r'\[(\d{1,2})\]');

  var cursor = 0;
  for (final match in marker.allMatches(answer)) {
    final number = int.tryParse(match.group(1) ?? '');
    if (number == null || !valid.contains(number)) continue;

    if (match.start > cursor) {
      buffer.write(answer.substring(cursor, match.start));
    }
    if (buffer.isNotEmpty) {
      segments.add(AnswerText(buffer.toString()));
      buffer.clear();
    }
    segments.add(AnswerCitation(number));
    cursor = match.end;
  }

  if (cursor < answer.length) {
    buffer.write(answer.substring(cursor));
  }
  if (buffer.isNotEmpty) {
    segments.add(AnswerText(buffer.toString()));
  }

  return segments;
}

/// Renders answer prose with inline, tappable citation markers.
class AnswerBody extends StatelessWidget {
  final String answer;
  final List<SearchSource> sources;
  final ValueChanged<SearchSource>? onCitationTap;

  const AnswerBody({
    super.key,
    required this.answer,
    required this.sources,
    this.onCitationTap,
  });

  @override
  Widget build(BuildContext context) {
    final segments = parseAnswerSegments(answer, sources);

    return RichText(
      // Raw RichText defaults to no scaling, so answer prose ignored the
      // system text size while every Text around it grew.
      textScaler: MediaQuery.textScalerOf(context),
      text: TextSpan(
        style: const TextStyle(
          color: Color(0xFFE8ECF5),
          fontSize: 14.5,
          height: 1.55,
          letterSpacing: 0.1,
        ),
        children: segments.map((segment) {
          switch (segment) {
            case AnswerText(:final text):
              return TextSpan(text: text);
            case AnswerCitation(:final number):
              final source = sources.firstWhere((s) => s.index == number);
              return WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: _CitationMarker(
                  number: number,
                  onTap: onCitationTap == null
                      ? null
                      : () => onCitationTap!(source),
                ),
              );
          }
        }).toList(),
      ),
    );
  }
}

class _CitationMarker extends StatelessWidget {
  final int number;
  final VoidCallback? onTap;

  const _CitationMarker({required this.number, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2.0),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: const Color(0xFFFFB300).withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: const Color(0xFFFFB300).withValues(alpha: 0.45),
                width: 0.9,
              ),
            ),
            child: Text(
              '$number',
              style: const TextStyle(
                color: Color(0xFFFFC64D),
                fontSize: 10.5,
                fontWeight: FontWeight.bold,
                height: 1.3,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
