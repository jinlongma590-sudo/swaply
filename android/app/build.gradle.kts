// android/app/build.gradle.kts

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    // ✅ 改为你的正式包名
    namespace = "cc.swaply.app"

    // ✅ 提升到 36，满足各插件与 AndroidX 1.10/1.16 的要求（仅影响编译期，不改变旧机型行为）
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // ✅ 改为你的正式 applicationId（决定 Play 商店唯一性）
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
    implementation("androidx.core:core-splashscreen:1.0.1")
}
