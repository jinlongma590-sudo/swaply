import org.gradle.api.file.Directory

plugins {
    id("com.android.application") version "8.4.2" apply false
    id("org.jetbrains.kotlin.android") version "1.9.24" apply false
// Flutter Gradle plugin is provided via settings.gradle.kts includeBuild
    id("dev.flutter.flutter-plugin-loader") version "1.0.0" apply false
}

// 🚫 不要在这里声明 repositories（已在 settings.gradle.kts 里统一配置）

// 可选：自定义根构建产物目录（沿用你原来的逻辑）
val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.set(newBuildDir)

subprojects {
    val newSubprojectBuildDir = rootProject.layout.buildDirectory.dir(name)
    layout.buildDirectory.set(newSubprojectBuildDir)
}

subprojects {
    evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}