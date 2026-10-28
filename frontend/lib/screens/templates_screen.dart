import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../widgets.dart';
import 'transactions_screen.dart';

class TemplatesScreen extends StatefulWidget {
  const TemplatesScreen({
    super.key,
    required this.api,
  });

  final Api api;

  @override
  State<TemplatesScreen> createState() => _TemplatesScreenState();
}

class _TemplatesScreenState extends State<TemplatesScreen> {
  AppData? data;
  String? error;
  bool loading = false;
  bool deleting = false;

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
    } catch (exception) {
      if (mounted) setState(() => error = readableError(exception));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> edit([QuickTemplate? template]) async {
    final current = data;
    if (current == null) return;

    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _TemplateForm(
          api: widget.api,
          data: current,
          template: template,
        ),
      ),
    );

    if (saved == true && mounted) await load();
  }

  Future<void> useTemplate(QuickTemplate template) async {
    final current = data;
    if (current == null) return;

    if (current.category(template.categoryId).isArchived) {
      showMessage(context, 'Edit this template and choose an active category.');
      return;
    }

    final saved = await openTransactionForm(
      context,
      api: widget.api,
      data: current,
      template: template,
    );

    if (saved && mounted) await load();
  }

  Future<void> remove(QuickTemplate template) async {
    if (deleting) return;

    final confirmed = await confirmAction(
      context,
      title: 'Delete template?',
      message: 'Existing transactions will remain unchanged.',
    );

    if (!confirmed || !mounted) return;
    setState(() => deleting = true);

    try {
      await widget.api.deleteTemplate(template.id);
      await load();
    } catch (exception) {
      if (mounted) showMessage(context, readableError(exception));
    } finally {
      if (mounted) setState(() => deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = data;

    final templates = current?.templates.toList() ?? <QuickTemplate>[];
    templates.sort((a, b) => a.name.compareTo(b.name));

    return Scaffold(
      appBar: AppBar(title: const Text('Quick-entry templates')),
      body: current == null
          ? loading
              ? const Center(child: CircularProgressIndicator())
              : ErrorMessage(
                  message: error ?? 'Could not load templates.',
                  onRetry: load,
                )
          : PageBody(
              onRefresh: load,
              children: [
                if (loading || deleting) const LinearProgressIndicator(),
                if (error != null)
                  ErrorMessage(message: error!, onRetry: load),
                const Panel(
                  child: Text(
                    'Save entries you use often. Select Use template, '
                    'check the details, and save the transaction.',
                  ),
                ),
                if (templates.isEmpty)
                  const EmptyMessage(
                    title: 'No templates yet',
                    message: 'Create a template for a frequent income or expense.',
                    icon: Icons.bookmark_border,
                  ),
                for (final template in templates)
                  Panel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                template.name,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            PopupMenuButton<String>(
                              enabled: !deleting && !loading,
                              onSelected: (action) {
                                if (action == 'edit') {
                                  edit(template);
                                } else {
                                  remove(template);
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
                        Text(
                          '${current.category(template.categoryId).name} • '
                          '${formatMoney(template.amountPaisa)}',
                        ),
                        if (template.note.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(template.note),
                        ],
                        if (current.category(template.categoryId).isArchived)
                          const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text(
                              'This category is archived. Edit the template '
                              'before using it.',
                            ),
                          ),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: deleting || loading
                              ? null
                              : () => useTemplate(template),
                          icon: const Icon(Icons.add),
                          label: const Text('Use template'),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: current == null || loading || deleting
            ? null
            : () => edit(),
        icon: const Icon(Icons.add),
        label: const Text('Add template'),
      ),
    );
  }
}

class _TemplateForm extends StatefulWidget {
  const _TemplateForm({
    required this.api,
    required this.data,
    this.template,
  });

  final Api api;
  final AppData data;
  final QuickTemplate? template;

  @override
  State<_TemplateForm> createState() => _TemplateFormState();
}

class _TemplateFormState extends State<_TemplateForm> {
  final formKey = GlobalKey<FormState>();

  late final TextEditingController name;
  late final TextEditingController amount;
  late final TextEditingController note;

  String type = expenseType;
  int? categoryId;
  bool busy = false;

  @override
  void initState() {
    super.initState();

    final template = widget.template;

    name = TextEditingController(text: template?.name ?? '');
    amount = TextEditingController(
      text: template == null ? '' : decimalMoney(template.amountPaisa),
    );
    note = TextEditingController(text: template?.note ?? '');

    if (template != null) {
      final category = widget.data.category(template.categoryId);
      type = category.type;
      categoryId = category.isArchived ? null : category.id;
    }
  }

  @override
  void dispose() {
    name.dispose();
    amount.dispose();
    note.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (!formKey.currentState!.validate()) return;

    setState(() => busy = true);

    try {
      await widget.api.saveTemplate(
        QuickTemplate(
          id: widget.template?.id ?? 0,
          categoryId: categoryId!,
          name: name.text.trim(),
          amountPaisa: positiveMoney(amount.text),
          note: note.text.trim(),
        ),
      );

      if (mounted) Navigator.of(context).pop(true);
    } catch (exception) {
      if (mounted) showMessage(context, readableError(exception));
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
            widget.template == null ? 'Add template' : 'Edit template',
          ),
        ),
        body: AbsorbPointer(
          absorbing: busy,
          child: Form(
            key: formKey,
            child: PageBody(
              children: [
                TextFormField(
                  controller: name,
                  maxLength: 60,
                  decoration: const InputDecoration(
                    labelText: 'Template name',
                    hintText: 'For example, university lunch',
                  ),
                  validator: requiredText,
                ),
                const SizedBox(height: 16),
                TransactionTypeField(
                  value: type,
                  onChanged: (value) {
                    setState(() {
                      type = value;
                      categoryId = null;
                    });
                  },
                ),
                const SizedBox(height: 16),
                CategoryField(
                  categories: widget.data.activeCategories(type),
                  value: categoryId,
                  onChanged: (value) => setState(() => categoryId = value),
                ),
                const SizedBox(height: 16),
                AmountField(controller: amount),
                const SizedBox(height: 16),
                TextFormField(
                  controller: note,
                  maxLength: 250,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Note (optional)',
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: busy ? null : save,
                  child: Text(busy ? 'Saving...' : 'Save template'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}