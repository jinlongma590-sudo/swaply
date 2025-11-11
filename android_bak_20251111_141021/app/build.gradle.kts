// android/app/build.gradle.kts

import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
}

// 读取 key.properties
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        load(keystorePropertiesFile.inputStream())
    }
}

android {
    namespace = "com.example.swaply"
    compileSdk = 35

    // ✅ 钉死 NDK 版本，避免找错目录
    ndkVersion = "26.1.10909125"

    defaultConfig {
        applicationId = "com.example.swaply"
        minSdk = 21
        targetSdk = 35
        versionCode = flutter.versionCode.toInt()
        versionName = flutter.versionName
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions { jvmTarget = "11" }

    // ★ 正式签名配置（读取 key.properties）
    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        // Debug 运行：不开压缩、不瘦身（避免 “shrinkResources 需开启 minify” 报错）
        getByName("debug") {
            isMinifyEnabled = false
            isShrinkResources = false
        }
        // Release 上架：开启 R8 压缩 + 资源瘦身
        getByName("release") {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
            // 若项目没有 proguard-rules.pro，可在 android/app 下创建一个空文件
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("androidx.core:core-splashscreen:1.0.1")
    implementation("androidx.core:core-ktx:1.13.1")
}
// --- 关键修复：强制所有插件使用统一的 Kotlin 版本 ---
configurations.all {
    resolutionStrategy.eachDependency {
        if (requested.group == "org.jetbrains.kotlin" && requested.name.startsWith("kotlin-")) {
            // 在 settings.gradle 中我们定义了 1.9.24，所以这里也用 1.9.24
            useVersion("1.9.24")
        }
    }
}