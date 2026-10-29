import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mylauncher/canvas/camera_controller.dart';

/// The canvas binds the shared camera to its own ticker provider. When it is
/// disposed — a fold mid-fly — it must release that binding, but never the
/// binding a newer canvas has already made during the posture transition.
void main() {
  testWidgets('detach by a stale owner leaves the current binding alone', (
    tester,
  ) async {
    final camera = CameraController()..updateViewportSize(const Size(400, 800));
    // Distinct instances: const ones would be canonicalised into one.
    final outgoing = TestVSync();
    final incoming = TestVSync();

    camera.init(outgoing);
    camera.init(incoming);
    camera.detach(outgoing);
    expect(camera.isBoundTo(incoming), isTrue);

    // Still animated on the live binding: the first frame has not moved it.
    final before = camera.translation;
    camera.flyTo(const Offset(100, 100));
    expect(camera.translation, before);
    // Disposed inside the body: the fly is still running, and the binding
    // checks for live animations before tear-downs run.
    camera.dispose();
  });

  testWidgets('a detached camera settles without a ticker', (tester) async {
    final camera = CameraController()..updateViewportSize(const Size(400, 800));
    addTearDown(camera.dispose);
    final owner = TestVSync();

    camera.init(owner);
    camera.flyTo(const Offset(100, 100)); // mid-fly when the canvas goes
    camera.detach(owner);
    expect(camera.isBoundTo(owner), isFalse);

    camera.resetView();
    expect(camera.zoom, 1.0);
    expect(camera.translation, const Offset(200, 400));

    // Re-initable by the next canvas.
    camera.init(owner);
    expect(camera.isBoundTo(owner), isTrue);
  });
}
