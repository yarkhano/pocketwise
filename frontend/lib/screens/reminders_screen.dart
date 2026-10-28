import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;

import '../api.dart';
import '../models.dart';
import '../notifications.dart';
import '../widgets.dart';

class RemindersScreen extends StatefulWidget {
  const RemindersScreen({
    super.key,
    required this.api,
  });

  final Api api;

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  AppData? data;
  String? error;
  String? warning;
  bool loading = false;
  bool working = false;

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
      final message = await Notifications.sync(
        result.reminders,
        enabled: result.user.remindersEnabled,
      );

      if (!mounted) return;

      setState(() {
        data = result;
        warning = message;
      });
    } catch (exception) {
      if (mounted) setState(() => error = readableError(exception));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> edit([BillReminder? reminder]) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _ReminderForm(
          api: widget.api,
          reminder: reminder,
        ),
      ),
    );

    if (saved == true && mounted) await load();
  }

  Future<void> toggle(BillReminder reminder) async {
    if (working) return;

    if (!reminder.isEnabled &&
        !reminder.isMonthly &&
        !reminder.scheduledAt.isAfter(DateTime.now())) {
      showMessage(context, 'Edit this reminder and choose a future time.');
      return;
    }

    setState(() => working = true);

    try {
      await widget.api.saveReminder(
        reminder.copyWith(isEnabled: !reminder.isEnabled),
      );
      await load();
    } catch (exception) {
      if (mounted) showMessage(context, readableError(exception));
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  Future<void> remove(BillReminder reminder) async {
    if (working) return;

    final confirmed = await confirmAction(
      context,
      title: 'Delete reminder?',
      message: 'The reminder will also be removed from this device schedule.',
    );

    if (!confirmed || !mounted) return;
    setState(() => working = true);

    try {
      await widget.api.deleteReminder(reminder.id);
      await load();
    } catch (exception) {
      if (mounted) showMessage(context, readableError(exception));
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  Future<void> enableNotifications() async {
    final current = data;
    if (current == null || working) return;

    setState(() => working = true);

    try {
      final allowed = await Notifications.requestPermission();

      if (!allowed) {
        throw StateError(
          'Allow notifications in Android Settings, then try again.',
        );
      }

      await widget.api.updateProfile(
        fullName: current.user.fullName,
        remindersEnabled: true,
      );

      await load();
    } catch (exception) {
      if (mounted) showMessage(context, readableError(exception));
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = data;

    final reminders = current?.reminders.toList() ?? <BillReminder>[];
    reminders.sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));

    return Scaffold(
      appBar: AppBar(title: const Text('Bill reminders')),
      body: current == null
          ? loading
              ? const Center(child: CircularProgressIndicator())
              : ErrorMessage(
                  message: error ?? 'Could not load reminders.',
                  onRetry: load,
                )
          : PageBody(
              onRefresh: load,
              children: [
                if (loading || working) const LinearProgressIndicator(),
                if (error != null)
                  ErrorMessage(message: error!, onRetry: load),
                Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Reminders notify you; they do not record '
                        'expenses or pay bills.',
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Monthly reminders are scheduled 12 occurrences '
                        'ahead and renewed when you refresh the app. '
                        'The 29th–31st use the last day of shorter months.',
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Android may deliver a reminder after the selected '
                        'time because of battery-saving settings.',
                      ),
                      if (!current.user.remindersEnabled) ...[
                        const SizedBox(height: 12),
                        const Text('Reminder notifications are switched off.'),
                        TextButton(
                          onPressed: working ? null : enableNotifications,
                          child: const Text('Enable notifications'),
                        ),
                      ],
                    ],
                  ),
                ),
                if (warning != null)
                  Panel(child: Text(warning!)),
                if (reminders.isEmpty)
                  const EmptyMessage(
                    title: 'No reminders yet',
                    message: 'Add a reminder for a bill or payment.',
                    icon: Icons.notifications_none,
                  ),
                for (final reminder in reminders)
                  Panel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.notifications_outlined),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                reminder.title,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            PopupMenuButton<String>(
                              enabled: !working && !loading,
                              onSelected: (action) {
                                if (action == 'edit') {
                                  edit(reminder);
                                } else {
                                  remove(reminder);
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
                          '${reminder.isMonthly ? "Monthly from" : "Once on"} '
                          '${formatDateTime(Notifications.localTime(reminder))}',
                        ),
                        Text('Time zone: ${reminder.timezone}'),
                        if (!reminder.isMonthly &&
                            !reminder.scheduledAt.isAfter(DateTime.now()))
                          const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text('The selected time has passed.'),
                          ),
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Active'),
                          value: reminder.isEnabled,
                          onChanged: working || loading
                              ? null
                              : (_) => toggle(reminder),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: current == null || working || loading
            ? null
            : () => edit(),
        icon: const Icon(Icons.add),
        label: const Text('Add reminder'),
      ),
    );
  }
}

class _ReminderForm extends StatefulWidget {
  const _ReminderForm({
    required this.api,
    this.reminder,
  });

  final Api api;
  final BillReminder? reminder;

  @override
  State<_ReminderForm> createState() => _ReminderFormState();
}

class _ReminderFormState extends State<_ReminderForm> {
  final formKey = GlobalKey<FormState>();

  late final TextEditingController title;
  late final String timezone;

  late DateTime date;
  late TimeOfDay time;

  String repeatType = 'once';
  bool enabled = true;
  bool busy = false;

  @override
  void initState() {
    super.initState();

    final reminder = widget.reminder;
    timezone = reminder?.timezone ?? Notifications.deviceTimezone;

    final local = reminder == null
        ? tz.TZDateTime.from(
            DateTime.now().add(const Duration(hours: 1)),
            tz.getLocation(timezone),
          )
        : Notifications.localTime(reminder);

    title = TextEditingController(text: reminder?.title ?? '');
    date = DateTime(local.year, local.month, local.day);
    time = TimeOfDay(hour: local.hour, minute: local.minute);

    repeatType = reminder?.repeatType ?? 'once';
    enabled = reminder?.isEnabled ?? true;
  }

  @override
  void dispose() {
    title.dispose();
    super.dispose();
  }

  Future<void> chooseTime() async {
    final selected = await showTimePicker(
      context: context,
      initialTime: time,
    );

    if (selected != null && mounted) {
      setState(() => time = selected);
    }
  }

  Future<void> save() async {
    if (!formKey.currentState!.validate()) return;

    final scheduled = tz.TZDateTime(
      tz.getLocation(timezone),
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );

    if (enabled &&
        repeatType == 'once' &&
        !scheduled.isAfter(DateTime.now())) {
      showMessage(context, 'Choose a future date and time.');
      return;
    }

    setState(() => busy = true);

    try {
      await widget.api.saveReminder(
        BillReminder(
          id: widget.reminder?.id ?? 0,
          title: title.text.trim(),
          scheduledAt: scheduled.toUtc(),
          timezone: timezone,
          repeatType: repeatType,
          isEnabled: enabled,
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
            widget.reminder == null ? 'Add reminder' : 'Edit reminder',
          ),
        ),
        body: AbsorbPointer(
          absorbing: busy,
          child: Form(
            key: formKey,
            child: PageBody(
              children: [
                TextFormField(
                  controller: title,
                  maxLength: 120,
                  decoration: const InputDecoration(
                    labelText: 'Reminder title',
                    hintText: 'For example, electricity bill',
                  ),
                  validator: requiredText,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: repeatType,
                  decoration: const InputDecoration(labelText: 'Repeat'),
                  items: const [
                    DropdownMenuItem(
                      value: 'once',
                      child: Text('One time'),
                    ),
                    DropdownMenuItem(
                      value: 'monthly',
                      child: Text('Every month'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => repeatType = value);
                    }
                  },
                ),
                const SizedBox(height: 16),
                DateField(
                  value: date,
                  label: repeatType == 'monthly' ? 'Starting date' : 'Date',
                  onChanged: (value) => setState(() => date = value),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.access_time),
                  title: const Text('Time'),
                  subtitle: Text(time.format(context)),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: chooseTime,
                ),
                Text('Time zone: $timezone'),
                const SizedBox(height: 8),
                if (repeatType == 'monthly')
                  const Text(
                    'Uses the same day each month, or the last day '
                    'when that month is shorter.',
                  ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Active reminder'),
                  value: enabled,
                  onChanged: (value) => setState(() => enabled = value),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: busy ? null : save,
                  child: Text(busy ? 'Saving...' : 'Save reminder'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}