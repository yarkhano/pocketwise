typedef Json = Map<String, dynamic>;

// PostgreSQL NUMERIC(14,2): maximum amount expressed in paisa.
const int maximumAmountPaisa = 99999999999999;

const String incomeType = 'income';
const String expenseType = 'expense';

int readId(dynamic value) {
  if (value is int) return value;

  final result = int.tryParse(value.toString());

  if (result == null) {
    throw const FormatException('Invalid record ID.');
  }

  return result;
}

// Converts "1250.50" to 125050 without floating-point arithmetic.
int parseMoney(String value) {
  final text = value.trim();

  if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(text)) {
    throw const FormatException(
      'Enter an amount such as 350 or 350.50.',
    );
  }

  final parts = text.split('.');
  final whole = BigInt.parse(parts[0]);
  final fraction = parts.length == 2
      ? parts[1].padRight(2, '0')
      : '00';

  final amount = whole * BigInt.from(100) + BigInt.parse(fraction);

  if (amount > BigInt.from(maximumAmountPaisa)) {
    throw const FormatException('The amount is too large.');
  }

  return amount.toInt();
}

int positiveMoney(String value) {
  final amount = parseMoney(value);

  if (amount <= 0) {
    throw const FormatException('Amount must be greater than zero.');
  }

  return amount;
}

// Our API contract sends monetary values as decimal strings.
int readMoney(dynamic value) {
  if (value is! String) {
    throw const FormatException(
      'The server must return amounts as decimal strings.',
    );
  }

  return parseMoney(value);
}

String decimalMoney(int paisa) {
  final sign = paisa < 0 ? '-' : '';
  final absolute = paisa.abs();
  final whole = absolute ~/ 100;
  final fraction = (absolute % 100).toString().padLeft(2, '0');

  return '$sign$whole.$fraction';
}

String formatMoney(int paisa) {
  final sign = paisa < 0 ? '-' : '';
  final absolute = paisa.abs();
  final whole = (absolute ~/ 100).toString();
  final fraction = (absolute % 100).toString().padLeft(2, '0');

  final grouped = whole.replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (match) => '${match[1]},',
  );

  return '${sign}PKR $grouped.$fraction';
}

DateTime dateOnly(DateTime value) {
  return DateTime(value.year, value.month, value.day);
}

DateTime monthOnly(DateTime value) {
  return DateTime(value.year, value.month);
}

bool sameMonth(DateTime first, DateTime second) {
  return first.year == second.year && first.month == second.month;
}

String dateToApi(DateTime value) {
  final year = value.year.toString().padLeft(4, '0');
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');

  return '$year-$month-$day';
}

String monthToApi(DateTime value) {
  return dateToApi(monthOnly(value));
}

const List<String> monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

String formatMonth(DateTime value) {
  return '${monthNames[value.month - 1]} ${value.year}';
}

String formatDate(DateTime value) {
  return '${value.day} ${monthNames[value.month - 1]} ${value.year}';
}

String formatDateTime(DateTime value) {
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');

  return '${formatDate(value)} • $hour:$minute';
}

class UserProfile {
  final int id;
  final String fullName;
  final String email;
  final bool remindersEnabled;

  const UserProfile({
    required this.id,
    required this.fullName,
    required this.email,
    this.remindersEnabled = true,
  });

  factory UserProfile.fromJson(Json json) {
    return UserProfile(
      id: readId(json['id']),
      fullName: json['full_name'] as String,
      email: json['email'] as String,
      remindersEnabled: json['reminders_enabled'] as bool? ?? true,
    );
  }

  UserProfile copyWith({
    String? fullName,
    bool? remindersEnabled,
  }) {
    return UserProfile(
      id: id,
      fullName: fullName ?? this.fullName,
      email: email,
      remindersEnabled: remindersEnabled ?? this.remindersEnabled,
    );
  }
}

class ExpenseCategory {
  final int id;
  final String name;
  final String type;
  final String iconKey;
  final int colorValue;
  final bool isArchived;

  const ExpenseCategory({
    required this.id,
    required this.name,
    required this.type,
    this.iconKey = 'other',
    this.colorValue = 0xFF2563EB,
    this.isArchived = false,
  });

  bool get isIncome => type == incomeType;

  factory ExpenseCategory.fromJson(Json json) {
    return ExpenseCategory(
      id: readId(json['id']),
      name: json['name'] as String,
      type: json['type'] as String,
      iconKey: json['icon_key'] as String? ?? 'other',
      colorValue: json['color_value'] == null
          ? 0xFF2563EB
          : readId(json['color_value']),
      isArchived: json['is_archived'] as bool? ?? false,
    );
  }

  Json toInput() {
    return {
      'name': name.trim(),
      'type': type,
      'icon_key': iconKey,
      'color_value': colorValue,
      'is_archived': isArchived,
    };
  }

  ExpenseCategory copyWith({
    String? name,
    String? type,
    String? iconKey,
    int? colorValue,
    bool? isArchived,
  }) {
    return ExpenseCategory(
      id: id,
      name: name ?? this.name,
      type: type ?? this.type,
      iconKey: iconKey ?? this.iconKey,
      colorValue: colorValue ?? this.colorValue,
      isArchived: isArchived ?? this.isArchived,
    );
  }
}

class MoneyTransaction {
  final int id;
  final int categoryId;
  final int amountPaisa;
  final DateTime date;
  final String note;

  const MoneyTransaction({
    required this.id,
    required this.categoryId,
    required this.amountPaisa,
    required this.date,
    this.note = '',
  });

  factory MoneyTransaction.fromJson(Json json) {
    return MoneyTransaction(
      id: readId(json['id']),
      categoryId: readId(json['category_id']),
      amountPaisa: readMoney(json['amount']),
      date: DateTime.parse(json['transaction_date'] as String),
      note: json['note'] as String? ?? '',
    );
  }

  Json toInput() {
    return {
      'category_id': categoryId,
      'amount': decimalMoney(amountPaisa),
      'transaction_date': dateToApi(date),
      'note': note.trim(),
    };
  }
}

class MonthlyBudget {
  final int id;
  final int categoryId;
  final DateTime month;
  final int limitPaisa;

  const MonthlyBudget({
    required this.id,
    required this.categoryId,
    required this.month,
    required this.limitPaisa,
  });

  factory MonthlyBudget.fromJson(Json json) {
    return MonthlyBudget(
      id: readId(json['id']),
      categoryId: readId(json['category_id']),
      month: DateTime.parse(json['month_start'] as String),
      limitPaisa: readMoney(json['limit_amount']),
    );
  }

  Json toInput() {
    return {
      'category_id': categoryId,
      'month_start': monthToApi(month),
      'limit_amount': decimalMoney(limitPaisa),
    };
  }
}

class BillReminder {
  final int id;
  final String title;

  // Absolute instant. Display and scheduling use the stored timezone.
  final DateTime scheduledAt;
  final String timezone;
  final String repeatType;
  final bool isEnabled;

  const BillReminder({
    required this.id,
    required this.title,
    required this.scheduledAt,
    required this.timezone,
    this.repeatType = 'once',
    this.isEnabled = true,
  });

  bool get isMonthly => repeatType == 'monthly';

  factory BillReminder.fromJson(Json json) {
    return BillReminder(
      id: readId(json['id']),
      title: json['title'] as String,
      scheduledAt: DateTime.parse(json['scheduled_at'] as String),
      timezone: json['timezone'] as String,
      repeatType: json['repeat_type'] as String? ?? 'once',
      isEnabled: json['is_enabled'] as bool? ?? true,
    );
  }

  Json toInput() {
    return {
      'title': title.trim(),
      'scheduled_at': scheduledAt.toUtc().toIso8601String(),
      'timezone': timezone,
      'repeat_type': repeatType,
      'is_enabled': isEnabled,
    };
  }

  BillReminder copyWith({bool? isEnabled}) {
    return BillReminder(
      id: id,
      title: title,
      scheduledAt: scheduledAt,
      timezone: timezone,
      repeatType: repeatType,
      isEnabled: isEnabled ?? this.isEnabled,
    );
  }
}

class QuickTemplate {
  final int id;
  final int categoryId;
  final String name;
  final int amountPaisa;
  final String note;

  const QuickTemplate({
    required this.id,
    required this.categoryId,
    required this.name,
    required this.amountPaisa,
    this.note = '',
  });

  factory QuickTemplate.fromJson(Json json) {
    return QuickTemplate(
      id: readId(json['id']),
      categoryId: readId(json['category_id']),
      name: json['name'] as String,
      amountPaisa: readMoney(json['amount']),
      note: json['note'] as String? ?? '',
    );
  }

  Json toInput() {
    return {
      'category_id': categoryId,
      'name': name.trim(),
      'amount': decimalMoney(amountPaisa),
      'note': note.trim(),
    };
  }
}

// Shared frontend data. Server mode will load this through api.dart.
// Demo mode will supply sample records using the same models.
class AppData {
  final UserProfile user;
  final List<ExpenseCategory> categories;
  final List<MoneyTransaction> transactions;
  final List<MonthlyBudget> budgets;
  final List<BillReminder> reminders;
  final List<QuickTemplate> templates;

  AppData({
    required this.user,
    required List<ExpenseCategory> categories,
    required List<MoneyTransaction> transactions,
    required List<MonthlyBudget> budgets,
    required List<BillReminder> reminders,
    required List<QuickTemplate> templates,
  })  : categories = List.unmodifiable(categories),
        transactions = List.unmodifiable(transactions),
        budgets = List.unmodifiable(budgets),
        reminders = List.unmodifiable(reminders),
        templates = List.unmodifiable(templates);

  ExpenseCategory category(int id) {
    return categories.firstWhere(
      (item) => item.id == id,
      orElse: () => throw StateError('Category $id was not found.'),
    );
  }

  List<ExpenseCategory> activeCategories([String? type]) {
    return categories
        .where(
          (item) =>
              !item.isArchived && (type == null || item.type == type),
        )
        .toList()
      ..sort(
        (first, second) =>
            first.name.toLowerCase().compareTo(second.name.toLowerCase()),
      );
  }

  List<MoneyTransaction> monthTransactions(DateTime month) {
    return transactions.where((item) => sameMonth(item.date, month)).toList()
      ..sort((first, second) {
        final byDate = second.date.compareTo(first.date);
        return byDate != 0 ? byDate : second.id.compareTo(first.id);
      });
  }

  int monthTotal(DateTime month, String type) {
    var total = 0;

    for (final item in transactions) {
      if (sameMonth(item.date, month) &&
          category(item.categoryId).type == type) {
        total += item.amountPaisa;
      }
    }

    return total;
  }

  int categoryTotal(int categoryId, DateTime month) {
    var total = 0;

    for (final item in transactions) {
      if (item.categoryId == categoryId &&
          sameMonth(item.date, month)) {
        total += item.amountPaisa;
      }
    }

    return total;
  }

  List<MonthlyBudget> monthBudgets(DateTime month) {
    return budgets.where((item) => sameMonth(item.month, month)).toList();
  }

  bool categoryHasTransactions(int categoryId) {
    return transactions.any((item) => item.categoryId == categoryId);
  }
}