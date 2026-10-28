import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'models.dart';

class Notifications {
  Notifications._();

  static final _plugin = FlutterLocalNotificationsPlugin();

  static bool _timezonesLoaded = false;
  static bool _ready = false;
  static String? _initializationError;

  // Prevent simultaneous refreshes from changing the schedule together.
  static Future<void> _queue = Future<void>.value();

  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static String get deviceTimezone => tz.local.name;

  static Future<void> initialize() async {
    if (!_timezonesLoaded) {
      tz_data.initializeTimeZones();
      _timezonesLoaded = true;
    }

    if (!supported || _ready) return;

    try {
      final information = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(information.identifier));

      final initialized = await _plugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('ic_notification'),
        ),
      );

      if (initialized != true) {
        throw StateError('Android notification initialization failed.');
      }

      _ready = true;
      _initializationError = null;
    } catch (_) {
      _initializationError =
          'Notifications could not start. Check the Android setup '
          'and restart the app.';
    }
  }

  static Future<T> _serialized<T>(Future<T> Function() operation) {
    final result = _queue.then((_) => operation());

    // Keep the queue usable even if one operation fails.
    _queue = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );

    return result;
  }

  static Future<bool> requestPermission() async {
    await initialize();

    if (!supported) {
      throw StateError('Local notifications are available on Android only.');
    }

    if (!_ready) {
      throw StateError(
        _initializationError ?? 'Notifications are unavailable.',
      );
    }

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    if (android == null) return false;

    await android.requestNotificationsPermission();

    return await android.areNotificationsEnabled() ?? false;
  }

  static Future<void> cancelAll() {
    return _serialized(() async {
      if (!supported) return;
      await _plugin.cancelAll();
    });
  }

  // Use this for displaying the reminder in its original time zone.
  static tz.TZDateTime localTime(BillReminder reminder) {
    return tz.TZDateTime.from(
      reminder.scheduledAt,
      tz.getLocation(reminder.timezone),
    );
  }

  // This method is separate so its date rules can be tested.
  static List<tz.TZDateTime> occurrences(
    BillReminder reminder, {
    required DateTime now,
    int count = 12,
  }) {
    if (!reminder.isEnabled || count <= 0) return [];

    final location = tz.getLocation(reminder.timezone);
    final anchor = tz.TZDateTime.from(reminder.scheduledAt, location);
    final current = tz.TZDateTime.from(now, location);

    if (!reminder.isMonthly) {
      return anchor.isAfter(current) ? [anchor] : [];
    }

    final anchorMonth = anchor.year * 12 + anchor.month - 1;
    final currentMonth = current.year * 12 + current.month - 1;
    final firstMonth = math.max(anchorMonth, currentMonth);

    final result = <tz.TZDateTime>[];

    for (var offset = 0; result.length < count; offset++) {
      final monthIndex = firstMonth + offset;
      final year = monthIndex ~/ 12;
      final month = monthIndex % 12 + 1;
      final lastDay = DateTime.utc(year, month + 1, 0).day;

      final occurrence = tz.TZDateTime(
        location,
        year,
        month,
        math.min(anchor.day, lastDay),
        anchor.hour,
        anchor.minute,
      );

      if (occurrence.isAfter(current) &&
          !occurrence.isBefore(anchor)) {
        result.add(occurrence);
      }
    }

    return result;
  }

  static Future<String?> sync(
    List<BillReminder> reminders, {
    required bool enabled,
  }) {
    return _serialized(() async {
      await initialize();

      if (!supported) {
        return enabled
            ? 'Reminder notifications are available on Android only.'
            : null;
      }

      try {
        if (!enabled) {
          await _plugin.cancelAll();
          return null;
        }

        if (!_ready) {
          return _initializationError;
        }

        final android = _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

        final allowed =
            await android?.areNotificationsEnabled() ?? false;

        if (!allowed) {
          await _plugin.cancelAll();

          return 'Notifications are blocked. Enable them in Android '
              'Settings, then refresh PocketWise.';
        }

        final now = DateTime.now();
        final jobs = <_NotificationJob>[];

        // Build the schedule first. Invalid data must not erase
        // an otherwise working schedule.
        for (final reminder in reminders) {
          for (final date in occurrences(reminder, now: now)) {
            jobs.add(_NotificationJob(reminder, date));
          }
        }

        jobs.sort((a, b) {
          final comparison = a.date.compareTo(b.date);
          return comparison != 0
              ? comparison
              : a.reminder.id.compareTo(b.reminder.id);
        });

        await _plugin.cancelAll();

        // Stay below device-specific alarm limits.
        final scheduledJobs = jobs.take(400).toList();

        for (var index = 0; index < scheduledJobs.length; index++) {
          final job = scheduledJobs[index];

          await _plugin.zonedSchedule(
            index + 1,
            'PocketWise reminder',
            job.reminder.title,
            job.date,
            const NotificationDetails(
              android: AndroidNotificationDetails(
                'pocketwise_bills',
                'Bill reminders',
                channelDescription: 'Your saved PocketWise reminders',
                icon: 'ic_notification',
                importance: Importance.high,
                priority: Priority.high,
              ),
            ),
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            payload: 'reminder:${job.reminder.id}',
          );
        }

        if (jobs.length > 400) {
          return 'Only the nearest 400 reminder occurrences were scheduled. '
              'Reduce active reminders and refresh.';
        }

        return null;
      } catch (_) {
        return 'Your reminder data is saved, but the device schedule '
            'could not be fully updated. Refresh to retry.';
      }
    });
  }
}

class _NotificationJob {
  const _NotificationJob(this.reminder, this.date);

  final BillReminder reminder;
  final tz.TZDateTime date;
}