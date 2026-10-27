import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mylauncher/main.dart';
import 'package:mylauncher/ui/theme/luminous_home_theme.dart';
import 'package:mylauncher/ui/widgets/native_panel_transition.dart';

/// Guards the ColorOS-derived "native feel" chrome: the shared panel
/// transition, the motion tokens' reduce-motion behaviour, the 60% search
/// scrim, and the sentence-case 12sp header chips.

void main() {
  group('Native panel transition', () {
    testWidgets('starts scale at 0.9 and never exceeds 1.0', (tester) async {
      final AnimationController controller = AnimationController(
        vsync: tester,
        duration: LuminousHomeTheme.motionPanel,
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => buildNativePanelTransition(
              context,
              controller,
              const AlwaysStoppedAnimation<double>(0.0),
              const SizedBox(width: 10, height: 10),
            ),
          ),
        ),
      );
      await tester.pump();

      double scaleValue() => tester
          .widget<ScaleTransition>(find.byType(ScaleTransition))
          .scale
          .value;

      expect(scaleValue(), closeTo(nativePanelScaleBegin, 1e-9));

      for (int i = 0; i <= 40; i++) {
        controller.value = i / 40;
        await tester.pump();
        expect(
          scaleValue(),
          inInclusiveRange(nativePanelScaleBegin - 1e-9, 1.0 + 1e-9),
          reason: 'scale left the 0.9..1.0 band at t=${i / 40}',
        );
      }

      expect(scaleValue(), closeTo(1.0, 1e-9));
    });

    test('route opens over motionPanel and closes over motionPanelExit', () {
      final NativePanelRoute<void> route = NativePanelRoute<void>(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const SizedBox.shrink(),
      );

      expect(route.transitionDuration, LuminousHomeTheme.motionPanel);
      expect(route.reverseTransitionDuration, LuminousHomeTheme.motionPanelExit);
    });
  });

  group('Motion tokens', () {
    testWidgets('motion() returns zero under disableAnimations', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Builder(
              builder: (context) => Text(
                '${LuminousHomeTheme.motion(context, LuminousHomeTheme.motionPanel).inMilliseconds}',
                textDirection: TextDirection.ltr,
              ),
            ),
          ),
        ),
      );

      expect(find.text('0'), findsOneWidget);
    });

    testWidgets('motion() passes the duration through when enabled',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Text(
              '${LuminousHomeTheme.motion(context, LuminousHomeTheme.motionPanel).inMilliseconds}',
              textDirection: TextDirection.ltr,
            ),
          ),
        ),
      );

      expect(find.text('350'), findsOneWidget);
    });
  });

  group('ColorOS chrome tokens', () {
    test('the search scrim is 60 percent like coui_color_mask_dark', () {
      final int argb = LuminousHomeTheme.scrim.toARGB32();

      expect((argb >> 24) & 0xFF, 0x99);
      expect(argb & 0xFFFFFF, 0x04060E);
    });

    test('the os17 corner scale is present alongside the existing radii', () {
      expect(LuminousHomeTheme.radiusS, 11);
      expect(LuminousHomeTheme.radiusM, 16);
      expect(LuminousHomeTheme.radiusL, 22);
      expect(LuminousHomeTheme.radiusFull, 72);
      expect(LuminousHomeTheme.cardRadius, 28);
      expect(LuminousHomeTheme.controlRadius, 18);
    });
  });

  group('Header utility chips', () {
    testWidgets('shows Set default, not SET DEFAULT, at 12sp w500',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CosmicHeaderHud(
              isDefaultLauncher: false,
              onSetDefaultLauncher: () {},
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Set default'), findsOneWidget);
      expect(find.text('SET DEFAULT'), findsNothing);

      final Text label = tester.widget<Text>(find.text('Set default'));
      expect(label.style?.fontSize, 12);
      expect(label.style?.fontWeight, FontWeight.w500);
      expect(label.style?.letterSpacing, isNull,
          reason: 'ColorOS chip labels are not tracked');
    });

    testWidgets('utility shelf does not overflow at 2.0 scale on cover width',
        (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(2.0),
              ),
              child: Scaffold(
                body: CosmicHeaderHud(
                  isDefaultLauncher: false,
                  onSetDefaultLauncher: () {},
                  onToggleCockpit: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });
}
