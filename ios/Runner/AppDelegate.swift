import UIKit
import Flutter

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // ✅ 彻底关闭 iOS 状态恢复（防止第二天恢复到无效路由导致黑屏）
  override func application(_ application: UIApplication,
                            shouldSaveApplicationState coder: NSCoder) -> Bool {
    return false
  }

  override func application(_ application: UIApplication,
                            shouldRestoreApplicationState coder: NSCoder) -> Bool {
    return false
  }
}
