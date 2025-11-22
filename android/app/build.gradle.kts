// android/app/build.gradle.kts

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    // ✅ 保持你的正式包名
    namespace = "cc.swaply.app"

    // ✅ 保持 36
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    // ✅ 关键改动：开启 desugaring，并把 Java 版本提升到 17
    compileOptions {
        // ★ 必开：支持 Java 8+/java.time 等 API（flutter_local_notifications 依赖）
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    // ✅ 同步把 Kotlin 目标版本设为 17
    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // ✅ 你的正式 applicationId
        applicationId = "cc.swaply.app"

        // 保持与工程一致
        minSdk = flutter.minSdkVersion

        // 保持 34，不触发更高 target 行为变更
        targetSdk = 34

        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // 使用 debug 签名以便 `flutter run --release`
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // ✅ 新增：desugaring 运行时库（版本按你给的建议）
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:1.2.2")

    // （可选但安全）Kotlin JDK8 扩展，Kotlin DSL 写法：
    implementation(kotlin("stdlib-jdk8"))

    implementation("androidx.core:core-splashscreen:1.0.1")
}
