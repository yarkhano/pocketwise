import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models.dart';
import 'theme.dart';

String readableError(Object error) {
  if (error is FormatException) {
    return error.message.toString();
  }

  return error
      .toString()
      .replaceFirst(RegExp(r'^(Exception|StateError|Bad state):\s*'), '');
}

void showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(message)),
    );
}

String? requiredText(String? value) {
  if (value == null || value.trim().isEmpty) {
    return 'This field is required.';
  }

  return null;
}

String? validateEmail(String? value) {
  final email = value?.trim() ?? '';

  if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
    return 'Enter a valid email address.';
  }

  return null;
}

String? validatePassword(String? value) {
  if (value == null || value.length < 8) {
    return 'Use at least 8 characters.';
  }

  if (value.length > 128) {
    return 'Use no more than 128 characters.';
  }

  return null;
}

String? validateAmount(String? value) {
  try {
    positiveMoney(value ?? '');
    return null;
  } on FormatException catch (error) {
    return error.message.toString();
  }
}

Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  String actionLabel = 'Delete',
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(actionLabel),
          ),
        ],
      );
    },
  );

  return result ?? false;
}

class PageBody extends StatelessWidget {
  final List<Widget> children;
  final Future<void> Function()? onRefresh;

  const PageBody({
    super.key,
    required this.children,
    this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final content = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      children: children,
    );

    final centered = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: content,
      ),
    );

    if (onRefresh == null) return centered;

    return RefreshIndicator(
      onRefresh: onRefresh!,
      child: centered,
    );
  }
}

class Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E9F1)),
      ),
      child: child,
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const SectionTitle(
    this.title, {
    super.key,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class EmptyMessage extends StatelessWidget {
  final String title;
  final String message;
  final IconData icon;

  const EmptyMessage({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.inbox_outlined,
  });

  @override
  Widget build(BuildContext context) {
    return Panel(
      padding: const EdgeInsets.symmetric(
        horizontal: 20,
        vertical: 32,
      ),
      child: Column(
        children: [
          Icon(icon, size: 44, color: brandColor),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class ErrorMessage extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const ErrorMessage({
    super.key,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              size: 48,
              color: expenseColor,
            ),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onRetry,
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

class AmountField extends StatelessWidget {
  final TextEditingController controller;
  final String label;

  const AmountField({
    super.key,
    required this.controller,
    this.label = 'Amount',
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
        LengthLimitingTextInputFormatter(15),
      ],
      decoration: InputDecoration(
        labelText: label,
        prefixText: 'PKR ',
        hintText: '0.00',
      ),
      validator: validateAmount,
    );
  }
}

class PasswordField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String? Function(String?)? validator;

  const PasswordField({
    super.key,
    required this.controller,
    this.label = 'Password',
    this.validator,
  });

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool hidden = true;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      obscureText: hidden,
      enableSuggestions: false,
      autocorrect: false,
      decoration: InputDecoration(
        labelText: widget.label,
        prefixIcon: const Icon(Icons.lock_outline),
        suffixIcon: IconButton(
          tooltip: hidden ? 'Show password' : 'Hide password',
          onPressed: () => setState(() => hidden = !hidden),
          icon: Icon(
            hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined,
          ),
        ),
      ),
      validator: widget.validator ?? validatePassword,
    );
  }
}

// Handles duplicate-tap prevention and displays request errors.
// Validation happens inside onSubmit, before sending a request.
class SubmitButton extends StatefulWidget {
  final String label;
  final Future<void> Function() onSubmit;
  final IconData? icon;

  const SubmitButton({
    super.key,
    required this.label,
    required this.onSubmit,
    this.icon,
  });

  @override
  State<SubmitButton> createState() => _SubmitButtonState();
}

class _SubmitButtonState extends State<SubmitButton> {
  bool busy = false;

  Future<void> submit() async {
    if (busy) return;

    setState(() => busy = true);

    try {
      await widget.onSubmit();
    } catch (error) {
      if (mounted) {
        showMessage(context, readableError(error));
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: busy ? null : submit,
        child: busy
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (widget.icon != null) ...[
                    Icon(widget.icon, size: 20),
                    const SizedBox(width: 8),
                  ],
                  Text(widget.label),
                ],
              ),
      ),
    );
  }
}

class MonthSelector extends StatelessWidget {
  final DateTime month;
  final ValueChanged<DateTime> onChanged;

  const MonthSelector({
    super.key,
    required this.month,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Panel(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Previous month',
            onPressed: () => onChanged(
              DateTime(month.year, month.month - 1),
            ),
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: Text(
              formatMonth(month),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          IconButton(
            tooltip: 'Next month',
            onPressed: () => onChanged(
              DateTime(month.year, month.month + 1),
            ),
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }
}

class CategoryField extends StatelessWidget {
  final List<ExpenseCategory> categories;
  final int? value;
  final ValueChanged<int?> onChanged;

  const CategoryField({
    super.key,
    required this.categories,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final validValue = categories.any((item) => item.id == value)
        ? value
        : null;

    return DropdownButtonFormField<int>(
      key: ValueKey(
        '${categories.map((item) => item.id).join(",")}:$validValue',
      ),
      initialValue: validValue,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Category'),
      items: categories.map((item) {
        return DropdownMenuItem<int>(
          value: item.id,
          child: Row(
            children: [
              Icon(
                categoryIcon(item.iconKey),
                size: 20,
                color: Color(item.colorValue),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  item.name,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      }).toList(),
      onChanged: categories.isEmpty ? null : onChanged,
      validator: (selected) {
        if (selected == null) return 'Choose a category.';
        return null;
      },
    );
  }
}

class TransactionTypeField extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const TransactionTypeField({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<String>(
      segments: const [
        ButtonSegment(
          value: expenseType,
          label: Text('Expense'),
          icon: Icon(Icons.arrow_upward),
        ),
        ButtonSegment(
          value: incomeType,
          label: Text('Income'),
          icon: Icon(Icons.arrow_downward),
        ),
      ],
      selected: {value},
      onSelectionChanged: (selection) => onChanged(selection.first),
    );
  }
}

class DateField extends StatelessWidget {
  final DateTime value;
  final ValueChanged<DateTime> onChanged;
  final String label;
  final DateTime? firstDate;
  final DateTime? lastDate;

  const DateField({
    super.key,
    required this.value,
    required this.onChanged,
    this.label = 'Date',
    this.firstDate,
    this.lastDate,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () async {
        final earliest = firstDate ?? DateTime(2000);
        final latest = lastDate ?? DateTime(2100, 12, 31);

        var initial = dateOnly(value);

        if (initial.isBefore(earliest)) initial = earliest;
        if (initial.isAfter(latest)) initial = latest;

        final selected = await showDatePicker(
          context: context,
          initialDate: initial,
          firstDate: earliest,
          lastDate: latest,
        );

        if (selected != null && context.mounted) {
          onChanged(selected);
        }
      },
      icon: const Icon(Icons.calendar_month_outlined),
      label: Text('$label: ${formatDate(value)}'),
    );
  }
}

class TransactionRow extends StatelessWidget {
  final MoneyTransaction transaction;
  final ExpenseCategory category;
  final VoidCallback? onTap;

  const TransactionRow({
    super.key,
    required this.transaction,
    required this.category,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = category.isIncome ? incomeColor : expenseColor;
    final sign = category.isIncome ? '+' : '-';

    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: Color(category.colorValue).withValues(alpha: 0.12),
        child: Icon(
          categoryIcon(category.iconKey),
          color: Color(category.colorValue),
        ),
      ),
      title: Text(
        transaction.note.isEmpty ? category.name : transaction.note,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${category.name} • ${formatDate(transaction.date)}',
      ),
      trailing: Text(
        '$sign${formatMoney(transaction.amountPaisa)}',
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

class BudgetProgress extends StatelessWidget {
  final int spentPaisa;
  final int limitPaisa;

  const BudgetProgress({
    super.key,
    required this.spentPaisa,
    required this.limitPaisa,
  });

  @override
  Widget build(BuildContext context) {
    final ratio = limitPaisa > 0 ? spentPaisa / limitPaisa : 0.0;
    final exceeded = spentPaisa >= limitPaisa;
    final approaching =
        !exceeded && spentPaisa * 100 >= limitPaisa * 80;

    final color = exceeded
        ? expenseColor
        : approaching
            ? warningColor
            : incomeColor;

    final remaining = limitPaisa - spentPaisa;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LinearProgressIndicator(
          value: ratio.clamp(0.0, 1.0).toDouble(),
          color: color,
          backgroundColor: color.withValues(alpha: 0.12),
          minHeight: 8,
          borderRadius: BorderRadius.circular(8),
        ),
        const SizedBox(height: 8),
        Text(
          '${formatMoney(spentPaisa)} of ${formatMoney(limitPaisa)}',
        ),
        const SizedBox(height: 4),
        Text(
          remaining < 0
              ? '${formatMoney(-remaining)} over budget'
              : '${formatMoney(remaining)} remaining',
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (exceeded || approaching) ...[
          const SizedBox(height: 6),
          Text(
            exceeded
                ? 'Budget limit reached or exceeded.'
                : 'You have used at least 80% of this budget.',
            style: TextStyle(color: color),
          ),
        ],
      ],
    );
  }
}