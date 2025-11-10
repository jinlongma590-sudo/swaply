// android/build.gradle.kts (根目录)
// --------------------------------------------------
// 最终修复版 v4：
// 1. 声明插件版本，与 settings.gradle (1.9.24) 保持一致
// 2. (关键) 添加 subprojects 块，强制所有插件(如 share_plus)
//    也必须使用 1.9.24，解决 metadata 2.2.0 的错误。
// --------------------------------------------------

plugins {
    id("com.android.application") version "8.6.1" apply false

    // ★ 关键：保持 1.9.24
    id("org.jetbrains.kotlin.android") version "1.9.24" apply false

    id("dev.flutter.flutter-plugin-loader") version "1.0.0" apply false
}

// ★ 关键：添加这个 KTS 语法的全局约束 ★
// (这将修复 share_plus 和其他插件的 "incompatible metadata" 错误)
subprojects {
    configurations.all {
        resolutionStrategy.eachDependency {
            if (requested.group == "org.jetbrains.kotlin" && requested.name.startsWith("kotlin-")) {
                // 强制所有 Kotlin 依赖项使用 1.9.24
                useVersion("1.9.24")
                because("Force alignment with AGP-compatible Kotlin version 1.9.24")
            }
        }
    }
}