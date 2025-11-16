param(
  [string]$ProjectRoot = (Get-Location).Path
)

$ErrorActionPreference = "Stop"
Set-Location $ProjectRoot
if (!(Test-Path .\pubspec.yaml)) {
  Write-Host "❌ 请先 cd 到 Flutter 项目根目录（能看到 pubspec.yaml）" -ForegroundColor Red
  exit 1
}

# 仅输出报告，不修改源码
Remove-Item -ErrorAction SilentlyContinue .\codecheck\welcome_audit*.*; mkdir -Force codecheck | Out-Null

function Section($t){ Write-Host "`n=== $t ===" -ForegroundColor Cyan }
function Pass($m){ Write-Host "PASS: $m" -ForegroundColor Green }
function Fail($m){ Write-Host "FAIL: $m" -ForegroundColor Red }

# 1) 全仓搜索旧函数“调用处”（排除函数定义本身）
Section "搜索 _showWelcomeGiftDialog() 的调用"
$calls = Select-String -Path .\lib\**\*.dart -Pattern '(?<!void\s)\b_showWelcomeGiftDialog\s*\(' -AllMatches
if ($calls) {
  $calls | Format-Table Path,LineNumber,Line -AutoSize | Tee-Object .\codecheck\welcome_audit_calls.txt | Out-Host
  Fail "发现 $(@($calls).Count) 处对 _showWelcomeGiftDialog 的调用（详见 codecheck\welcome_audit_calls.txt）"
} else {
  Pass "未发现任何调用（OK）"
}

# 2) main.dart 中是否存在“空实现存根”
Section "检查 main.dart 中是否存在空存根"
$stub = Select-String -Path .\lib\main.dart -Pattern 'void\s+_showWelcomeGiftDialog\s*\('
if ($stub) { Pass "存根已存在（OK）" } else { Fail "未找到 _showWelcomeGiftDialog 存根，请确认 main.dart 已更新" }

# 3) 旧本地键是否在别处还被使用
Section "搜索旧本地键 new_user_welcome_pending_/welcome_gift_shown_ 的使用"
$keys = Select-String -Path .\lib\**\*.dart -Pattern 'welcome_gift_shown_|new_user_welcome_pending_' -AllMatches
if ($keys) {
  $outside = $keys | Where-Object { $_.Path -notlike '*main.dart' }
  if ($outside) {
    $outside | Format-Table Path,LineNumber,Line -AutoSize | Tee-Object .\codecheck\welcome_audit_keys_outside_main.txt | Out-Host
    Fail "在 main.dart 之外仍有旧键引用（详见 codecheck\welcome_audit_keys_outside_main.txt）"
  } else {
    Pass "旧键只在 main.dart 内（登录时已做统一清理，OK）"
  }
} else {
  Pass "未检出旧键（OK）"
}

# 4) 新弹窗是否存在 & 是否被引用
Section "检查新弹窗 WelcomeCouponDialog 接线情况"
$widgetFile = '.\lib\widgets\welcome_coupon_dialog.dart'
if (Test-Path $widgetFile) { Pass "找到组件文件 $widgetFile" } else { Fail "未找到 $widgetFile，请确认已添加" }

$refs = Select-String -Path .\lib\**\*.dart -Pattern 'WelcomeCouponDialog' -AllMatches
if ($refs) {
  $refs | Format-Table Path,LineNumber,Line -AutoSize | Tee-Object .\codecheck\welcome_audit_new_refs.txt | Out-Host
  Pass "已找到对 WelcomeCouponDialog 的引用（见 codecheck\welcome_audit_new_refs.txt）"
} else {
  Fail "未找到对 WelcomeCouponDialog 的任何引用，请确认页面侧的 showDialog 已接入新弹窗"
}

# 5) 兜底：搜是否存在含 “Welcome” 的 AlertDialog（可能是旧UI）
Section "兜底搜索含 Welcome 的 AlertDialog"
$legacy = Select-String -Path .\lib\**\*.dart -Pattern 'AlertDialog[^\r\n]*Welcome' -AllMatches
if ($legacy) {
  $legacy | Format-Table Path,LineNumber,Line -AutoSize | Tee-Object .\codecheck\welcome_audit_legacy_alerts.txt | Out-Host
  Write-Host "NOTE: 以上可能包含无关的欢迎类弹窗，仅供人工复核。" -ForegroundColor Yellow
} else {
  Pass "未发现含 Welcome 的 AlertDialog（OK）"
}

Write-Host "`n—— 汇总 ——"
if ($calls -or (-not $stub) -or ($outside) -or (-not (Test-Path $widgetFile)) -or (-not $refs)) {
  Write-Host "⚠ 有检查项需要关注；详见 codecheck/ 目录的报告文件" -ForegroundColor Yellow
  exit 2
} else {
  Write-Host "✅ 全部检查通过：旧弹窗不会再弹，且新弹窗组件已接线" -ForegroundColor Green
}
