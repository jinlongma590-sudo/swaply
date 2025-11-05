// ios/Runner/AppDelegate.swift
import UIKit
import Flutter
import flutter_web_auth_2   // 👈 关键：导入插件

@main
@objc class AppDelegate: FlutterAppDelegate {

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // 处理自定义 Scheme 回调（swaply://...），自动结束 ASWebAuthenticationSession
  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey : Any] = [:]
  ) -> Bool {
    if FlutterWebAuth2Plugin.resume(with: url) {
      return true
    }
    return super.application(app, open: url, options: options)
  }

  // 兼容某些场景的通用链接（通常用不到，但保留更稳）
  override func application(
    _ application: UIApplication,
    continue userActivity: NSUserActivity,
    restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
  ) -> Bool {
    if let url = userActivity.webpageURL, FlutterWebAuth2Plugin.resume(with: url) {
      return true
    }
    return super.application(application, continue: userActivity, restorationHandler: restorationHandler)
  }
}
