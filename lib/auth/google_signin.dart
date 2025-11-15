import 'package:flutter/foundation.dart';
// lib/auth/google_signin.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
// for LaunchMode

const String _kIOSRedirect = 'cc.swaply.app://login-callback';

class GoogleSignInButton extends StatelessWidget {
  final VoidCallback? onBefore;
  final VoidCallback? onAfter;

  const GoogleSignInButton({super.key, this.onBefore, this.onAfter});

  Future<void> _startGoogleOAuth(BuildContext context) async {
    onBefore?.call();
    try {
      await Supabase.instance.client.auth.signInWithOAuth(
        OAuthProvider.google, // 鈫?杩欓噷涓€瀹氳鏈夐€楀彿
        // 鍙湪 iOS 浼?deep link锛孉ndroid 浼?null
        redirectTo: (kIsWeb ? 'https://swaply.cc/auth/callback' : 'cc.swaply.app://login-callback'),
        // iOS 蹇呴』鐢ㄥ閮ㄥ簲鐢紝閬垮厤鍐呭祵椤靛叧涓嶆帀
        authScreenLaunchMode: LaunchMode.externalApplication,
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Google 鐧诲綍澶辫触锛?e')),
      );
    } finally {
      onAfter?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: () => _startGoogleOAuth(context),
      child: const Text('Continue with Google'),
    );
  }
}


