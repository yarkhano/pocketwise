import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({
    super.key,
    required this.api,
    required this.onAuthenticated,
  });

  final Api api;
  final VoidCallback onAuthenticated;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final formKey = GlobalKey<FormState>();

  final nameController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmController = TextEditingController();

  bool registering = false;
  bool busy = false;

  @override
  void dispose() {
    nameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    confirmController.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (busy || !formKey.currentState!.validate()) return;

    setState(() => busy = true);

    try {
      if (registering) {
        await widget.api.register(
          nameController.text,
          emailController.text,
          passwordController.text,
        );

        if (!mounted) return;

        setState(() => registering = false);
        passwordController.clear();
        confirmController.clear();

        showMessage(
          context,
          'Account created. Log in using your email and password.',
        );
      } else {
        await widget.api.login(emailController.text, passwordController.text);

        if (mounted) widget.onAuthenticated();
      }
    } catch (error) {
      if (mounted) showMessage(context, readableError(error));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void switchMode() {
    if (busy) return;

    formKey.currentState?.reset();
    passwordController.clear();
    confirmController.clear();

    setState(() => registering = !registering);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Image.asset(
                        'assets/logo.png',
                        width: 76,
                        height: 76,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.account_balance_wallet_rounded,
                          size: 76,
                          color: brandColor,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'PocketWise',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      registering
                          ? 'Create your personal account'
                          : 'Welcome back. Log in to manage your money.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 28),
                    if (registering) ...[
                      TextFormField(
                        controller: nameController,
                        enabled: !busy,
                        maxLength: 80,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Full name',
                          prefixIcon: Icon(Icons.person_outline),
                          counterText: '',
                        ),
                        validator: requiredText,
                      ),
                      const SizedBox(height: 14),
                    ],
                    TextFormField(
                      controller: emailController,
                      enabled: !busy,
                      maxLength: 254,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.email_outlined),
                        counterText: '',
                      ),
                      validator: validateEmail,
                    ),
                    const SizedBox(height: 14),
                    AbsorbPointer(
                      absorbing: busy,
                      child: PasswordField(
                        controller: passwordController,
                        validator: registering
                            ? validatePassword
                            : requiredText,
                      ),
                    ),
                    if (registering) ...[
                      const SizedBox(height: 14),
                      AbsorbPointer(
                        absorbing: busy,
                        child: PasswordField(
                          controller: confirmController,
                          label: 'Confirm password',
                          validator: (value) {
                            if (value != passwordController.text) {
                              return 'Passwords do not match.';
                            }

                            return requiredText(value);
                          },
                        ),
                      ),
                    ],
                    const SizedBox(height: 22),
                    FilledButton(
                      onPressed: busy ? null : submit,
                      child: busy
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(registering ? 'Create account' : 'Log in'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: busy ? null : switchMode,
                      child: Text(
                        registering
                            ? 'Already registered? Log in'
                            : 'New here? Create an account',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
