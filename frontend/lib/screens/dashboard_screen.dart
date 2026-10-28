import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';
import '../widgets.dart';

class DashboardScreen extends StatelessWidget {
  final AppData data;
  final DateTime month;
  final ValueChanged<DateTime> onMonthChanged;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onAddTransaction;
  final VoidCallback onViewTransactions;

  const DashboardScreen({
    super.key,
    required this.data,
    required this.month,
    required this.onMonthChanged,
    required this.onRefresh,
    required this.onAddTransaction,
    required this.onViewTransactions,
  });

  @override
  Widget build(BuildContext context) {
    final income = data.monthTotal(month, incomeType);
    final expenses = data.monthTotal(month, expenseType);
    final transactions = data.monthTransactions(month);
    final budgets = data.monthBudgets(month);

    return PageBody(
      onRefresh: onRefresh,
      children: [
        Text(
          'Hello, ${data.user.fullName}',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 6),
        const Text('Your monthly spending at a glance.'),
        const SizedBox(height: 16),
        MonthSelector(
          month: month,
          onChanged: onMonthChanged,
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final cardWidth = width >= 550
                ? (width - 24) / 3
                : width;

            return Wrap(
              spacing: 12,
              children: [
                SizedBox(
                  width: cardWidth,
                  child: _SummaryCard(
                    label: 'Income',
                    amount: income,
                    color: incomeColor,
                    icon: Icons.south_west,
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: _SummaryCard(
                    label: 'Expenses',
                    amount: expenses,
                    color: expenseColor,
                    icon: Icons.north_east,
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: _SummaryCard(
                    label: 'Net amount',
                    amount: income - expenses,
                    color: brandColor,
                    icon: Icons.account_balance_wallet_outlined,
                  ),
                ),
              ],
            );
          },
        ),
        const Text(
          'Net amount is recorded income minus expenses, not a bank balance.',
          style: TextStyle(fontSize: 12, color: Colors.black54),
        ),
        const SizedBox(height: 16),
        SubmitButton(
          label: 'Add transaction',
          icon: Icons.add,
          onSubmit: onAddTransaction,
        ),
        const SectionTitle('Category budgets'),
        if (budgets.isEmpty)
          const EmptyMessage(
            title: 'No budgets for this month',
            message: 'Open Budgets to set a category spending limit.',
            icon: Icons.savings_outlined,
          ),
        for (final budget in budgets)
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.category(budget.categoryId).name,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                BudgetProgress(
                  spentPaisa: data.categoryTotal(
                    budget.categoryId,
                    month,
                  ),
                  limitPaisa: budget.limitPaisa,
                ),
              ],
            ),
          ),
        SectionTitle(
          'Recent transactions',
          trailing: TextButton(
            onPressed: onViewTransactions,
            child: const Text('View all'),
          ),
        ),
        if (transactions.isEmpty)
          const EmptyMessage(
            title: 'No transactions yet',
            message: 'Add your first income or expense for this month.',
          )
        else
          Panel(
            child: Column(
              children: [
                for (final transaction in transactions.take(5))
                  TransactionRow(
                    transaction: transaction,
                    category: data.category(transaction.categoryId),
                    onTap: onViewTransactions,
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final int amount;
  final Color color;
  final IconData icon;

  const _SummaryCard({
    required this.label,
    required this.amount,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(height: 12),
          Text(label),
          const SizedBox(height: 6),
          Text(
            formatMoney(amount),
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}