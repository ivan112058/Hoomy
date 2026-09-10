import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/auth/auth_controller.dart';
import '../../data/subsonic/subsonic_client.dart';

/// 登录页：服务器 URL + 用户名 + 密码。
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _serverController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _submitting = false;

  @override
  void dispose() {
    _serverController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      await ref.read(authProvider.notifier).login(
            _serverController.text,
            _usernameController.text,
            _passwordController.text,
          );
      // 登录态由根路由监听，这里无需导航。
    } on SubsonicException catch (e) {
      _showError(e.isAuthError ? '用户名或密码错误' : e.message);
    } on FormatException catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError('登录失败: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Theme.of(context).colorScheme.error),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('连接 Navidrome')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          children: [
            TextFormField(
              controller: _serverController,
              keyboardType: TextInputType.url,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                labelText: '服务器地址',
                hintText: '例如 192.168.1.10:4533',
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? '请输入服务器地址' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _usernameController,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(labelText: '用户名'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? '请输入用户名' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: '密码',
                suffixIcon: IconButton(
                  icon: Icon(_obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              onFieldSubmitted: (_) => _submitting ? null : _submit(),
              validator: (v) =>
                  (v == null || v.isEmpty) ? '请输入密码' : null,
            ),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('登录'),
            ),
          ],
        ),
      ),
    );
  }
}
