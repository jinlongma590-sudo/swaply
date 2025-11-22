flutter run 之后可用的过滤命令（手动复制执行）：
flutter run -d emulator-5554 | Select-String -Pattern '\[EMAIL-LOGIN\]|\[AuthFlowObserver\]|supabase\.auth|\[DeepLink\]|\[WelcomeDialog\]' | Tee-Object '.\.audit-email-login-20251122-225934\15-runtime-auth-filter.log'

