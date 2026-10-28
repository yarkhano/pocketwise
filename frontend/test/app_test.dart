import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'package:pocketwise/api.dart';
import 'package:pocketwise/models.dart';
import 'package:pocketwise/notifications.dart';

void main() {
  setUpAll(() {
    tz_data.initializeTimeZones();
  });

  group('Money values', () {
    test('preserves decimal amounts exactly', () {
      expect(parseMoney('0.10') + parseMoney('0.20'), 30);
      expect(parseMoney('1250.50'), 125050);
      expect(decimalMoney(125050), '1250.50');
      expect(decimalMoney(5), '0.05');
    });

    test('rejects invalid transaction amounts', () {
      expect(() => positiveMoney('0'), throwsFormatException);
      expect(() => positiveMoney('-10'), throwsFormatException);
      expect(() => positiveMoney('12.345'), throwsFormatException);
      expect(() => positiveMoney('abc'), throwsFormatException);
    });

    test('rejects values above the supported maximum', () {
      expect(
        () => parseMoney('1000000000000.00'),
        throwsFormatException,
      );
    });
  });

  group('Demo data', () {
    late Api api;

    setUp(() {
      api = Api();
      api.enterDemo();
    });

    tearDown(() {
      api.dispose();
    });

    test('category totals follow transaction changes', () async {
      final before = await api.loadData();
      final month = monthOnly(DateTime.now());

      final category = before.activeCategories(expenseType).first;
      final originalTotal = before.categoryTotal(category.id, month);

      await api.saveTransaction(
        MoneyTransaction(
          id: 0,
          categoryId: category.id,
          amountPaisa: 12345,
          date: DateTime.now(),
          note: 'Test expense',
        ),
      );

      final after = await api.loadData();

      expect(
        after.categoryTotal(category.id, month),
        originalTotal + 12345,
      );
    });

    test('saving a template does not create a transaction', () async {
      final before = await api.loadData();
      final category = before.activeCategories(expenseType).first;

      await api.saveTemplate(
        QuickTemplate(
          id: 0,
          categoryId: category.id,
          name: 'Test template',
          amountPaisa: 50000,
          note: 'For later use',
        ),
      );

      final after = await api.loadData();

      expect(after.transactions.length, before.transactions.length);
      expect(after.templates.length, before.templates.length + 1);
    });

    test('duplicate category budgets are rejected', () async {
      final data = await api.loadData();
      final existing = data.budgets.first;

      await expectLater(
        api.saveBudget(
          MonthlyBudget(
            id: 0,
            categoryId: existing.categoryId,
            month: existing.month,
            limitPaisa: 99900,
          ),
        ),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('Reminder dates', () {
    final location = tz.getLocation('Asia/Karachi');

    test('monthly reminders handle short months', () {
      final reminder = BillReminder(
        id: 1,
        title: 'Monthly bill',
        scheduledAt: tz.TZDateTime(
          location,
          2028,
          1,
          31,
          9,
        ).toUtc(),
        timezone: 'Asia/Karachi',
        repeatType: 'monthly',
      );

      final dates = Notifications.occurrences(
        reminder,
        now: tz.TZDateTime(location, 2028, 1, 1),
        count: 3,
      );

      expect(dates.map((date) => date.month).toList(), [1, 2, 3]);
      expect(dates.map((date) => date.day).toList(), [31, 29, 31]);
      expect(dates.every((date) => date.hour == 9), isTrue);
    });

    test('expired one-time reminders are not rescheduled', () {
      final reminder = BillReminder(
        id: 2,
        title: 'Old bill',
        scheduledAt: DateTime.utc(2020, 1, 1),
        timezone: 'Asia/Karachi',
      );

      final dates = Notifications.occurrences(
        reminder,
        now: DateTime.utc(2026, 1, 1),
      );

      expect(dates, isEmpty);
    });

    test('disabled reminders have no occurrences', () {
      final reminder = BillReminder(
        id: 3,
        title: 'Disabled bill',
        scheduledAt: DateTime.utc(2030, 1, 1),
        timezone: 'Asia/Karachi',
        repeatType: 'monthly',
        isEnabled: false,
      );

      expect(
        Notifications.occurrences(
          reminder,
          now: DateTime.utc(2026, 1, 1),
        ),
        isEmpty,
      );
    });
  });
}