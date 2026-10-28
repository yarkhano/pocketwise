import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../notifications.dart';
import '../widgets.dart';
import 'categories_screen.dart';
import 'reminders_screen.dart';
import 'templates_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.api,
    required this.initialData,
    required this.onSignedOut,
  });

  final Api api;
  final AppData initialData;
  final Future<void> Function() onSignedOut;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late AppData data;

  bool busy = false;
  String? error;
  String? notificationWarning;

  @override
  void initState() {
    super.initState();
    data = widget.initialData;
  }

  Future<void> refresh() async {
    if (busy) return;

    setState(() {
      busy = true;
      error = null;
    });

    try {
      final result = await widget.api.loadData();
      final warning = await Notifications.sync(
        result.reminders,
        enabled: result.user.remindersEnabled,
      );

      if (!mounted) return;

      setState(() {
        data = result;
        notificationWarning = warning;
      });
    } catch (exception) {
      if (mounted) setState(() => error = readableError(exception));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> openPage(Widget page) async {
    if (busy) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => page),
    );

    if (mounted) await refresh();
  }

  Future<void> editProfile() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _ProfileForm(
          api: widget.api,
          user: data.user,
        ),
      ),
    );

    if (saved == true && mounted) await refresh();
  }

  Future<void> toggleNotifications(bool enabled) async {
    if (busy) return;
    setState(() => busy = true);

    try {
      if (enabled) {
        final allowed = await Notifications.requestPermission();

        if (!allowed) {
          throw StateError(
            'Allow notifications in Android Settings, then try again.',
          );
        }
      }

      await widget.api.updateProfile(
        fullName: data.user.fullName,
        remindersEnabled: enabled,
      );

      final result = await widget.api.loadData();
      final warning = await Notifications.sync(
        result.reminders,
        enabled: result.user.remindersEnabled,
      );

      if (!mounted) return;

      setState(() {
        data = result;
        notificationWarning = warning;
      });

      showMessage(
        context,
        enabled ? 'Reminder preference enabled.' : 'Reminder preference disabled.',
      );
    } catch (exception) {
      if (mounted) showMessage(context, readableError(exception));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> changePassword() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _PasswordForm(api: widget.api),
      ),
    );

    if (changed == true && mounted) {
      showMessage(context, 'Password changed. Please sign in again.');
      await widget.onSignedOut();
    }
  }

  Future<void> signOut() async {
    final confirmed = await confirmAction(
      context,
      title: 'Sign out?',
      message: widget.api.isDemo
          ? 'Your temporary demo data will be cleared.'
          : 'Local reminder notifications will be cancelled on this device.',
      actionLabel: 'Sign out',
    );

    if (!confirmed || !mounted) return;
    await widget.onSignedOut();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: PageBody(
        onRefresh: refresh,
        children: [
          if (busy) const LinearProgressIndicator(),
          if (error != null)
            ErrorMessage(message: error!, onRetry: refresh),
          Panel(
            child: Column(
              children: [
                const CircleAvatar(
                  radius: 30,
                  child: Icon(Icons.person_outline, size: 34),
                ),
                const SizedBox(height: 12),
                Text(
                  data.user.fullName,
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  data.user.email,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: busy ? null : editProfile,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit profile'),
                ),
              ],
            ),
          ),
          if (widget.api.isDemo)
            const Panel(
              child: Text(
                'Demo mode: changes are temporary and disappear when '
                'you leave the demo or restart the app.',
              ),
            ),
          Panel(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.category_outlined),
                  title: const Text('Categories'),
                  subtitle: const Text('Add, edit, archive, and restore'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: busy
                      ? null
                      : () => openPage(CategoriesScreen(api: widget.api)),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.notifications_outlined),
                  title: const Text('Bill reminders'),
                  subtitle: const Text('One-time and monthly reminders'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: busy
                      ? null
                      : () => openPage(RemindersScreen(api: widget.api)),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.bookmark_border),
                  title: const Text('Quick-entry templates'),
                  subtitle: const Text('Reuse frequent transaction details'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: busy
                      ? null
                      : () => openPage(TemplatesScreen(api: widget.api)),
                ),
              ],
            ),
          ),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Reminder notifications'),
                  subtitle: const Text(
                    'Enable or disable local bill notifications',
                  ),
                  value: data.user.remindersEnabled,
                  onChanged: busy ? null : toggleNotifications,
                ),
                if (notificationWarning != null) ...[
                  const SizedBox(height: 8),
                  Text(notificationWarning!),
                ],
                if (data.user.remindersEnabled)
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => toggleNotifications(true),
                    child: const Text('Check notification permission'),
                  ),
              ],
            ),
          ),
          Panel(
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.lock_outline),
              title: const Text('Change password'),
              subtitle: Text(
                widget.api.isDemo
                    ? 'Available for real accounts after backend setup'
                    : 'You will need to sign in again afterward',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: busy || widget.api.isDemo ? null : changePassword,
            ),
          ),
          const Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PocketWise',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                Text('Personal expense and budget tracker'),
                SizedBox(height: 8),
                Text('Currency: Pakistani rupee (PKR)'),
                SizedBox(height: 8),
                Text(
                  'Dashboard totals are based on your recorded entries. '
                  'PocketWise does not connect to a bank account.',
                ),
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed: busy ? null : signOut,
            icon: const Icon(Icons.logout),
            label: const Text('Sign out'),
          ),
        ],
      ),
    );
  }
}

class _ProfileForm extends StatefulWidget {
  const _ProfileForm({
    required this.api,
    required this.user,
  });

  final Api api;
  final UserProfile user;

  @override
  State<_ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends State<_ProfileForm> {
  final formKey = GlobalKey<FormState>();
  late final TextEditingController name;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    name = TextEditingController(text: widget.user.fullName);
  }

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (!formKey.currentState!.validate()) return;
    setState(() => busy = true);

    try {
      await widget.api.updateProfile(
        fullName: name.text.trim(),
        remindersEnabled: widget.user.remindersEnabled,
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
        appBar: AppBar(title: const Text('Edit profile')),
        body: AbsorbPointer(
          absorbing: busy,
          child: Form(
            key: formKey,
            child: PageBody(
              children: [
                TextFormField(
                  controller: name,
                  maxLength: 80,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Full name'),
                  validator: requiredText,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  initialValue: widget.user.email,
                  readOnly: true,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    helperText: 'The account email cannot be changed here.',
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: busy ? null : save,
                  child: Text(busy ? 'Saving...' : 'Save profile'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PasswordForm extends StatefulWidget {
  const _PasswordForm({required this.api});

  final Api api;

  @override
  State<_PasswordForm> createState() => _PasswordFormState();
}

class _PasswordFormState extends State<_PasswordForm> {
  final formKey = GlobalKey<FormState>();

  final current = TextEditingController();
  final password = TextEditingController();
  final confirmation = TextEditingController();

  bool busy = false;

  @override
  void dispose() {
    current.dispose();
    password.dispose();
    confirmation.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (!formKey.currentState!.validate()) return;
    setState(() => busy = true);

    try {
      // Cancel before changing credentials so logout cannot leave
      // old account reminders scheduled on this device.
      await Notifications.cancelAll();

      await widget.api.changePassword(
        current.text,
        password.text,
      );

      if (mounted) Navigator.of(context).pop(true);
    } catch (exception) {
      if (mounted) {
        showMessage(
          context,
          '${readableError(exception)} '
          'Refresh the app afterward to renew reminder notifications.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('Change password')),
        body: AbsorbPointer(
          absorbing: busy,
          child: Form(
            key: formKey,
            child: PageBody(
              children: [
                PasswordField(
                  controller: current,
                  label: 'Current password',
                  validator: requiredText,
                ),
                const SizedBox(height: 16),
                PasswordField(
                  controller: password,
                  label: 'New password',
                  validator: (value) {
                    final error = validatePassword(value);
                    if (error != null) return error;

                    if (value == current.text) {
                      return 'Choose a different password.';
                    }

                    return null;
                  },
                ),
                const SizedBox(height: 16),
                PasswordField(
                  controller: confirmation,
                  label: 'Confirm new password',
                  validator: (value) {
                    if (value != password.text) {
                      return 'Passwords do not match.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                const Text(
                  'Changing your password ends your existing sessions. '
                  'Sign in again using your new password.',
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: busy ? null : save,
                  child: Text(busy ? 'Updating...' : 'Change password'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}