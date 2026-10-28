import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';

class CategoriesScreen extends StatefulWidget {
  final Api api;

  const CategoriesScreen({
    super.key,
    required this.api,
  });

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  AppData? data;
  String? error;

  bool loading = true;
  bool showArchived = false;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });

    try {
      final result = await widget.api.loadData();

      if (mounted) setState(() => data = result);
    } catch (failure) {
      if (mounted) setState(() => error = readableError(failure));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> edit([ExpenseCategory? category]) async {
    final current = data;

    if (current == null || busy) return;

    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => _CategoryForm(
          api: widget.api,
          data: current,
          category: category,
        ),
      ),
    );

    if (saved == true && mounted) await load();
  }

  Future<void> toggleArchive(ExpenseCategory category) async {
    if (busy) return;

    final confirmed = await confirmAction(
      context,
      title: category.isArchived ? 'Restore category?' : 'Archive category?',
      message: category.isArchived
          ? 'This category will become available for new transactions.'
          : 'Existing records will remain. This category will no longer '
              'be selectable for new transactions.',
      actionLabel: category.isArchived ? 'Restore' : 'Archive',
    );

    if (!confirmed || !mounted) return;

    setState(() => busy = true);

    try {
      await widget.api.saveCategory(
        category.copyWith(isArchived: !category.isArchived),
      );

      await load();
    } catch (failure) {
      if (mounted) showMessage(context, readableError(failure));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = data;

    final categories = current?.categories
            .where((item) => showArchived || !item.isArchived)
            .toList() ??
        [];

    categories.sort((first, second) {
      final byType = first.type.compareTo(second.type);

      return byType != 0
          ? byType
          : first.name.toLowerCase().compareTo(second.name.toLowerCase());
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Categories')),
      body: loading && current == null
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? ErrorMessage(message: error!, onRetry: load)
              : PageBody(
                  onRefresh: load,
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Show archived categories'),
                      value: showArchived,
                      onChanged: (value) {
                        setState(() => showArchived = value);
                      },
                    ),
                    if (loading || busy)
                      const LinearProgressIndicator(),
                    if (categories.isEmpty)
                      const EmptyMessage(
                        title: 'No categories',
                        message: 'Add a category using the button below.',
                        icon: Icons.category_outlined,
                      ),
                    for (final category in categories)
                      Panel(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            backgroundColor: Color(category.colorValue)
                                .withValues(alpha: 0.12),
                            child: Icon(
                              categoryIcon(category.iconKey),
                              color: Color(category.colorValue),
                            ),
                          ),
                          title: Text(category.name),
                          subtitle: Text(
                            '${category.isIncome ? "Income" : "Expense"}'
                            '${category.isArchived ? " • Archived" : ""}',
                          ),
                          onTap: busy ? null : () => edit(category),
                          trailing: PopupMenuButton<String>(
                            enabled: !busy,
                            onSelected: (action) {
                              if (action == 'edit') {
                                edit(category);
                              } else {
                                toggleArchive(category);
                              }
                            },
                            itemBuilder: (_) => [
                              const PopupMenuItem(
                                value: 'edit',
                                child: Text('Edit'),
                              ),
                              PopupMenuItem(
                                value: 'archive',
                                child: Text(
                                  category.isArchived ? 'Restore' : 'Archive',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: current == null || busy ? null : () => edit(),
        icon: const Icon(Icons.add),
        label: const Text('Category'),
      ),
    );
  }
}

class _CategoryForm extends StatefulWidget {
  final Api api;
  final AppData data;
  final ExpenseCategory? category;

  const _CategoryForm({
    required this.api,
    required this.data,
    this.category,
  });

  @override
  State<_CategoryForm> createState() => _CategoryFormState();
}

class _CategoryFormState extends State<_CategoryForm> {
  final formKey = GlobalKey<FormState>();

  late final TextEditingController nameController;

  late String type;
  late String iconKey;
  late int colorValue;

  bool busy = false;

  @override
  void initState() {
    super.initState();

    nameController = TextEditingController(
      text: widget.category?.name ?? '',
    );

    type = widget.category?.type ?? expenseType;
    iconKey = widget.category?.iconKey ?? 'other';
    colorValue = widget.category?.colorValue ?? categoryColors.first;
  }

  @override
  void dispose() {
    nameController.dispose();
    super.dispose();
  }

  bool get typeLocked {
    final id = widget.category?.id;

    if (id == null) return false;

    return widget.data.categoryHasTransactions(id) ||
        widget.data.budgets.any((item) => item.categoryId == id) ||
        widget.data.templates.any((item) => item.categoryId == id);
  }

  Future<void> save() async {
    if (busy || !formKey.currentState!.validate()) return;

    setState(() => busy = true);

    try {
      await widget.api.saveCategory(
        ExpenseCategory(
          id: widget.category?.id ?? 0,
          name: nameController.text,
          type: type,
          iconKey: iconKey,
          colorValue: colorValue,
          isArchived: widget.category?.isArchived ?? false,
        ),
      );

      if (mounted) Navigator.pop(context, true);
    } catch (failure) {
      if (mounted) showMessage(context, readableError(failure));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !busy,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.category == null ? 'Add category' : 'Edit category',
          ),
        ),
        body: AbsorbPointer(
          absorbing: busy,
          child: Form(
            key: formKey,
            child: PageBody(
              children: [
                TextFormField(
                  controller: nameController,
                  textCapitalization: TextCapitalization.words,
                  maxLength: 40,
                  decoration: const InputDecoration(
                    labelText: 'Category name',
                  ),
                  validator: requiredText,
                ),
                const SizedBox(height: 16),
                if (typeLocked)
                  Panel(
                    child: Text(
                      'Type: ${type == incomeType ? "Income" : "Expense"}\n'
                      'The type is locked because this category is used '
                      'by existing records.',
                    ),
                  )
                else
                  TransactionTypeField(
                    value: type,
                    onChanged: (value) => setState(() => type = value),
                  ),
                const SectionTitle('Choose an icon'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: categoryIcons.entries.map((entry) {
                    return ChoiceChip(
                      selected: iconKey == entry.key,
                      avatar: Icon(entry.value, size: 18),
                      label: Text(entry.key),
                      onSelected: (_) {
                        setState(() => iconKey = entry.key);
                      },
                    );
                  }).toList(),
                ),
                const SectionTitle('Choose a color'),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: categoryColors.map((value) {
                    return Semantics(
                      button: true,
                      selected: colorValue == value,
                      label: 'Category color ${categoryColors.indexOf(value) + 1}',
                      child: InkWell(
                        onTap: () => setState(() => colorValue = value),
                        borderRadius: BorderRadius.circular(24),
                        child: CircleAvatar(
                          radius: 24,
                          backgroundColor: Color(value),
                          child: colorValue == value
                              ? const Icon(Icons.check, color: Colors.white)
                              : null,
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 28),
                FilledButton(
                  onPressed: busy ? null : save,
                  child: busy
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save category'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}