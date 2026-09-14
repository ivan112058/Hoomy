import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/auth/auth_controller.dart';
import '../../data/subsonic/subsonic_client.dart';
import '../shared/hoomy_button.dart';
import '../shared/hoomy_focusable.dart';
import '../shared/hoomy_icon_button.dart';

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
    // 先取 messenger：登录成功后本页会被根路由换掉，提示仍要留在屏幕上。
    final messenger = ScaffoldMessenger.of(context);
    final notifier = ref.read(authProvider.notifier);
    try {
      await notifier.login(
        _serverController.text,
        _usernameController.text,
        _passwordController.text,
      );
      // 登录态由根路由监听，这里无需导航。
      if (!notifier.credentialsPersisted) {
        _showNotice(messenger, '凭据未能保存到本机，下次打开需要重新登录');
      }
    } on SubsonicException catch (e) {
      _showError(messenger, e.isAuthError ? '用户名或密码错误' : e.message);
    } on FormatException catch (e) {
      _showError(messenger, e.message);
    } catch (e) {
      _showError(messenger, '登录失败: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showError(ScaffoldMessengerState messenger, String message) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  /// 非错误的提醒（例如凭据存不下来）：用中性配色，不冒充失败。
  void _showNotice(ScaffoldMessengerState messenger, String message) {
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('连接 Navidrome')),
      // TV 上焦点必须能**离开**输入框（[HoomyTextFieldEscape]）：票据 07
      // 验收时暴露过「TV 登录页输入框拿不到焦点」，只修「进得去」不够 ——
      // 用上下键要能从服务器地址走到用户名、密码与登录按钮。
      body: HoomyTextFieldEscape(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            children: [
              TextFormField(
                controller: _serverController,
                keyboardType: TextInputType.url,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: '服务器地址',
                  hintText: '例如 192.168.1.10:4533',
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? '请输入服务器地址' : null,
                onFieldSubmitted: (_) =>
                    FocusScope.of(context).nextFocus(),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _usernameController,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: '用户名'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? '请输入用户名' : null,
                onFieldSubmitted: (_) =>
                    FocusScope.of(context).nextFocus(),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: '密码',
                  suffixIcon: HoomyIconButton(
                    icon: _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    tooltip: _obscurePassword ? '显示密码' : '隐藏密码',
                    iconSize: 20,
                    size: 40,
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                onFieldSubmitted: (_) => _submitting ? null : _submit(),
                validator: (v) =>
                    (v == null || v.isEmpty) ? '请输入密码' : null,
              ),
              const SizedBox(height: 32),
              // 用 HoomyButton 而不是 FilledButton：Material 按钮的聚焦反馈只是
              // 默认半透明叠加，TV 上这一步（进入应用的第一屏）必须看得清焦点。
              HoomyButton(
                filled: true,
                onPressed: _submitting ? null : _submit,
                minHeight: 48,
                child: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('登录'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
