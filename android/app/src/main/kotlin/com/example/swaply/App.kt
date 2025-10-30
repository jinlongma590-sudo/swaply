package com.example.swaply

import android.app.Application

class App : Application() {
    override fun onCreate() {
        super.onCreate()
        // 这里以后可以放全局初始化逻辑
    }
}