// android/build.gradle.kts (根目录)
// --------------------------------------------------
// 最终修复版 v5：
// 1. 声明插件版本，与 settings.gradle (2.0.0) 保持一致
// 2. (关键) 添加 subprojects 块，强制所有插件(如 share_plus)
//    也必须降级到 2.0.0，解决 metadata 2.2.0 的错误。
// --------------------------------------------------

plugins {
    id("com.android.application") version "8.6.1" apply false

    // ★ 关键：保持 2.0.0
    id("org.jetbrains.kotlin.android") version "2.0.0" apply false

    id("dev.flutter.flutter-plugin-loader") version "1.0.0" apply false
}

// ★ 关键：添加这个 KTS 语法的全局约束 ★
// (这将修复 share_plus 的 "incompatible metadata 2.2.0" 错误)
subprojects {
    configurations.all {
        resolutionStrategy.eachDependency {
            if (requested.group == "org.jetbrains.kotlin" && requested.name.startsWith("kotlin-")) {
                // 强制所有 Kotlin 依赖项使用 2.0.0
                useVersion("2.0.0")
                because("Force alignment with AGP-compatible Kotlin version 2.0.0")
            }
        }
    }
}