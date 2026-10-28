import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';

class BudgetsScreen extends StatefulWidget {
  const BudgetsScreen({
    super.key,
    required this.api,
    required this.data,
    required this.month,
    required this.onMonthChanged,
    required this.onChanged,
  });

  final Api api;
  final AppData data;
  final DateTime month;
  final ValueChanged<DateTime> onMonthChanged;
  final Future<void> Function() onChanged;

  @override
  State<BudgetsScreen> createState() => _BudgetsScreenState();
}

class _BudgetsScreenState extends State<BudgetsScreen> {
  bool deleting = false;

  Future<void> edit([MonthlyBudget? budget]) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _BudgetForm(
          api: widget.api,
          data: widget.data,
          month: widget.month,
          budget: budget,
        ),
      ),
    );

    if (saved == true && mounted) {
      await widget.onChanged();
    }
  }

  Future<void> remove(MonthlyBudget budget) async {
    if (deleting) return;

    final confirmed = await confirmAction(
      context,
      title: 'Delete budget?',
      message: 'Your transactions will remain unchanged.',
    );

    if (!confirmed || !mounted) return;

    setState(() => deleting = true);

    try {
      await widget.api.deleteBudget(budget.id);
      await widget.onChanged();

      if (mounted) showMessage(context, 'Budget deleted.');
    } catch (error) {
      if (mounted) showMessage(context, readableError(error));
    } finally {
      if (mounted) setState(() => deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final budgets = widget.data.monthBudgets(widget.month).toList()
      ..sort(
        (a, b) => widget.data
            .category(a.categoryId)
            .name
            .compareTo(widget.data.category(b.categoryId).name),
      );

    final total = budgets.fold<int>(
      0,
      (sum, budget) => sum + budget.limitPaisa,
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: PageBody(
        onRefresh: widget.onChanged,
        children: [
          MonthSelector(
            month: widget.month,
            onChanged: widget.onMonthChanged,
          ),
          const SizedBox(height: 16),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Total category budgets'),
                const SizedBox(height: 8),
                Text(
                  formatMoney(total),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Set one budget per expense category each month. '
                  'Warnings appear at 80% and 100% of the limit.',
                ),
              ],
            ),
          ),
          if (deleting) const LinearProgressIndicator(),
          if (budgets.isEmpty)
            const EmptyMessage(
              title: 'No budgets this month',
              message: 'Add a budget to track spending against a limit.',
              icon: Icons.savings_outlined,
            ),
          for (final budget in budgets)
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        categoryIcon(
                          widget.data.category(budget.categoryId).iconKey,
                        ),
                        color: Color(
                          widget.data.category(budget.categoryId).colorValue,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          widget.data.category(budget.categoryId).name,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      PopupMenuButton<String>(
                        enabled: !deleting,
                        onSelected: (action) {
                          if (action == 'edit') {
                            edit(budget);
                          } else {
                            remove(budget);
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'edit',
                            child: Text('Edit'),
                          ),
                          PopupMenuItem(
                            value: 'delete',
                            child: Text('Delete'),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  BudgetProgress(
                    spentPaisa: widget.data.categoryTotal(
                      budget.categoryId,
                      widget.month,
                    ),
                    limitPaisa: budget.limitPaisa,
                  ),
                ],
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: deleting ? null : () => edit(),
        icon: const Icon(Icons.add),
        label: const Text('Add budget'),
      ),
    );
  }
}

class _BudgetForm extends StatefulWidget {
  const _BudgetForm({
    required this.api,
    required this.data,
    required this.month,
    this.budget,
  });

  final Api api;
  final AppData data;
  final DateTime month;
  final MonthlyBudget? budget;

  @override
  State<_BudgetForm> createState() => _BudgetFormState();
}

class _BudgetFormState extends State<_BudgetForm> {
  final formKey = GlobalKey<FormState>();
  late final TextEditingController amount;

  late DateTime month;
  int? categoryId;
  bool busy = false;

  @override
  void initState() {
    super.initState();

    final budget = widget.budget;

    month = monthOnly(budget?.month ?? widget.month);
    categoryId = budget?.categoryId;

    amount = TextEditingController(
      text: budget == null ? '' : decimalMoney(budget.limitPaisa),
    );
  }

  @override
  void dispose() {
    amount.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (!formKey.currentState!.validate()) return;

    final duplicate = widget.data.budgets.any(
      (budget) =>
          budget.id != widget.budget?.id &&
          budget.categoryId == categoryId &&
          sameMonth(budget.month, month),
    );

    if (duplicate) {
      showMessage(
        context,
        'This category already has a budget for this month.',
      );
      return;
    }

    setState(() => busy = true);

    try {
      await widget.api.saveBudget(
        MonthlyBudget(
          id: widget.budget?.id ?? 0,
          categoryId: categoryId!,
          month: monthOnly(month),
          limitPaisa: positiveMoney(amount.text),
        ),
      );

      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) showMessage(context, readableError(error));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = widget.data.categories
        .where(
          (category) =>
              category.type == expenseType &&
              (!category.isArchived ||
                  category.id == widget.budget?.categoryId),
        )
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    return PopScope(
      canPop: !busy,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.budget == null ? 'Add budget' : 'Edit budget'),
        ),
        body: AbsorbPointer(
          absorbing: busy,
          child: Form(
            key: formKey,
            child: PageBody(
              children: [
                MonthSelector(
                  month: month,
                  onChanged: (value) => setState(() => month = value),
                ),
                const SizedBox(height: 20),
                CategoryField(
                  categories: categories,
                  value: categoryId,
                  onChanged: (value) => setState(() => categoryId = value),
                ),
                const SizedBox(height: 16),
                AmountField(
                  controller: amount,
                  label: 'Monthly limit',
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: busy ? null : save,
                  child: Text(busy ? 'Saving...' : 'Save budget'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}