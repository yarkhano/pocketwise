import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'models.dart';

class ApiException implements Exception {
  const ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class Api {
  // This storage belongs only to the frontend presentation version.
  // The future backend implementation must not treat it as server data.
  static const _storageKey = 'pocketwise_local_accounts_v1';
  static const _storage = FlutterSecureStorage();

  final Future<String?> Function() _readStore;
  final Future<void> Function(String value) _writeStore;

  Json? _state;

  // Serialize operations to avoid overlapping saves.
  Future<void> _queue = Future<void>.value();

  Api({
    Future<String?> Function()? readStore,
    Future<void> Function(String value)? writeStore,
  }) : _readStore = readStore ?? (() => _storage.read(key: _storageKey)),
       _writeStore =
           writeStore ??
           ((value) => _storage.write(key: _storageKey, value: value));

  void dispose() {}

  Json get _root => _state!;

  List<Json> get _accounts => (_root['accounts'] as List).cast<Json>();

  Json get _account {
    final activeId = _root['active_user_id'];

    for (final account in _accounts) {
      final user = account['user'] as Json;

      if (user['id'] == activeId) return account;
    }

    throw const ApiException('Please log in to continue.');
  }

  Future<T> _run<T>(FutureOr<T> Function() operation, {bool save = false}) {
    final future = _queue.then((_) async {
      await _initialize();

      final previous = save ? jsonEncode(_root) : null;

      try {
        final result = await operation();

        if (save) {
          await _writeStore(jsonEncode(_root));
        }

        return result;
      } catch (_) {
        // Restore the previous in-memory state if validation or saving fails.
        if (previous != null) {
          _state = jsonDecode(previous) as Json;
        }

        rethrow;
      }
    });

    _queue = future.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );

    return future;
  }

  Future<void> _initialize() async {
    if (_state != null) return;

    final saved = await _readStore();

    if (saved != null) {
      try {
        final decoded = jsonDecode(saved);

        if (decoded is! Map<String, dynamic> ||
            decoded['version'] != 1 ||
            decoded['accounts'] is! List ||
            decoded['next_user_id'] is! int ||
            decoded['next_record_id'] is! int) {
          throw const FormatException();
        }

        _state = decoded;
        return;
      } catch (_) {
        throw const ApiException(
          'Saved account data could not be opened. '
          'Your existing data has not been overwritten.',
        );
      }
    }

    _state = {
      'version': 1,
      'active_user_id': null,
      'next_user_id': 1,
      'next_record_id': 100,
      'accounts': <Json>[],
    };

    try {
      // Fictional classroom credentials only.
      final yar = await _createAccount(
        'Muhammad Yar Khan',
        'yar@pocketwise.example',
        'PocketWise@123',
      );

      await _createAccount(
        'Durdana Bila',
        'durdana@pocketwise.example',
        'PocketWise@123',
      );

      await _createAccount(
        'Zain Ul Hadi',
        'zain@pocketwise.example',
        'PocketWise@123',
      );

      // The first account has sample records for presenting reports.
      // The other accounts start empty to demonstrate account separation.
      _addPresentationRecords(yar);

      await _writeStore(jsonEncode(_root));
    } catch (_) {
      _state = null;
      rethrow;
    }
  }

  static String _normalizeEmail(String value) {
    return value.trim().toLowerCase();
  }

  static void _validatePassword(String value) {
    if (value.length < 8 || value.length > 128) {
      throw const ApiException(
        'Password must contain between 8 and 128 characters.',
      );
    }
  }

  static void _validateText(
    String value,
    String label,
    int maximum, {
    bool optional = false,
  }) {
    if (!optional && value.trim().isEmpty) {
      throw ApiException('Enter $label.');
    }

    if (value.trim().length > maximum) {
      throw ApiException('$label must not exceed $maximum characters.');
    }
  }

  static void _validateAmount(int value) {
    if (value <= 0 || value > maximumAmountPaisa) {
      throw const ApiException('Enter a valid positive amount.');
    }
  }

  Future<String> _passwordHash(
    String password,
    String salt,
    int iterations,
  ) async {
    final algorithm = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: 256,
    );

    final key = await algorithm.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: base64Decode(salt),
    );

    return base64Encode(await key.extractBytes());
  }

  Future<Json> _makeCredential(String password) async {
    const iterations = 600000;
    final random = Random.secure();

    final salt = base64Encode(
      List<int>.generate(16, (_) => random.nextInt(256)),
    );

    return {
      'salt': salt,
      'iterations': iterations,
      'hash': await _passwordHash(password, salt, iterations),
    };
  }

  Future<bool> _passwordMatches(Json credential, String password) async {
    final actual = await _passwordHash(
      password,
      credential['salt'] as String,
      credential['iterations'] as int,
    );

    final expectedBytes = base64Decode(credential['hash'] as String);
    final actualBytes = base64Decode(actual);

    if (expectedBytes.length != actualBytes.length) return false;

    var difference = 0;

    for (var index = 0; index < actualBytes.length; index++) {
      difference |= expectedBytes[index] ^ actualBytes[index];
    }

    return difference == 0;
  }

  int _newRecordId() {
    final id = _root['next_record_id'] as int;
    _root['next_record_id'] = id + 1;
    return id;
  }

  Future<Json> _createAccount(
    String fullName,
    String email,
    String password,
  ) async {
    final id = _root['next_user_id'] as int;
    final credential = await _makeCredential(password);

    _root['next_user_id'] = id + 1;

    final account = <String, dynamic>{
      'user': {
        'id': id,
        'full_name': fullName.trim(),
        'email': _normalizeEmail(email),
        'reminders_enabled': false,
      },
      'credential': credential,
      'categories': _defaultCategories(),
      'transactions': <Json>[],
      'budgets': <Json>[],
      'reminders': <Json>[],
      'templates': <Json>[],
    };

    (_root['accounts'] as List).add(account);
    return account;
  }

  List<Json> _defaultCategories() {
    final definitions = [
      ('Food', expenseType, 'food', 0xFFE76F00),
      ('Transport', expenseType, 'transport', 0xFF2563EB),
      ('Shopping', expenseType, 'shopping', 0xFF9333EA),
      ('Bills', expenseType, 'bills', 0xFF0891B2),
      ('Education', expenseType, 'education', 0xFF2563EB),
      ('Health', expenseType, 'health', 0xFFBE3445),
      ('Allowance', incomeType, 'allowance', 0xFF087F5B),
      ('Salary', incomeType, 'salary', 0xFF2563EB),
    ];

    return [
      for (final item in definitions)
        {
          'id': _newRecordId(),
          'name': item.$1,
          'type': item.$2,
          'icon_key': item.$3,
          'color_value': item.$4,
          'is_archived': false,
        },
    ];
  }

  void _addPresentationRecords(Json account) {
    final categories = (account['categories'] as List).cast<Json>();

    int categoryId(String name) {
      return categories.firstWhere((category) => category['name'] == name)['id']
          as int;
    }

    final now = DateTime.now();
    final month = monthOnly(now);
    final previousMonth = DateTime(now.year, now.month - 1);

    final transactions = [
      MoneyTransaction(
        id: _newRecordId(),
        categoryId: categoryId('Allowance'),
        amountPaisa: 3000000,
        date: month,
        note: 'Monthly allowance',
      ),
      MoneyTransaction(
        id: _newRecordId(),
        categoryId: categoryId('Food'),
        amountPaisa: 850000,
        date: dateOnly(now),
        note: 'Food spending',
      ),
      MoneyTransaction(
        id: _newRecordId(),
        categoryId: categoryId('Transport'),
        amountPaisa: 150000,
        date: dateOnly(now),
        note: 'Bus fares',
      ),
      MoneyTransaction(
        id: _newRecordId(),
        categoryId: categoryId('Shopping'),
        amountPaisa: 220000,
        date: dateOnly(now),
        note: 'Stationery and supplies',
      ),
      MoneyTransaction(
        id: _newRecordId(),
        categoryId: categoryId('Allowance'),
        amountPaisa: 2500000,
        date: previousMonth,
        note: 'Previous allowance',
      ),
      MoneyTransaction(
        id: _newRecordId(),
        categoryId: categoryId('Food'),
        amountPaisa: 750000,
        date: DateTime(previousMonth.year, previousMonth.month, 5),
        note: 'Previous food spending',
      ),
    ];

    account['transactions'] = [
      for (final item in transactions) {'id': item.id, ...item.toInput()},
    ];

    final budgets = [
      MonthlyBudget(
        id: _newRecordId(),
        categoryId: categoryId('Food'),
        month: month,
        limitPaisa: 1000000,
      ),
      MonthlyBudget(
        id: _newRecordId(),
        categoryId: categoryId('Transport'),
        month: month,
        limitPaisa: 500000,
      ),
    ];

    account['budgets'] = [
      for (final item in budgets) {'id': item.id, ...item.toInput()},
    ];

    final templates = [
      QuickTemplate(
        id: _newRecordId(),
        categoryId: categoryId('Food'),
        name: 'University lunch',
        amountPaisa: 35000,
        note: 'Lunch',
      ),
      QuickTemplate(
        id: _newRecordId(),
        categoryId: categoryId('Transport'),
        name: 'Bus fare',
        amountPaisa: 10000,
        note: 'Travel to university',
      ),
    ];

    account['templates'] = [
      for (final item in templates) {'id': item.id, ...item.toInput()},
    ];
  }

  Future<bool> restoreSession() {
    return _run(() {
      final activeId = _root['active_user_id'];

      return _accounts.any(
        (account) => (account['user'] as Json)['id'] == activeId,
      );
    });
  }

  Future<void> register(String fullName, String email, String password) {
    return _run<void>(() async {
      _validateText(fullName, 'your name', 80);
      _validatePassword(password);

      final normalized = _normalizeEmail(email);

      if (normalized.length > 254 ||
          !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(normalized)) {
        throw const ApiException('Enter a valid email address.');
      }

      if (_accounts.any(
        (account) => (account['user'] as Json)['email'] == normalized,
      )) {
        throw const ApiException('An account with this email already exists.');
      }

      await _createAccount(fullName, normalized, password);
    }, save: true);
  }

  Future<void> login(String email, String password) {
    return _run<void>(() async {
      final normalized = _normalizeEmail(email);
      Json? selected;

      for (final account in _accounts) {
        if ((account['user'] as Json)['email'] == normalized) {
          selected = account;
          break;
        }
      }

      if (selected == null ||
          !await _passwordMatches(selected['credential'] as Json, password)) {
        throw const ApiException('Incorrect email or password.');
      }

      _root['active_user_id'] = (selected['user'] as Json)['id'];
    }, save: true);
  }

  Future<String?> logout() {
    return _run<String?>(() {
      _root['active_user_id'] = null;
      return null;
    }, save: true);
  }

  AppData _data() {
    final account = _account;

    return AppData(
      user: UserProfile.fromJson(account['user'] as Json),
      categories: _rows('categories').map(ExpenseCategory.fromJson).toList(),
      transactions: _rows(
        'transactions',
      ).map(MoneyTransaction.fromJson).toList(),
      budgets: _rows('budgets').map(MonthlyBudget.fromJson).toList(),
      reminders: _rows('reminders').map(BillReminder.fromJson).toList(),
      templates: _rows('templates').map(QuickTemplate.fromJson).toList(),
    );
  }

  Future<AppData> loadData() => _run(_data);

  List<Json> _rows(String collection) {
    return List<Json>.from(_account[collection] as List);
  }

  Json? _existing(String collection, int id) {
    if (id == 0) return null;

    for (final row in _rows(collection)) {
      if (row['id'] == id) return row;
    }

    throw const ApiException('The requested record was not found.');
  }

  void _put(String collection, int id, Json input) {
    if (id != 0) _existing(collection, id);

    final savedId = id == 0 ? _newRecordId() : id;

    _account[collection] = [
      ..._rows(collection).where((row) => row['id'] != savedId),
      {'id': savedId, ...input},
    ];
  }

  Future<void> _delete(String collection, int id) {
    return _run<void>(() {
      _existing(collection, id);

      _account[collection] = _rows(
        collection,
      ).where((row) => row['id'] != id).toList();
    }, save: true);
  }

  ExpenseCategory _checkCategory(
    int id, {
    int? existingCategoryId,
    bool expenseOnly = false,
  }) {
    final category = _data().category(id);

    if (category.isArchived && id != existingCategoryId) {
      throw const ApiException('Choose an active category.');
    }

    if (expenseOnly && category.type != expenseType) {
      throw const ApiException('Budgets require an expense category.');
    }

    return category;
  }

  Future<void> saveCategory(ExpenseCategory value) {
    return _run<void>(() {
      _validateText(value.name, 'a category name', 40);

      if (value.type != incomeType && value.type != expenseType) {
        throw const ApiException('Choose income or expense.');
      }

      final data = _data();

      if (data.categories.any(
        (category) =>
            category.id != value.id &&
            category.type == value.type &&
            category.name.toLowerCase() == value.name.trim().toLowerCase(),
      )) {
        throw const ApiException('This category name already exists.');
      }

      if (value.id != 0) {
        final old = data.category(value.id);

        final referenced =
            data.categoryHasTransactions(value.id) ||
            data.budgets.any((item) => item.categoryId == value.id) ||
            data.templates.any((item) => item.categoryId == value.id);

        if (referenced && old.type != value.type) {
          throw const ApiException(
            'The category type cannot change while records use it.',
          );
        }
      }

      _put('categories', value.id, value.toInput());
    }, save: true);
  }

  Future<void> saveTransaction(MoneyTransaction value) {
    return _run<void>(() {
      _validateAmount(value.amountPaisa);
      _validateText(value.note, 'the note', 250, optional: true);

      final old = _existing('transactions', value.id);

      _checkCategory(
        value.categoryId,
        existingCategoryId: old?['category_id'] as int?,
      );

      _put('transactions', value.id, value.toInput());
    }, save: true);
  }

  Future<void> deleteTransaction(int id) => _delete('transactions', id);

  Future<void> saveBudget(MonthlyBudget value) {
    return _run<void>(() {
      _validateAmount(value.limitPaisa);

      final old = _existing('budgets', value.id);

      _checkCategory(
        value.categoryId,
        existingCategoryId: old?['category_id'] as int?,
        expenseOnly: true,
      );

      if (_data().budgets.any(
        (budget) =>
            budget.id != value.id &&
            budget.categoryId == value.categoryId &&
            sameMonth(budget.month, value.month),
      )) {
        throw const ApiException(
          'This category already has a budget for that month.',
        );
      }

      _put('budgets', value.id, value.toInput());
    }, save: true);
  }

  Future<void> deleteBudget(int id) => _delete('budgets', id);

  Future<void> saveReminder(BillReminder value) {
    return _run<void>(() {
      _validateText(value.title, 'a reminder title', 120);

      if (value.repeatType != 'once' && value.repeatType != 'monthly') {
        throw const ApiException('Choose a valid reminder repeat option.');
      }

      if (value.isEnabled &&
          !value.isMonthly &&
          !value.scheduledAt.isAfter(DateTime.now())) {
        throw const ApiException('Choose a future reminder time.');
      }

      _put('reminders', value.id, value.toInput());
    }, save: true);
  }

  Future<void> deleteReminder(int id) => _delete('reminders', id);

  Future<void> saveTemplate(QuickTemplate value) {
    return _run<void>(() {
      _validateText(value.name, 'a template name', 60);
      _validateText(value.note, 'the note', 250, optional: true);
      _validateAmount(value.amountPaisa);
      _checkCategory(value.categoryId);

      _put('templates', value.id, value.toInput());
    }, save: true);
  }

  Future<void> deleteTemplate(int id) => _delete('templates', id);

  Future<void> updateProfile({
    required String fullName,
    required bool remindersEnabled,
  }) {
    return _run<void>(() {
      _validateText(fullName, 'your name', 80);

      final user = _account['user'] as Json;
      user['full_name'] = fullName.trim();
      user['reminders_enabled'] = remindersEnabled;
    }, save: true);
  }

  Future<void> changePassword(String currentPassword, String newPassword) {
    return _run<void>(() async {
      final account = _account;

      if (!await _passwordMatches(
        account['credential'] as Json,
        currentPassword,
      )) {
        throw const ApiException('Your current password is incorrect.');
      }

      _validatePassword(newPassword);

      if (currentPassword == newPassword) {
        throw const ApiException('Choose a different new password.');
      }

      account['credential'] = await _makeCredential(newPassword);
      _root['active_user_id'] = null;
    }, save: true);
  }
}
