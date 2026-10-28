import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';
import '../widgets.dart';

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({
    super.key,
    required this.data,
    required this.month,
    required this.onMonthChanged,
    required this.onRefresh,
  });

  final AppData data;
  final DateTime month;
  final ValueChanged<DateTime> onMonthChanged;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final income = data.monthTotal(month, incomeType);
    final expenses = data.monthTotal(month, expenseType);

    final categoryTotals = <int, int>{};

    for (final transaction in data.monthTransactions(month)) {
      if (data.category(transaction.categoryId).type == expenseType) {
        categoryTotals.update(
          transaction.categoryId,
          (amount) => amount + transaction.amountPaisa,
          ifAbsent: () => transaction.amountPaisa,
        );
      }
    }

    final spending = categoryTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final months = List.generate(
      6,
      (index) => DateTime(month.year, month.month - 5 + index),
    );

    var maximum = 1;

    for (final item in months) {
      maximum = math.max(maximum, data.monthTotal(item, incomeType));
      maximum = math.max(maximum, data.monthTotal(item, expenseType));
    }

    return PageBody(
      onRefresh: onRefresh,
      children: [
        MonthSelector(
          month: month,
          onChanged: onMonthChanged,
        ),
        const SizedBox(height: 16),
        Panel(
          child: Column(
            children: [
              _TotalRow(
                title: 'Income',
                amount: income,
                color: incomeColor,
              ),
              _TotalRow(
                title: 'Expenses',
                amount: expenses,
                color: expenseColor,
              ),
              const Divider(),
              _TotalRow(
                title: 'Net this month',
                amount: income - expenses,
                color: income >= expenses ? incomeColor : expenseColor,
              ),
              const SizedBox(height: 8),
              const Text(
                'Net means recorded income minus recorded expenses.',
              ),
            ],
          ),
        ),
        const SectionTitle('Spending by category'),
        if (spending.isEmpty)
          const EmptyMessage(
            title: 'No expenses to display',
            message: 'Add expenses to see your category report.',
            icon: Icons.pie_chart_outline,
          )
        else
          Panel(
            child: Column(
              children: [
                SizedBox(
                  height: 220,
                  width: 220,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Positioned.fill(
                        child: ExcludeSemantics(
                          child: CustomPaint(
                            painter: _DonutPainter(
                              amounts: spending
                                  .map((entry) => entry.value)
                                  .toList(),
                              colors: spending
                                  .map(
                                    (entry) => Color(
                                      data.category(entry.key).colorValue,
                                    ),
                                  )
                                  .toList(),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 130,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('Total spent'),
                            const SizedBox(height: 6),
                            Text(
                              formatMoney(expenses),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                for (final entry in spending)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 6,
                          backgroundColor: Color(
                            data.category(entry.key).colorValue,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(data.category(entry.key).name),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            '${formatMoney(entry.value)}\n'
                            '${(entry.value / expenses * 100).toStringAsFixed(1)}%',
                            textAlign: TextAlign.right,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        const SectionTitle('Six-month comparison'),
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Text(
            'Green shows income. Red shows expenses. '
            'All bars use the same scale.',
          ),
        ),
        for (final item in months)
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  formatMonth(item),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                _ReportBar(
                  label: 'Income',
                  amount: data.monthTotal(item, incomeType),
                  maximum: maximum,
                  color: incomeColor,
                ),
                const SizedBox(height: 12),
                _ReportBar(
                  label: 'Expenses',
                  amount: data.monthTotal(item, expenseType),
                  maximum: maximum,
                  color: expenseColor,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({
    required this.title,
    required this.amount,
    required this.color,
  });

  final String title;
  final int amount;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(child: Text(title)),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              formatMoney(amount),
              textAlign: TextAlign.right,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportBar extends StatelessWidget {
  const _ReportBar({
    required this.label,
    required this.amount,
    required this.maximum,
    required this.color,
  });

  final String label;
  final int amount;
  final int maximum;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: Text(label)),
            Flexible(
              child: Text(
                formatMoney(amount),
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        LinearProgressIndicator(
          value: (amount / maximum).clamp(0.0, 1.0),
          minHeight: 9,
          borderRadius: BorderRadius.circular(8),
          color: color,
          backgroundColor: color.withValues(alpha: 0.12),
        ),
      ],
    );
  }
}

class _DonutPainter extends CustomPainter {
  const _DonutPainter({
    required this.amounts,
    required this.colors,
  });

  final List<int> amounts;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final total = amounts.fold<int>(0, (sum, value) => sum + value);
    if (total == 0) return;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 18;
    final rectangle = Rect.fromCircle(center: center, radius: radius);

    var start = -math.pi / 2;

    for (var index = 0; index < amounts.length; index++) {
      final sweep = amounts[index] / total * math.pi * 2;

      final paint = Paint()
        ..color = colors[index]
        ..style = PaintingStyle.stroke
        ..strokeWidth = 28;

      canvas.drawArc(rectangle, start, sweep, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) => true;
}