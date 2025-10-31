// lib/pages/account_settings_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AccountSettingsPage extends StatefulWidget {
  const AccountSettingsPage({Key? key}) : super(key: key);

  @override
  State<AccountSettingsPage> createState() => _AccountSettingsPageState();
}

class _AccountSettingsPageState extends State<AccountSettingsPage> {
  final _pwdCtrl = TextEditingController();
  bool _ack = false;
  bool _deleting = false;

  @override
  void dispose() {
    _pwdCtrl.dispose();
    super.dispose();
  }

  bool get _canSubmit => _ack && _pwdCtrl.text.trim().isNotEmpty && !_deleting;

  // 顶部显眼错误横幅
  void _showErrorBanner(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.hideCurrentMaterialBanner();

    HapticFeedback.heavyImpact(); // 震动提示

    messenger.showMaterialBanner(
      MaterialBanner(
        backgroundColor: Colors.red.shade600,
        leading: const Icon(Icons.error_outline, color: Colors.white),
        content: Text(
          message,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => messenger.hideCurrentMaterialBanner(),
            child: const Text('Dismiss', style: TextStyle(color: Colors.white)),
          ),
        ],
        forceActionsBelow: false,
      ),
    );

    // 4 秒后自动隐藏
    Future.delayed(const Duration(seconds: 4), () {
      if (!mounted) return;
      messenger.hideCurrentMaterialBanner();
    });
  }

  // 成功提示（保留底部 Snackbar，但样式更显眼）
  void _showSuccessSnack(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentMaterialBanner();
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: const [
            Icon(Icons.check_circle_rounded, color: Colors.white),
            SizedBox(width: 8),
            Expanded(child: Text('Account deleted.')),
          ],
        ),
        backgroundColor: Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ✅ 确认弹窗：输入 DELETE 才能继续
  Future<bool> _finalConfirm() async {
    final ctrl = TextEditingController();
    bool canConfirm = false;

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setState) => AlertDialog(
            title: const Text(
              'Type DELETE to confirm',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            content: TextField(
              controller: ctrl,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'DELETE',
              ),
              onChanged: (v) {
                setState(() {
                  canConfirm = v.trim().toUpperCase() == 'DELETE';
                });
              },
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel', style: TextStyle(fontSize: 16)),
              ),
              ElevatedButton(
                onPressed: canConfirm ? () => Navigator.pop(ctx, true) : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: const Text('Confirm'),
              ),
            ],
          ),
        );
      },
    );

    // 不手动 dispose，避免过渡期断言崩溃
    return ok ?? false;
  }

  Future<void> _deleteAccount() async {
    if (!_canSubmit) return;
    if (!await _finalConfirm()) return;

    setState(() => _deleting = true);
    final client = Supabase.instance.client;

    try {
      final res = await client.functions.invoke(
        'delete_account',
        body: {
          'confirm': true,
          'password': _pwdCtrl.text.trim(),
          'reason': 'user_request',
        },
      );

      final data = (res.data is Map) ? (res.data as Map) : {};
      if (data['ok'] == true) {
        await client.auth.signOut();
        if (!mounted) return;
        bool pushed = false;
        try {
          Navigator.of(context).pushNamedAndRemoveUntil('/login', (r) => false);
          pushed = true;
        } catch (_) {}
        if (!pushed && mounted) {
          Navigator.of(context).popUntil((r) => r.isFirst);
        }
        if (mounted) _showSuccessSnack('Account deleted.');
      } else {
        final msg = data['error']?.toString() ?? 'Delete failed';
        throw Exception(msg);
      }
    } catch (e) {
      if (mounted) {
        final message = e.toString();
        final lower = message.toLowerCase();
        final wrongPwd = lower.contains('403') ||
            lower.contains('wrong password') ||
            lower.contains('password');
        final friendly = wrongPwd
            ? 'Password is incorrect.'
            : message.replaceFirst('Exception: ', '');
        _showErrorBanner(friendly);
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final danger = Theme.of(context).colorScheme.error;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Account',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.lock_outline),
              title: const Text(
                'Security',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                'Password, devices (coming soon)',
                style: TextStyle(fontSize: 15, color: Colors.grey[600]),
              ),
              onTap: () {},
            ),
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: danger.withOpacity(.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: danger.withOpacity(.2)),
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: danger, size: 22),
                    const SizedBox(width: 8),
                    Text(
                      'Danger Zone',
                      style: TextStyle(
                        color: danger,
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'This will permanently delete your profile, listings, messages, notifications, favorites, coupons and all media files. This action cannot be undone.',
                  style: TextStyle(fontSize: 15, height: 1.45),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _pwdCtrl,
                  obscureText: true,
                  style: const TextStyle(fontSize: 16),
                  decoration: const InputDecoration(
                    labelText: 'Current password',
                    labelStyle: TextStyle(fontSize: 15),
                    hintText: 'Enter your password',
                    hintStyle: TextStyle(fontSize: 15),
                    border: OutlineInputBorder(),
                  ),
                ),
                CheckboxListTile(
                  value: _ack,
                  onChanged: (v) => setState(() => _ack = v ?? false),
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'I understand this will permanently delete my account and data.',
                    style: TextStyle(fontSize: 15, height: 1.4),
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _canSubmit ? _deleteAccount : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          _canSubmit ? danger : danger.withOpacity(.5),
                      textStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: _deleting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Delete My Account'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
