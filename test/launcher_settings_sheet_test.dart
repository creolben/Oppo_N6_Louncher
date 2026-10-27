import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mylauncher/main.dart';
import 'package:mylauncher/ui/widgets/launcher_settings_sheet.dart';

/// Mounts the sheet the way `showLauncherSettingsSheet` does, minus the route,
/// so layout and interaction can be checked directly.
Widget _host({
  required ValueNotifier<bool> isDefault,
  bool nativeMode = false,
  Future<void> Function(bool)? onLockModeChanged,
  VoidCallback? onDefaultHomeTap,
  VoidCallback? onOpenAmbientWallpaper,
  VoidCallback? onOpenGestures,
  double textScale = 1.0,
}) {
  return MaterialApp(
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(
          body: LauncherSettingsSheet(
            isDefaultLauncher: isDefault,
            onDefaultHomeTap: onDefaultHomeTap ?? () {},
            nativeLockMode: nativeMode,
            onLockModeChanged: onLockModeChanged ?? (_) async {},
            onOpenAmbientWallpaper: onOpenAmbientWallpaper ?? () {},
            onOpenGestures: onOpenGestures ?? () {},
          ),
        ),
      ),
    ),
  );
}

void _setSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('renders every section with plain-language rows',
      (tester) async {
    _setSize(tester, const Size(400, 1400));
    final isDefault = ValueNotifier<bool>(true);
    addTearDown(isDefault.dispose);

    await tester.pumpWidget(_host(isDefault: isDefault));

    expect(find.text('Settings'), findsOneWidget);
    for (final section in ['Home', 'Appearance', 'Lock screen', 'About']) {
      expect(find.text(section), findsOneWidget, reason: section);
    }
    // "Gestures" is both the section overline and the row title.
    expect(find.text('Gestures'), findsNWidgets(2));
    expect(find.text('Default home app'), findsOneWidget);
    expect(find.text('Ambient wallpaper'), findsOneWidget);
    expect(find.text('Cosmic'), findsOneWidget);
    expect(find.text('ColorOS'), findsOneWidget);
    expect(find.text('ChronoFold'), findsOneWidget);
  });

  testWidgets('default-home row reflects and follows the live status',
      (tester) async {
    _setSize(tester, const Size(400, 1400));
    final isDefault = ValueNotifier<bool>(false);
    addTearDown(isDefault.dispose);
    var taps = 0;

    await tester.pumpWidget(
      _host(isDefault: isDefault, onDefaultHomeTap: () => taps++),
    );

    expect(find.text('Set as default'), findsOneWidget);
    expect(find.text('ChronoFold is your home app'), findsNothing);

    await tester.tap(find.text('Default home app'));
    await tester.pump();
    expect(taps, 1);

    // The resume re-check flips the notifier while the sheet is still open.
    isDefault.value = true;
    await tester.pump();

    expect(find.text('ChronoFold is your home app'), findsOneWidget);
    expect(find.text('Set as default'), findsNothing);
  });

  testWidgets('lock mode switches only after the user confirms',
      (tester) async {
    _setSize(tester, const Size(400, 1400));
    final isDefault = ValueNotifier<bool>(true);
    addTearDown(isDefault.dispose);
    final changes = <bool>[];

    await tester.pumpWidget(
      _host(
        isDefault: isDefault,
        nativeMode: false,
        onLockModeChanged: (native) async => changes.add(native),
      ),
    );

    // Tapping the already-selected option does nothing at all.
    await tester.tap(find.text('Cosmic'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);

    // Cancel leaves the surface alone.
    await tester.tap(find.text('ColorOS'));
    await tester.pumpAndSettle();
    expect(find.text('Use the ColorOS lock screen?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(changes, isEmpty);
    expect(
      find.byIcon(Icons.radio_button_checked_rounded),
      findsOneWidget,
    );
    final cosmicSelected = tester.getSemantics(
      find.bySemanticsLabel(RegExp('^Lock screen: Cosmic')),
    );
    expect(cosmicSelected, isSemantics(isSelected: true));

    // Confirm applies it.
    await tester.tap(find.text('ColorOS'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Switch'));
    await tester.pumpAndSettle();
    expect(changes, [true]);
    final colorOsSelected = tester.getSemantics(
      find.bySemanticsLabel(RegExp('^Lock screen: ColorOS')),
    );
    expect(colorOsSelected, isSemantics(isSelected: true));
  });

  testWidgets('gestures and wallpaper rows call through', (tester) async {
    _setSize(tester, const Size(400, 1400));
    final isDefault = ValueNotifier<bool>(true);
    addTearDown(isDefault.dispose);
    var gestures = 0;
    var wallpaper = 0;

    await tester.pumpWidget(
      _host(
        isDefault: isDefault,
        onOpenGestures: () => gestures++,
        onOpenAmbientWallpaper: () => wallpaper++,
      ),
    );

    await tester.tap(find.text('Ambient wallpaper'));
    await tester.tap(find.text('Swipe down, double-tap to sleep'));
    await tester.pump();
    expect(wallpaper, 1);
    expect(gestures, 1);
  });

  for (final size in const [Size(360, 780), Size(900, 1000)]) {
    testWidgets('no overflow at 2.0 text scale on ${size.width}x${size.height}',
        (tester) async {
      _setSize(tester, size);
      final isDefault = ValueNotifier<bool>(false);
      addTearDown(isDefault.dispose);

      await tester.pumpWidget(_host(isDefault: isDefault, textScale: 2.0));
      await tester.pump();
      expect(tester.takeException(), isNull);

      // The bottom of the list is reachable by scrolling.
      await tester.scrollUntilVisible(
        find.text('Home screen for foldables'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.takeException(), isNull);

      // On the inner screen the panel is capped and centred, not stretched.
      if (size.width > LauncherSettingsSheet.maxWidth) {
        final double width = tester
            .getSize(find.byType(LauncherSettingsSheet).first)
            .width;
        final Rect panel = tester.getRect(
          find
              .ancestor(
                of: find.text('Settings'),
                matching: find.byType(Container),
              )
              .last,
        );
        expect(panel.width, lessThanOrEqualTo(LauncherSettingsSheet.maxWidth));
        expect(panel.center.dx, closeTo(width / 2, 1));
      }
    });
  }

  testWidgets('the dock gear opens ChronoFold Settings, not a system page',
      (tester) async {
    _setSize(tester, const Size(900, 1000));
    await tester.pumpWidget(
      ChronoFoldApp(
        isKeyguardLocked: () async => false,
        firstRunHintDismissed: true,
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.byTooltip('Settings'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(LauncherSettingsSheet), findsOneWidget);
    expect(find.text('Default home app'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
