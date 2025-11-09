// android/settings.gradle.kts

pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
        maven("https://storage.googleapis.com/download.flutter.io")
    }

    // 解析 Flutter SDK 路径（优先环境变量，其次 local.properties，最后兜底 C:/flutter）
    val flutterSdkPath: String = run {
        val env = System.getenv("FLUTTER_ROOT")
        if (!env.isNullOrBlank()) {
            env.replace("\\", "/")
        } else {
            val localProps = java.io.File(rootDir, "local.properties")
            if (localProps.exists()) {
                val text = localProps.readText()
                val sdk = Regex("""^\s*flutter\.sdk\s*=\s*(.+)\s*$""", RegexOption.MULTILINE)
                    .find(text)
                    ?.groupValues?.get(1)
                    ?.trim()
                (sdk ?: "C:/flutter").replace("\\", "/")
            } else {
                "C:/flutter"
            }
        }
    }

    // 引入 Flutter 的 Gradle 辅助工程，提供 dev.flutter.flutter-plugin-loader 插件
    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")
}

plugins {
    // Flutter 插件从 includeBuild 提供，此处不写版本号
    id("dev.flutter.flutter-plugin-loader")

    // 仅声明版本，不在 settings 中应用
    id("com.android.application") version "8.4.2" apply false
    id("org.jetbrains.kotlin.android") version "1.9.24" apply false
}

@Suppress("UnstableApiUsage")
dependencyResolutionManagement {
    // 统一在 settings 声明仓库，禁止各模块再行声明
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
        maven("https://storage.googleapis.com/download.flutter.io")
    }
}

rootProject.name = "swaply"
include(":app")
