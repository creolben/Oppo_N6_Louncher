import 'package:flutter/material.dart';

/// Formats a clock reading the way the platform's own clock is formatted.
///
/// Every ChronoFold surface used to hardcode a zero-padded 24-hour reading,
/// so on a device set to 12-hour the launcher disagreed with the ColorOS
/// status bar and keyguard it sits next to — the "two clocks in different
/// formats" complaint. The time *value* is correct wherever it comes from
/// (each surface samples `DateTime.now()` per its own minute-gated timer);
/// only the rendering follows the platform here, and from this one helper,
/// so the four surfaces cannot drift apart again.
///
/// 24-hour keeps the zero-padded `HH:MM`. 12-hour drops the hour's leading
/// zero and appends the locale day period (`7:05 PM`), matching what the OEM
/// clock shows for the same setting.
String formatClockTime(BuildContext context, DateTime time) {
  final minute = time.minute.toString().padLeft(2, '0');
  if (MediaQuery.alwaysUse24HourFormatOf(context)) {
    return '${time.hour.toString().padLeft(2, '0')}:$minute';
  }
  final int hourOfHalfDay = time.hour % 12;
  final int hour12 = hourOfHalfDay == 0 ? 12 : hourOfHalfDay;
  final String dayPeriod = time.hour < 12 ? 'AM' : 'PM';
  return '$hour12:$minute $dayPeriod';
}