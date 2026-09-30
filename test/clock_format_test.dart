import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mylauncher/ui/format/clock_format.dart';

/// The shared clock helper is what keeps all four ChronoFold surfaces in
/// agreement with the platform's own 12/24-hour setting. Both formats are
/// pinned by setting `alwaysUse24HourFormat` explicitly: the test host's
/// ambient value defaults to 12-hour (the engine's PlatformConfiguration
/// starts `alwaysUse24HourFormat` at false), so a test that relied on the
/// ambient value would only ever exercise half the helper.
Future<String> formatUnder(
  WidgetTester tester, {
  required bool use24Hour,
  required DateTime time,
}) async {
  String? formatted;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            alwaysUse24HourFormat: use24Hour,
          ),
          child: Builder(
            builder: (context) {
              formatted = formatClockTime(context, time);
              return const SizedBox();
            },
          ),
        ),
      ),
    ),
  );
  return formatted!;
}

void main() {
  testWidgets('a 24-hour device keeps the zero-padded HH:MM', (tester) async {
    // The format the four surfaces hardcoded before the helper existed, so
    // a 24-hour device renders exactly what it always did.
    expect(
      await formatUnder(
        tester,
        use24Hour: true,
        time: DateTime(2025, 1, 1, 19, 5),
      ),
      equals('19:05'),
    );
    expect(
      await formatUnder(
        tester,
        use24Hour: true,
        time: DateTime(2025, 1, 1, 0, 0),
      ),
      equals('00:00'),
    );
    expect(
      await formatUnder(
        tester,
        use24Hour: true,
        time: DateTime(2025, 1, 1, 9, 59),
      ),
      equals('09:59'),
    );
  });

  testWidgets(
    'a 12-hour device uses h:MM and the locale day period', (tester) async {
    // No leading zero on the hour, zero-padded minute, AM/PM appended —
    // what the ColorOS status bar shows for the same setting, so the
    // launcher's clocks stop disagreeing with the OEM clock next to them.
    expect(
      await formatUnder(
        tester,
        use24Hour: false,
        time: DateTime(2025, 1, 1, 19, 5),
      ),
      equals('7:05 PM'),
    );
    expect(
      await formatUnder(
        tester,
        use24Hour: false,
        time: DateTime(2025, 1, 1, 0, 5),
      ),
      equals('12:05 AM'),
    );
    expect(
      await formatUnder(
        tester,
        use24Hour: false,
        time: DateTime(2025, 1, 1, 12, 5),
      ),
      equals('12:05 PM'),
    );
    expect(
      await formatUnder(
        tester,
        use24Hour: false,
        time: DateTime(2025, 1, 1, 23, 0),
      ),
      equals('11:00 PM'),
    );
  });
}