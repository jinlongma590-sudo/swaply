// ios/Runner/AppDelegate.swift
import UIKit
import Flutter
import supabase_flutter // ✅ 关键：导入 Supabase 包

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // ✅ 关键：添加这个方法来捕获并转发 URL
  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey : Any] = [:]
  ) -> Bool {
    // 将 URL 转发给 Supabase 插件
    Supabase.instance.client.auth.handleDeepLink(url)
    return super.application(app, open: url, options: options)
  }
}