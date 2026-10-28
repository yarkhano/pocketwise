import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'models.dart';

class ApiException implements Exception {
  final String message;

  const ApiException(this.message);

  @override
  String toString() => message;
}

class Api {
  static const baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000/api/v1',
  );

  static const _sessionKey = 'pocketwise_session';

  final http.Client _client = http.Client();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  String? _accessToken;
  String? _refreshToken;
  Future<bool>? _refreshing;

  AppData? _demo;
  int _nextId = 100;

  bool get isDemo => _demo != null;

  String get serverAddress => baseUrl;

  void dispose() {
    _client.close();
  }

  Future<void> _saveSession(dynamic response) async {
    if (response is! Map) {
      throw const ApiException('Invalid authentication response.');
    }

    final access = response['access_token'];
    final refresh = response['refresh_token'];

    if (access is! String ||
        refresh is! String ||
        access.isEmpty ||
        refresh.isEmpty) {
      throw const ApiException('The server did not return valid tokens.');
    }

    // Save both values together so a rotated token pair stays consistent.
    await _storage.write(
      key: _sessionKey,
      value: jsonEncode({
        'access_token': access,
        'refresh_token': refresh,
      }),
    );

    _accessToken = access;
    _refreshToken = refresh;
  }

  Future<void> _clearSession() async {
    _accessToken = null;
    _refreshToken = null;
    await _storage.delete(key: _sessionKey);
  }

  // Reads the saved session. HomeScreen verifies it by loading account data.
  Future<bool> restoreSession() async {
    final saved = await _storage.read(key: _sessionKey);

    if (saved == null) return false;

    try {
      final parsed = jsonDecode(saved) as Map<String, dynamic>;
      _accessToken = parsed['access_token'] as String?;
      _refreshToken = parsed['refresh_token'] as String?;

      if (_accessToken == null || _refreshToken == null) {
        await _clearSession();
        return false;
      }

      return true;
    } on FormatException {
      await _clearSession();
      return false;
    } on TypeError {
      await _clearSession();
      return false;
    }
  }

  Future<void> login(String email, String password) async {
    final response = await _request(
      'POST',
      '/auth/login',
      authenticated: false,
      body: {
        'email': email.trim().toLowerCase(),
        'password': password,
      },
    );

    await _saveSession(response);
    _demo = null;
  }

  Future<void> register(
    String fullName,
    String email,
    String password,
  ) async {
    await _request(
      'POST',
      '/auth/register',
      authenticated: false,
      body: {
        'full_name': fullName.trim(),
        'email': email.trim().toLowerCase(),
        'password': password,
      },
    );
  }

  // Returns a warning if server revocation could not be confirmed.
  // Local credentials are still removed.
  Future<String?> logout() async {
    if (isDemo) {
      _demo = null;
      return null;
    }

    String? warning;

    try {
      if (_refreshToken != null) {
        await _request(
          'POST',
          '/auth/logout',
          authenticated: false,
          body: {'refresh_token': _refreshToken},
        );
      }
    } catch (_) {
      warning =
          'Signed out on this device. Server session revocation could not '
          'be confirmed because the server was unavailable.';
    } finally {
      await _clearSession();
    }

    return warning;
  }

  Future<bool> _refreshSession() {
    final existing = _refreshing;

    if (existing != null) return existing;

    final future = _performRefresh();
    _refreshing = future;

    return future.whenComplete(() {
      if (identical(_refreshing, future)) {
        _refreshing = null;
      }
    });
  }

  Future<bool> _performRefresh() async {
    final token = _refreshToken;

    if (token == null) return false;

    try {
      final response = await _request(
        'POST',
        '/auth/refresh',
        authenticated: false,
        body: {'refresh_token': token},
      );

      await _saveSession(response);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<dynamic> _request(
    String method,
    String path, {
    Json? body,
    Map<String, String>? query,
    bool authenticated = true,
    bool retry = true,
  }) async {
    final normalizedBase = baseUrl.replaceFirst(RegExp(r'/$'), '');
    final uri = Uri.parse('$normalizedBase$path').replace(
      queryParameters: query,
    );

    final request = http.Request(method, uri);

    request.headers['Accept'] = 'application/json';

    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }

    if (authenticated && _accessToken != null) {
      request.headers['Authorization'] = 'Bearer $_accessToken';
    }

    http.Response response;

    try {
      response = await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw const ApiException(
        'The request timed out. Check your connection and try again.',
      );
    } on http.ClientException {
      throw const ApiException(
        'Cannot reach the server. Use demo mode until FastAPI is running.',
      );
    }

    if (response.statusCode == 401 &&
        authenticated &&
        retry &&
        await _refreshSession()) {
      return _request(
        method,
        path,
        body: body,
        query: query,
        authenticated: authenticated,
        retry: false,
      );
    }

    dynamic decoded;

    if (response.body.trim().isNotEmpty) {
      try {
        decoded = jsonDecode(response.body);
      } on FormatException {
        if (response.statusCode < 400) {
          throw const ApiException('The server returned an invalid response.');
        }
      }
    }

    if (response.statusCode >= 400) {
      if (response.statusCode == 401) {
        throw ApiException(
          authenticated
              ? 'Your session could not be verified. Please sign out and log in.'
              : 'The email, password, or session is invalid.',
        );
      }

      if (response.statusCode >= 500) {
        throw const ApiException(
          'The server could not complete the request. Please try again.',
        );
      }

      final detail = decoded is Map ? decoded['detail'] : null;

      if (detail is String) throw ApiException(detail);

      if (detail is List) {
        final messages = detail
            .whereType<Map>()
            .map((item) => item['msg']?.toString() ?? 'Invalid input.')
            .join('\n');

        if (messages.isNotEmpty) throw ApiException(messages);
      }

      throw ApiException('Request failed (${response.statusCode}).');
    }

    return decoded;
  }

  // Planned list response:
  // {"items": [...], "total": 25}
  //
  // Fetches all pages so frontend summaries never use a partial list.
  Future<List<Json>> _all(
    String path, {
    Map<String, String> query = const {},
  }) async {
    const limit = 200;
    final result = <Json>[];

    while (true) {
      final response = await _request(
        'GET',
        path,
        query: {
          ...query,
          'limit': '$limit',
          'offset': '${result.length}',
        },
      );

      if (response is! Map ||
          response['items'] is! List ||
          response['total'] is! int) {
        throw const ApiException('Invalid list response from the server.');
      }

      final rows = (response['items'] as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();

      final total = response['total'] as int;

      result.addAll(rows);

      if (result.length >= total) return result;

      if (rows.isEmpty) {
        throw const ApiException('The server returned incomplete data.');
      }
    }
  }

  Future<AppData> loadData() async {
    if (_demo != null) return _demo!;

    // Sequential requests keep authentication refresh behavior simple.
    final profile = await _request('GET', '/users/me');
    final categories = await _all(
      '/categories',
      query: {'include_archived': 'true'},
    );
    final transactions = await _all('/transactions');
    final budgets = await _all('/budgets');
    final reminders = await _all('/reminders');
    final templates = await _all('/templates');

    return AppData(
      user: UserProfile.fromJson(
        Map<String, dynamic>.from(profile as Map),
      ),
      categories: categories.map(ExpenseCategory.fromJson).toList(),
      transactions: transactions.map(MoneyTransaction.fromJson).toList(),
      budgets: budgets.map(MonthlyBudget.fromJson).toList(),
      reminders: reminders.map(BillReminder.fromJson).toList(),
      templates: templates.map(QuickTemplate.fromJson).toList(),
    );
  }

  Future<void> saveCategory(ExpenseCategory value) async {
    final name = value.name.trim();

    if (name.isEmpty) {
      throw const ApiException('Enter a category name.');
    }

    if (value.type != incomeType && value.type != expenseType) {
      throw const ApiException('Choose income or expense.');
    }

    if (!isDemo) {
      await _request(
        value.id == 0 ? 'POST' : 'PATCH',
        value.id == 0 ? '/categories' : '/categories/${value.id}',
        body: value.toInput(),
      );
      return;
    }

    final data = _demo!;

    if (data.categories.any(
      (item) =>
          item.id != value.id &&
          item.type == value.type &&
          item.name.toLowerCase() == name.toLowerCase(),
    )) {
      throw const ApiException('This category name already exists.');
    }

    if (value.id != 0) {
      final old = data.category(value.id);
      final referenced = data.categoryHasTransactions(value.id) ||
          data.budgets.any((item) => item.categoryId == value.id) ||
          data.templates.any((item) => item.categoryId == value.id);

      if (referenced && old.type != value.type) {
        throw const ApiException(
          'The type cannot change while this category is used by records.',
        );
      }
    }

    final saved = ExpenseCategory(
      id: value.id == 0 ? _nextId++ : value.id,
      name: name,
      type: value.type,
      iconKey: value.iconKey,
      colorValue: value.colorValue,
      isArchived: value.isArchived,
    );

    _update(
      categories: [
        ...data.categories.where((item) => item.id != saved.id),
        saved,
      ],
    );
  }

  ExpenseCategory _validateCategory(
    int categoryId, {
    int? existingCategoryId,
    bool expenseOnly = false,
  }) {
    final category = _demo!.category(categoryId);

    if (category.isArchived && categoryId != existingCategoryId) {
      throw const ApiException('Choose an active category.');
    }

    if (expenseOnly && category.type != expenseType) {
      throw const ApiException('Budgets require an expense category.');
    }

    return category;
  }

  Future<void> saveTransaction(MoneyTransaction value) async {
    if (value.amountPaisa <= 0 ||
        value.amountPaisa > maximumAmountPaisa) {
      throw const ApiException('Enter a valid positive amount.');
    }

    if (!isDemo) {
      await _request(
        value.id == 0 ? 'POST' : 'PATCH',
        value.id == 0 ? '/transactions' : '/transactions/${value.id}',
        body: value.toInput(),
      );
      return;
    }

    final data = _demo!;
    final old = data.transactions.where((item) => item.id == value.id);

    _validateCategory(
      value.categoryId,
      existingCategoryId: old.isEmpty ? null : old.first.categoryId,
    );

    final saved = MoneyTransaction(
      id: value.id == 0 ? _nextId++ : value.id,
      categoryId: value.categoryId,
      amountPaisa: value.amountPaisa,
      date: dateOnly(value.date),
      note: value.note.trim(),
    );

    _update(
      transactions: [
        ...data.transactions.where((item) => item.id != saved.id),
        saved,
      ],
    );
  }

  Future<void> deleteTransaction(int id) async {
    if (!isDemo) {
      await _request('DELETE', '/transactions/$id');
      return;
    }

    _update(
      transactions: _demo!.transactions
          .where((item) => item.id != id)
          .toList(),
    );
  }

  Future<void> saveBudget(MonthlyBudget value) async {
    if (value.limitPaisa <= 0 ||
        value.limitPaisa > maximumAmountPaisa) {
      throw const ApiException('Enter a valid budget limit.');
    }

    if (!isDemo) {
      await _request(
        value.id == 0 ? 'POST' : 'PATCH',
        value.id == 0 ? '/budgets' : '/budgets/${value.id}',
        body: value.toInput(),
      );
      return;
    }

    final data = _demo!;
    final old = data.budgets.where((item) => item.id == value.id);

    _validateCategory(
      value.categoryId,
      existingCategoryId: old.isEmpty ? null : old.first.categoryId,
      expenseOnly: true,
    );

    if (data.budgets.any(
      (item) =>
          item.id != value.id &&
          item.categoryId == value.categoryId &&
          sameMonth(item.month, value.month),
    )) {
      throw const ApiException(
        'This category already has a budget for that month.',
      );
    }

    final saved = MonthlyBudget(
      id: value.id == 0 ? _nextId++ : value.id,
      categoryId: value.categoryId,
      month: monthOnly(value.month),
      limitPaisa: value.limitPaisa,
    );

    _update(
      budgets: [
        ...data.budgets.where((item) => item.id != saved.id),
        saved,
      ],
    );
  }

  Future<void> deleteBudget(int id) async {
    if (!isDemo) {
      await _request('DELETE', '/budgets/$id');
      return;
    }

    _update(
      budgets: _demo!.budgets.where((item) => item.id != id).toList(),
    );
  }

  Future<void> saveReminder(BillReminder value) async {
    if (value.title.trim().isEmpty) {
      throw const ApiException('Enter a reminder title.');
    }

    if (!isDemo) {
      await _request(
        value.id == 0 ? 'POST' : 'PATCH',
        value.id == 0 ? '/reminders' : '/reminders/${value.id}',
        body: value.toInput(),
      );
      return;
    }

    final saved = BillReminder(
      id: value.id == 0 ? _nextId++ : value.id,
      title: value.title.trim(),
      scheduledAt: value.scheduledAt,
      timezone: value.timezone,
      repeatType: value.repeatType,
      isEnabled: value.isEnabled,
    );

    _update(
      reminders: [
        ..._demo!.reminders.where((item) => item.id != saved.id),
        saved,
      ],
    );
  }

  Future<void> deleteReminder(int id) async {
    if (!isDemo) {
      await _request('DELETE', '/reminders/$id');
      return;
    }

    _update(
      reminders: _demo!.reminders.where((item) => item.id != id).toList(),
    );
  }

  Future<void> saveTemplate(QuickTemplate value) async {
    if (value.name.trim().isEmpty) {
      throw const ApiException('Enter a template name.');
    }

    if (value.amountPaisa <= 0 ||
        value.amountPaisa > maximumAmountPaisa) {
      throw const ApiException('Enter a valid amount.');
    }

    if (!isDemo) {
      await _request(
        value.id == 0 ? 'POST' : 'PATCH',
        value.id == 0 ? '/templates' : '/templates/${value.id}',
        body: value.toInput(),
      );
      return;
    }

    _validateCategory(value.categoryId);

    final saved = QuickTemplate(
      id: value.id == 0 ? _nextId++ : value.id,
      categoryId: value.categoryId,
      name: value.name.trim(),
      amountPaisa: value.amountPaisa,
      note: value.note.trim(),
    );

    _update(
      templates: [
        ..._demo!.templates.where((item) => item.id != saved.id),
        saved,
      ],
    );
  }

  Future<void> deleteTemplate(int id) async {
    if (!isDemo) {
      await _request('DELETE', '/templates/$id');
      return;
    }

    _update(
      templates: _demo!.templates.where((item) => item.id != id).toList(),
    );
  }

  Future<void> updateProfile({
    required String fullName,
    required bool remindersEnabled,
  }) async {
    if (fullName.trim().isEmpty) {
      throw const ApiException('Enter your name.');
    }

    if (!isDemo) {
      await _request(
        'PATCH',
        '/users/me',
        body: {
          'full_name': fullName.trim(),
          'reminders_enabled': remindersEnabled,
        },
      );
      return;
    }

    _update(
      user: _demo!.user.copyWith(
        fullName: fullName.trim(),
        remindersEnabled: remindersEnabled,
      ),
    );
  }

  Future<void> changePassword(
    String currentPassword,
    String newPassword,
  ) async {
    if (isDemo) {
      throw const ApiException(
        'Demo mode has no password. Connect to the backend to change a password.',
      );
    }

    await _request(
      'POST',
      '/users/me/password',
      body: {
        'current_password': currentPassword,
        'new_password': newPassword,
      },
    );

    // Backend contract: changing the password revokes existing sessions.
    await _clearSession();
  }

  void _update({
    UserProfile? user,
    List<ExpenseCategory>? categories,
    List<MoneyTransaction>? transactions,
    List<MonthlyBudget>? budgets,
    List<BillReminder>? reminders,
    List<QuickTemplate>? templates,
  }) {
    final old = _demo!;

    _demo = AppData(
      user: user ?? old.user,
      categories: categories ?? old.categories,
      transactions: transactions ?? old.transactions,
      budgets: budgets ?? old.budgets,
      reminders: reminders ?? old.reminders,
      templates: templates ?? old.templates,
    );
  }

  void enterDemo() {
    _nextId = 100;

    final now = DateTime.now();
    final month = monthOnly(now);

    _demo = AppData(
      user: const UserProfile(
        id: 1,
        fullName: 'Demo Student',
        email: 'demo@pocketwise.example',
        remindersEnabled: false,
      ),
      categories: const [
        ExpenseCategory(
          id: 1,
          name: 'Food',
          type: expenseType,
          iconKey: 'food',
          colorValue: 0xFFE76F00,
        ),
        ExpenseCategory(
          id: 2,
          name: 'Transport',
          type: expenseType,
          iconKey: 'transport',
          colorValue: 0xFF2563EB,
        ),
        ExpenseCategory(
          id: 3,
          name: 'Shopping',
          type: expenseType,
          iconKey: 'shopping',
          colorValue: 0xFF9333EA,
        ),
        ExpenseCategory(
          id: 4,
          name: 'Bills',
          type: expenseType,
          iconKey: 'bills',
          colorValue: 0xFF0891B2,
        ),
        ExpenseCategory(
          id: 5,
          name: 'Allowance',
          type: incomeType,
          iconKey: 'allowance',
          colorValue: 0xFF087F5B,
        ),
        ExpenseCategory(
          id: 6,
          name: 'Salary',
          type: incomeType,
          iconKey: 'salary',
          colorValue: 0xFF2563EB,
        ),
      ],
      transactions: [
        MoneyTransaction(
          id: 10,
          categoryId: 5,
          amountPaisa: 3000000,
          date: month,
          note: 'Monthly allowance',
        ),
        MoneyTransaction(
          id: 11,
          categoryId: 1,
          amountPaisa: 850000,
          date: dateOnly(now),
          note: 'Food spending',
        ),
        MoneyTransaction(
          id: 12,
          categoryId: 2,
          amountPaisa: 150000,
          date: dateOnly(now),
          note: 'Bus fares',
        ),
        MoneyTransaction(
          id: 13,
          categoryId: 3,
          amountPaisa: 220000,
          date: dateOnly(now),
          note: 'Stationery and supplies',
        ),
        MoneyTransaction(
          id: 14,
          categoryId: 5,
          amountPaisa: 2500000,
          date: DateTime(now.year, now.month - 1, 1),
          note: 'Previous allowance',
        ),
        MoneyTransaction(
          id: 15,
          categoryId: 1,
          amountPaisa: 750000,
          date: DateTime(now.year, now.month - 1, 5),
          note: 'Previous food spending',
        ),
      ],
      budgets: [
        MonthlyBudget(
          id: 20,
          categoryId: 1,
          month: month,
          limitPaisa: 1000000,
        ),
        MonthlyBudget(
          id: 21,
          categoryId: 2,
          month: month,
          limitPaisa: 500000,
        ),
      ],
      reminders: [],
      templates: const [
        QuickTemplate(
          id: 30,
          categoryId: 1,
          name: 'Lunch',
          amountPaisa: 35000,
          note: 'Lunch',
        ),
        QuickTemplate(
          id: 31,
          categoryId: 2,
          name: 'Bus fare',
          amountPaisa: 10000,
          note: 'Bus fare',
        ),
      ],
    );
  }
}