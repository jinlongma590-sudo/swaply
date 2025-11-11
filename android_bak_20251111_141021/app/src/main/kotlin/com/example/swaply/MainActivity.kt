package com.example.swaply

import android.os.Bundle
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // 安装官方 Android 12+ 的启动屏
        installSplashScreen()
        super.onCreate(savedInstanceState)
    }
}