$ErrorActionPreference="Stop"
$AppGradle="android\app\build.gradle"

if(!(Test-Path $AppGradle)){ throw "未找到 $AppGradle" }
$content = Get-Content $AppGradle -Raw

# 升级 compileSdk（两种写法都兼容）
$content = $content -replace 'compileSdkVersion\s*\d+','compileSdkVersion 34'
$content = $content -replace 'compileSdk\s*=\s*\d+','compileSdk = 34'

# 注入 core-splashscreen 依赖
if($content -notmatch 'androidx\.core:core-splashscreen'){
  $content = $content -replace '(dependencies\s*\{)','$1' + "`r`n    implementation ""androidx.core:core-splashscreen:1.0.1"""
}

Set-Content $AppGradle -Value $content -Encoding UTF8
Write-Host "? 已更新 $AppGradle（compileSdk=34，添加 core-splashscreen）" -ForegroundColor Green
