import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../notifications.dart';
import '../widgets.dart';

import 'budgets_screen.dart';
import 'dashboard_screen.dart';
import 'reports_screen.dart';
import 'settings_screen.dart';
import 'transactions_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.api, required this.onSignedOut});

  final Api api;
  final VoidCallback onSignedOut;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  AppData? data;
  String? error;
  String? notificationWarning;

  int selectedIndex = 0;
  DateTime selectedMonth = monthOnly(DateTime.now());

  bool loading = true;
  bool signingOut = false;

  Future<void>? activeRefresh;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() {
    if (!mounted || signingOut) return Future<void>.value();

    final existing = activeRefresh;
    if (existing != null) return existing;

    final future = load();
    activeRefresh = future;

    return future.whenComplete(() {
      if (identical(activeRefresh, future)) {
        activeRefresh = null;
      }
    });
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });

    try {
      final loaded = await widget.api.loadData();

      if (!mounted || signingOut) return;

      final warning = await Notifications.sync(
        loaded.reminders,
        enabled: loaded.user.remindersEnabled,
      );

      if (!mounted || signingOut) return;

      setState(() {
        data = loaded;
        notificationWarning = warning;
      });
    } catch (failure) {
      if (mounted && !signingOut) {
        setState(() => error = readableError(failure));
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> signOut() async {
    if (signingOut) return;

    setState(() => signingOut = true);

    try {
      await activeRefresh;

      String? notificationError;

      try {
        await Notifications.cancelAll();
      } catch (_) {
        notificationError =
            'Signed out, but device reminders could not be cancelled.';
      }

      final warning = await widget.api.logout();

      if (!mounted) return;

      final message = warning ?? notificationError;
      if (message != null) showMessage(context, message);

      Navigator.of(context).popUntil((route) => route.isFirst);
      widget.onSignedOut();
    } catch (failure) {
      if (mounted) {
        showMessage(context, readableError(failure));
        setState(() => signingOut = false);
      }
    }
  }

  Future<void> openSettings() async {
    final current = data;
    if (current == null || signingOut) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(
          api: widget.api,
          initialData: current,
          onSignedOut: signOut,
        ),
      ),
    );

    if (mounted && !signingOut) await refresh();
  }

  void changeMonth(DateTime month) {
    setState(() => selectedMonth = monthOnly(month));
  }

  @override
  Widget build(BuildContext context) {
    final current = data;

    const titles = [
      'PocketWise',
      'Transactions',
      'Monthly budgets',
      'Spending reports',
    ];

    Widget content;

    if (signingOut || (loading && current == null)) {
      content = const Center(child: CircularProgressIndicator());
    } else if (current == null) {
      content = ErrorMessage(
        message: error ?? 'Unable to load your account.',
        onRetry: refresh,
      );
    } else {
      final pages = <Widget>[
        DashboardScreen(
          data: current,
          month: selectedMonth,
          onMonthChanged: changeMonth,
          onRefresh: refresh,
          onAddTransaction: () async {
            final saved = await openTransactionForm(
              context,
              api: widget.api,
              data: current,
            );

            if (saved && mounted) await refresh();
          },
          onViewTransactions: () {
            setState(() => selectedIndex = 1);
          },
        ),
        TransactionsScreen(api: widget.api, data: current, onChanged: refresh),
        BudgetsScreen(
          api: widget.api,
          data: current,
          month: selectedMonth,
          onMonthChanged: changeMonth,
          onChanged: refresh,
        ),
        ReportsScreen(
          data: current,
          month: selectedMonth,
          onMonthChanged: changeMonth,
          onRefresh: refresh,
        ),
      ];

      content = pages[selectedIndex];
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(titles[selectedIndex]),
        actions: [
          if (current != null)
            IconButton(
              tooltip: 'Refresh',
              onPressed: loading || signingOut ? null : refresh,
              icon: const Icon(Icons.refresh),
            ),
          IconButton(
            tooltip: current == null ? 'Sign out' : 'Settings',
            onPressed: signingOut
                ? null
                : current == null
                ? signOut
                : openSettings,
            icon: Icon(
              current == null ? Icons.logout : Icons.settings_outlined,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (loading && current != null)
              const LinearProgressIndicator(minHeight: 2),
            if (error != null && current != null)
              MaterialBanner(
                content: Text(
                  '$error Previously loaded data is still displayed.',
                ),
                actions: [
                  TextButton(
                    onPressed: loading ? null : refresh,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            if (notificationWarning != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                child: Text(
                  notificationWarning!,
                  style: const TextStyle(color: Colors.orange, fontSize: 12),
                ),
              ),
            Expanded(child: content),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: signingOut
            ? null
            : (index) {
                setState(() => selectedIndex = index);
                refresh();
              },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Records',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: Icon(Icons.account_balance_wallet),
            label: 'Budgets',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart),
            label: 'Reports',
          ),
        ],
      ),
    );
  }
}
