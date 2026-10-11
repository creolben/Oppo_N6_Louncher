import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mylauncher/core/badge_controller.dart';

/// The controller is the one place the badge map becomes per-package counts;
/// these tests drive it through an injected stream, exactly as a test host does
/// instead of the platform channel.
void main() {
  test('maps package names to positive counts', () async {
    final events = StreamController<Map<String, dynamic>>.broadcast();
    final controller = BadgeController(stream: events.stream);
    addTearDown(() {
      controller.dispose();
      events.close();
    });

    expect(controller.hasReceivedEvent, isFalse);
    expect(controller.countFor('com.a'), 0);

    events.add(<String, dynamic>{'com.a': 3, 'com.b': 1});
    await pumpEventQueue();

    expect(controller.countFor('com.a'), 3);
    expect(controller.countFor('com.b'), 1);
    expect(controller.countFor('com.c'), 0);
    expect(controller.hasReceivedEvent, isTrue);
  });

  test('an empty map clears the counts rather than keeping stale numbers',
      () async {
    final events = StreamController<Map<String, dynamic>>.broadcast();
    final controller = BadgeController(stream: events.stream);
    addTearDown(() {
      controller.dispose();
      events.close();
    });

    events.add(<String, dynamic>{'com.a': 5});
    await pumpEventQueue();
    expect(controller.countFor('com.a'), 5);

    events.add(<String, dynamic>{});
    await pumpEventQueue();
    expect(controller.countFor('com.a'), 0);
    expect(controller.counts, isEmpty);
  });

  test('ignores zero, negative and non-numeric values', () async {
    final events = StreamController<Map<String, dynamic>>.broadcast();
    final controller = BadgeController(stream: events.stream);
    addTearDown(() {
      controller.dispose();
      events.close();
    });

    events.add(<String, dynamic>{
      'com.zero': 0,
      'com.negative': -2,
      'com.text': 'not a number',
      'com.numericText': '4',
    });
    await pumpEventQueue();

    expect(controller.countFor('com.zero'), 0);
    expect(controller.countFor('com.negative'), 0);
    expect(controller.countFor('com.text'), 0);
    expect(controller.countFor('com.numericText'), 4);
  });

  test('notifies only when the counts actually change', () async {
    final events = StreamController<Map<String, dynamic>>.broadcast();
    final controller = BadgeController(stream: events.stream);
    addTearDown(() {
      controller.dispose();
      events.close();
    });

    var notifications = 0;
    controller.addListener(() => notifications++);

    events.add(<String, dynamic>{'com.a': 2});
    await pumpEventQueue();
    expect(notifications, 1);

    events.add(<String, dynamic>{'com.a': 2});
    await pumpEventQueue();
    expect(notifications, 1, reason: 'an identical map is not a change');

    events.add(<String, dynamic>{'com.a': 3});
    await pumpEventQueue();
    expect(notifications, 2);
  });
}
