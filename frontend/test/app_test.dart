import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'package:pocketwise/api.dart';
import 'package:pocketwise/models.dart';
import 'package:pocketwise/notifications.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tz_data.initializeTimeZones();

  group('Money values', () {
    test('preserves decimal amounts exactly', () {
      expect(parseMoney('0.10') + parseMoney('0.20'), 30);
      expect(parseMoney('1250.50'), 125050);
      expect(decimalMoney(125050), '1250.50');
      expect(decimalMoney(5), '0.05');
    });

    test('rejects invalid amounts', () {
      expect(() => positiveMoney('0'), throwsFormatException);
      expect(() => positiveMoney('-10'), throwsFormatException);
      expect(() => positiveMoney('12.345'), throwsFormatException);
      expect(() => positiveMoney('abc'), throwsFormatException);
      expect(() => parseMoney('1000000000000.00'), throwsFormatException);
    });
  });

  group('Local accounts', () {
    late String initialStore;
    String? savedStore;
    late Api api;

    Api createApi() {
      return Api(
        readStore: () async => savedStore,
        writeStore: (value) async {
          savedStore = value;
        },
      );
    }

    setUpAll(() async {
      savedStore = null;

      final first = createApi();
      await first.restoreSession();
      initialStore = savedStore!;
      first.dispose();
    });

    setUp(() async {
      savedStore = initialStore;
      api = createApi();

      await api.login('yar@pocketwise.example', 'PocketWise@123');
    });

    tearDown(() {
      api.dispose();
    });

    test('rejects an incorrect password', () async {
      await api.logout();

      await expectLater(
        api.login('yar@pocketwise.example', 'WrongPassword123'),
        throwsA(isA<ApiException>()),
      );

      expect(await api.restoreSession(), isFalse);
    });

    test('records and session survive a new Api instance', () async {
      final before = await api.loadData();
      final category = before.activeCategories(expenseType).first;

      await api.saveTransaction(
        MoneyTransaction(
          id: 0,
          categoryId: category.id,
          amountPaisa: 12345,
          date: DateTime.now(),
          note: 'Persistence check',
        ),
      );

      final reopened = createApi();

      expect(await reopened.restoreSession(), isTrue);

      final restored = await reopened.loadData();

      expect(
        restored.transactions.any(
          (item) =>
              item.note == 'Persistence check' && item.amountPaisa == 12345,
        ),
        isTrue,
      );

      reopened.dispose();
    });

    test('different accounts have separate records', () async {
      final first = await api.loadData();
      expect(first.transactions, isNotEmpty);

      await api.logout();
      await api.login('durdana@pocketwise.example', 'PocketWise@123');

      final second = await api.loadData();

      expect(second.user.email, 'durdana@pocketwise.example');
      expect(second.transactions, isEmpty);
      expect(second.budgets, isEmpty);

      await expectLater(
        api.deleteTransaction(first.transactions.first.id),
        throwsA(isA<ApiException>()),
      );
    });

    test('registration creates an account with empty records', () async {
      await api.logout();

      await api.register(
        'New Student',
        'student@pocketwise.example',
        'Student@123',
      );

      await api.login('student@pocketwise.example', 'Student@123');

      final data = await api.loadData();

      expect(data.user.fullName, 'New Student');
      expect(data.categories, isNotEmpty);
      expect(data.transactions, isEmpty);
      expect(data.templates, isEmpty);
    });

    test('duplicate email registration is rejected', () async {
      await expectLater(
        api.register('Another User', ' YAR@POCKETWISE.EXAMPLE ', 'Another@123'),
        throwsA(isA<ApiException>()),
      );
    });

    test('password change ends the session and updates credentials', () async {
      await api.changePassword('PocketWise@123', 'ChangedPassword@456');

      expect(await api.restoreSession(), isFalse);

      await expectLater(
        api.login('yar@pocketwise.example', 'PocketWise@123'),
        throwsA(isA<ApiException>()),
      );

      await api.login('yar@pocketwise.example', 'ChangedPassword@456');

      expect(await api.restoreSession(), isTrue);
    });

    test('category totals follow saved transactions', () async {
      final before = await api.loadData();
      final month = monthOnly(DateTime.now());
      final category = before.activeCategories(expenseType).first;

      final original = before.categoryTotal(category.id, month);

      await api.saveTransaction(
        MoneyTransaction(
          id: 0,
          categoryId: category.id,
          amountPaisa: 12345,
          date: DateTime.now(),
        ),
      );

      final after = await api.loadData();

      expect(after.categoryTotal(category.id, month), original + 12345);
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
        throwsA(isA<ApiException>()),
      );
    });
  });
  group('Reminder dates', () {
    final location = tz.getLocation('Asia/Karachi');

    test('monthly reminders handle shorter months', () {
      final reminder = BillReminder(
        id: 1,
        title: 'Monthly bill',
        scheduledAt: tz.TZDateTime(location, 2028, 1, 31, 9).toUtc(),
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

    test('expired one-time reminders are not scheduled', () {
      final reminder = BillReminder(
        id: 2,
        title: 'Old bill',
        scheduledAt: DateTime.utc(2020, 1, 1),
        timezone: 'Asia/Karachi',
      );

      expect(
        Notifications.occurrences(reminder, now: DateTime.utc(2026, 1, 1)),
        isEmpty,
      );
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
        Notifications.occurrences(reminder, now: DateTime.utc(2026, 1, 1)),
        isEmpty,
      );
    });
  });
}
