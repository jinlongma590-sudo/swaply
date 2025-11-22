// lib/pages/account_settings_page.dart
import 'package:flutter/foundation.dart'; // 鉁?For platform check
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:swaply/services/auth_service.dart'; // ✅ 新增：统一走 AuthService 登出
import 'package:swaply/services/auth_flow_observer.dart'; // ✅ 新增 Observer
import 'package:swaply/router/root_nav.dart';
class AccountSettingsPage extends StatefulWidget {
  const AccountSettingsPage({super.key});

  @override
  State<AccountSettingsPage> createState() => _AccountSettingsPageState();
}

class _AccountSettingsPageState extends State<AccountSettingsPage> {
  final _pwdCtrl = TextEditingController();
  bool _ack = false;
  bool _deleting = false;

  // 鉁?闃叉姈锛氬垹闄ゆ垚鍔熷悗鐨?signOut 鍙厑璁歌Е鍙戜竴娆★紝闃叉鐑噸杞?閲嶅缓瀵艰嚧閲嶅鐧诲嚭
  bool _logoutAfterDeletionOnce = false;

  @override
  void dispose() {
    _pwdCtrl.dispose();
    super.dispose();
  }

  bool get _canSubmit => _ack && _pwdCtrl.text.trim().isNotEmpty && !_deleting;

  // 椤堕儴鏄剧溂閿欒妯箙
  void _showErrorBanner(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.hideCurrentMaterialBanner();

    HapticFeedback.heavyImpact(); // 闇囧姩鎻愮ず

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

    // 4 绉掑悗鑷姩闅愯棌
    Future.delayed(const Duration(seconds: 4), () {
      if (!mounted) return;
      messenger.hideCurrentMaterialBanner();
    });
  }

  // 鎴愬姛鎻愮ず锛堝簳閮?Snackbar锛?
  void _showSuccessSnack(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentMaterialBanner();
    messenger.showSnackBar(
      SnackBar(
        content: const Row(
          children: [
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

  // 鉁?纭寮圭獥锛氳緭鍏?DELETE 鎵嶈兘缁х画
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

    // 涓嶆墜鍔?dispose锛岄伩鍏嶈繃娓℃湡鏂█宕╂簝
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

      final data = (res.data is Map) ? (res.data as Map) : const {};
      final ok = data['ok'] == true;

      if (ok) {
        // 鉁?鍏堟彁绀猴紝鍐嶁€滃彧瑙﹀彂涓€娆♀€濈櫥鍑猴紝闅忓悗閫€鍑哄埌鏍癸紙闃绘柇褰撳墠椤甸噸寤哄鑷寸殑閲嶅閫昏緫锛?
        if (mounted) {
          _showSuccessSnack('Account deleted.');
        }

        if (!_logoutAfterDeletionOnce) {
          _logoutAfterDeletionOnce = true;
          try {
            // 统一从 AuthService 登出，并打印调用栈，便于追踪来源
            debugPrint(
                '[[SIGNOUT-TRACE]] account_settings_page -> direct signOut');
            debugPrint(StackTrace.current.toString());

            // ✅ 1) 标记快车道
            AuthFlowObserver.I.markManualSignOut();
            // ✅ 2) 执行登出
            await AuthService().signOut();
          } catch (_) {/* 闈欓粯 */}
        }

        if (!mounted) return;
        // 鍥炲埌鏍硅矾鐢憋紙鎴栨寜浣犻」鐩敼涓?SafeNavigator.pushNamedAndRemoveUntil('/welcome', (_) => false)锛?
        rootNavKey.currentState?.popUntil((r) => r.isFirst);
        return;
      } else {
        final msg = (data['error'] ?? 'Delete failed').toString();
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

  // 鉁?缁熶竴鐨?AppBar 鏋勫缓鍣?(涓庡叾浠栭〉闈㈤鏍间竴鑷?
  PreferredSizeWidget _buildStandardAppBar(BuildContext context) {
    const String title = 'Account';
    final double statusBar = MediaQuery.of(context).padding.top;
    final bool isIOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
    const Color kBgColor = Color(0xFF2563EB);

    // Android & 鍏朵粬骞冲彴锛氭爣鍑?AppBar
    if (!isIOS) {
      return AppBar(
        title: const Text(
          title,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        backgroundColor: kBgColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      );
    }

    // iOS锛?4pt 鑷畾涔夊鑸爮
    const double kNavBarHeight = 44.0;
    const double kButtonSize = 32.0;
    const double kSidePadding = 16.0;
    const double kButtonSpacing = 12.0;

    final Widget iosBackButton = SizedBox(
      width: kButtonSize,
      height: kButtonSize,
      child: GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: const Icon(Icons.arrow_back_ios_new,
              size: 18, color: Colors.white),
        ),
      ),
    );

    const Widget iosTitle = Expanded(
      child: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 18,
        ),
      ),
    );

    const Widget iosRightPlaceholder =
    SizedBox(width: kButtonSize, height: kButtonSize);

    return PreferredSize(
      preferredSize: Size.fromHeight(statusBar + kNavBarHeight),
      child: Container(
        color: kBgColor,
        padding: EdgeInsets.only(top: statusBar),
        child: SizedBox(
          height: kNavBarHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: kSidePadding),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                iosBackButton,
                const SizedBox(width: kButtonSpacing),
                iosTitle,
                const SizedBox(width: kButtonSpacing),
                iosRightPlaceholder,
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final danger = Theme.of(context).colorScheme.error;
    return Scaffold(
      appBar: _buildStandardAppBar(context),
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
                  onChanged: (v) => setState(() => _ack = (v ?? false)),
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