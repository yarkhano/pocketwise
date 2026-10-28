import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';

Future<bool> openTransactionForm(
  BuildContext context, {
  required Api api,
  required AppData data,
  MoneyTransaction? transaction,
  QuickTemplate? template,
}) async {
  final result = await Navigator.push<bool>(
    context,
    MaterialPageRoute(
      builder: (_) => _TransactionForm(
        api: api,
        data: data,
        transaction: transaction,
        template: template,
      ),
    ),
  );

  return result ?? false;
}

class TransactionsScreen extends StatefulWidget {
  final Api api;
  final AppData data;
  final Future<void> Function() onChanged;

  const TransactionsScreen({
    super.key,
    required this.api,
    required this.data,
    required this.onChanged,
  });

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  final searchController = TextEditingController();

  String type = 'all';
  int? categoryId;
  DateTimeRange? range;

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  List<MoneyTransaction> get filtered {
    final query = searchController.text.trim().toLowerCase();

    return widget.data.transactions.where((item) {
      final category = widget.data.category(item.categoryId);

      if (type != 'all' && category.type != type) return false;
      if (categoryId != null && item.categoryId != categoryId) return false;
      if (query.isNotEmpty && !item.note.toLowerCase().contains(query)) {
        return false;
      }

      if (range != null) {
        final date = dateOnly(item.date);

        if (date.isBefore(dateOnly(range!.start)) ||
            date.isAfter(dateOnly(range!.end))) {
          return false;
        }
      }

      return true;
    }).toList()
      ..sort((first, second) {
        final dateOrder = second.date.compareTo(first.date);
        return dateOrder != 0 ? dateOrder : second.id.compareTo(first.id);
      });
  }

  Future<void> addOrEdit([MoneyTransaction? transaction]) async {
    final saved = await openTransactionForm(
      context,
      api: widget.api,
      data: widget.data,
      transaction: transaction,
    );

    if (saved) await widget.onChanged();
  }

  Future<void> selectDates() async {
    final selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100, 12, 31),
      initialDateRange: range,
    );

    if (selected != null && mounted) {
      setState(() => range = selected);
    }
  }

  Future<void> showDetails(MoneyTransaction transaction) async {
    final category = widget.data.category(transaction.categoryId);

    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(category.name),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                formatMoney(transaction.amountPaisa),
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: category.isIncome ? incomeColor : expenseColor,
                ),
              ),
              const SizedBox(height: 12),
              Text('Type: ${category.isIncome ? "Income" : "Expense"}'),
              Text('Date: ${formatDate(transaction.date)}'),
              const SizedBox(height: 10),
              Text(
                transaction.note.isEmpty
                    ? 'No note'
                    : transaction.note,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'delete'),
              child: const Text('Delete'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, 'edit'),
              child: const Text('Edit'),
            ),
          ],
        );
      },
    );

    if (!mounted) return;

    if (action == 'edit') {
      await addOrEdit(transaction);
    } else if (action == 'delete') {
      final confirmed = await confirmAction(
        context,
        title: 'Delete transaction?',
        message: 'This record will be removed and your totals will update.',
      );

      if (!confirmed || !mounted) return;

      try {
        await widget.api.deleteTransaction(transaction.id);
        await widget.onChanged();

        if (mounted) showMessage(context, 'Transaction deleted.');
      } catch (error) {
        if (mounted) showMessage(context, readableError(error));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final records = filtered;

    final categories = widget.data.categories
        .where((item) => type == 'all' || item.type == type)
        .toList();

    final selectedCategory =
        categories.any((item) => item.id == categoryId)
            ? categoryId
            : null;

    return Stack(
      children: [
        PageBody(
          onRefresh: widget.onChanged,
          children: [
            TextField(
              controller: searchController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Search transaction notes',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: searchController.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        onPressed: () {
                          searchController.clear();
                          setState(() {});
                        },
                        icon: const Icon(Icons.close),
                      ),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: type,
              decoration: const InputDecoration(labelText: 'Type'),
              items: const [
                DropdownMenuItem(value: 'all', child: Text('All types')),
                DropdownMenuItem(
                  value: expenseType,
                  child: Text('Expenses'),
                ),
                DropdownMenuItem(
                  value: incomeType,
                  child: Text('Income'),
                ),
              ],
              onChanged: (value) {
                setState(() {
                  type = value ?? 'all';
                  categoryId = null;
                });
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              key: ValueKey('$type:$selectedCategory'),
              initialValue: selectedCategory ?? -1,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Category'),
              items: [
                const DropdownMenuItem(
                  value: -1,
                  child: Text('All categories'),
                ),
                ...categories.map(
                  (item) => DropdownMenuItem(
                    value: item.id,
                    child: Text(
                      '${item.name}${item.isArchived ? " (archived)" : ""}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
              onChanged: (value) {
                setState(() {
                  categoryId = value == -1 ? null : value;
                });
              },
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: selectDates,
              icon: const Icon(Icons.date_range),
              label: Text(
                range == null
                    ? 'All dates — choose a range'
                    : '${formatDate(range!.start)} to '
                        '${formatDate(range!.end)}',
              ),
            ),
            if (range != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => setState(() => range = null),
                  child: const Text('Clear date filter'),
                ),
              ),
            SectionTitle('${records.length} transactions'),
            if (records.isEmpty)
              const EmptyMessage(
                title: 'No matching transactions',
                message: 'Try different filters or add a transaction.',
              )
            else
              Panel(
                child: Column(
                  children: [
                    for (final record in records)
                      TransactionRow(
                        transaction: record,
                        category: widget.data.category(record.categoryId),
                        onTap: () => showDetails(record),
                      ),
                  ],
                ),
              ),
          ],
        ),
        Positioned(
          bottom: 16,
          right: 16,
          child: FloatingActionButton.extended(
            heroTag: 'add_transaction',
            onPressed: () => addOrEdit(),
            icon: const Icon(Icons.add),
            label: const Text('Add'),
          ),
        ),
      ],
    );
  }
}

class _TransactionForm extends StatefulWidget {
  final Api api;
  final AppData data;
  final MoneyTransaction? transaction;
  final QuickTemplate? template;

  const _TransactionForm({
    required this.api,
    required this.data,
    this.transaction,
    this.template,
  });

  @override
  State<_TransactionForm> createState() => _TransactionFormState();
}

class _TransactionFormState extends State<_TransactionForm> {
  final formKey = GlobalKey<FormState>();

  late final TextEditingController amountController;
  late final TextEditingController noteController;

  late String type;
  late DateTime date;
  int? categoryId;

  bool busy = false;

  @override
  void initState() {
    super.initState();

    final transaction = widget.transaction;
    final template = widget.template;

    categoryId = transaction?.categoryId ?? template?.categoryId;

    type = categoryId == null
        ? expenseType
        : widget.data.category(categoryId!).type;

    date = transaction?.date ?? dateOnly(DateTime.now());

    final amount = transaction?.amountPaisa ?? template?.amountPaisa;

    amountController = TextEditingController(
      text: amount == null ? '' : decimalMoney(amount),
    );

    noteController = TextEditingController(
      text: transaction?.note ?? template?.note ?? '',
    );
  }

  @override
  void dispose() {
    amountController.dispose();
    noteController.dispose();
    super.dispose();
  }

  List<ExpenseCategory> get availableCategories {
    return widget.data.categories.where((item) {
      if (item.type != type) return false;

      // Historical archived category can remain on an existing record.
      return !item.isArchived ||
          item.id == widget.transaction?.categoryId;
    }).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  void useTemplate(QuickTemplate template) {
    final category = widget.data.category(template.categoryId);

    if (category.isArchived) {
      showMessage(context, 'This template uses an archived category.');
      return;
    }

    setState(() {
      categoryId = template.categoryId;
      type = category.type;
      amountController.text = decimalMoney(template.amountPaisa);
      noteController.text = template.note;
    });
  }

  Future<void> save() async {
    if (busy || !formKey.currentState!.validate()) return;

    setState(() => busy = true);

    try {
      await widget.api.saveTransaction(
        MoneyTransaction(
          id: widget.transaction?.id ?? 0,
          categoryId: categoryId!,
          amountPaisa: positiveMoney(amountController.text),
          date: date,
          note: noteController.text,
        ),
      );

      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) showMessage(context, readableError(error));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final templates = widget.data.templates.where(
      (item) => !widget.data.category(item.categoryId).isArchived,
    );

    return PopScope(
      canPop: !busy,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.transaction == null ? 'Add transaction' : 'Edit transaction',
          ),
        ),
        body: SafeArea(
          child: AbsorbPointer(
            absorbing: busy,
            child: Form(
              key: formKey,
              child: PageBody(
                children: [
                  if (widget.transaction == null && templates.isNotEmpty) ...[
                    const SectionTitle('Quick templates'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: templates.map((item) {
                        return ActionChip(
                          avatar: const Icon(Icons.bolt, size: 18),
                          label: Text(item.name),
                          onPressed: () => useTemplate(item),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 18),
                  ],
                  TransactionTypeField(
                    value: type,
                    onChanged: (value) {
                      setState(() {
                        type = value;
                        categoryId = null;
                      });
                    },
                  ),
                  const SizedBox(height: 18),
                  AmountField(controller: amountController),
                  const SizedBox(height: 16),
                  CategoryField(
                    categories: availableCategories,
                    value: categoryId,
                    onChanged: (value) {
                      setState(() => categoryId = value);
                    },
                  ),
                  if (availableCategories.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'Create an active category in Settings → Categories.',
                      ),
                    ),
                  const SizedBox(height: 16),
                  DateField(
                    value: date,
                    onChanged: (value) => setState(() => date = value),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: noteController,
                    maxLength: 250,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Note (optional)',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Review the details before saving. Selecting a template '
                    'does not save a transaction automatically.',
                    style: TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: busy ? null : save,
                    child: busy
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Save transaction'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}