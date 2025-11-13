$ErrorActionPreference = "Stop"

# === 统一目标回调 ===
$DeepLinkScheme = "cc.swaply.app"
$DeepLinkHost   = "login-callback"
$WebHost        = "swaply.cc"

# === 路径 ===
$Root  = (Get-Location).Path
$Lib   = Join-Path $Root "lib"
$Man   = Join-Path $Root "android\app\src\main\AndroidManifest.xml"
$Plist = Join-Path $Root "ios\Runner\Info.plist"

function TS { (Get-Date).ToString("yyyyMMddHHmmss") }
function Save-Bak($path){ if(Test-Path $path){ Copy-Item $path "$path.bak.$(TS)" -Force } }

Write-Host "== Swaply Reset-Link 一键修复 ==" -ForegroundColor Cyan
Write-Host ("目标回调：{0}://{1} | https://{2}/auth/callback" -f $DeepLinkScheme,$DeepLinkHost,$WebHost) -ForegroundColor Gray
Write-Host ""

# ========== 1) Dart 全量修复 ==========
if(!(Test-Path $Lib)){ throw "未找到 lib 目录：$Lib" }
$dartFiles = Get-ChildItem -Path $Lib -Recurse -Include *.dart

# 1A) 替换旧回调 io.supabase.flutter://callback
$oldCount = 0
foreach($f in $dartFiles){
  $txt = Get-Content $f.FullName -Raw
  if($txt -match 'io\.supabase\.flutter://callback'){
    Save-Bak $f.FullName
    $new = $txt -replace 'io\.supabase\.flutter://callback',("$($DeepLinkScheme)://$($DeepLinkHost)")
    Set-Content $f.FullName -Value $new -Encoding UTF8
    $oldCount++
    Write-Host ("? 替换旧回调 -> {0}" -f $f.FullName) -ForegroundColor Green
  }
}

# 1B) 统一 redirectTo 参数（含 forgot/login/register/oauth 等）
$reRedirectArg = [regex]'redirectTo\s*:\s*[^,\)\}]+'
$targetExpr = "redirectTo: (kIsWeb ? 'https://${WebHost}/auth/callback' : '${DeepLinkScheme}://${DeepLinkHost}')"
$chg = 0
foreach($f in $dartFiles){
  $txt = Get-Content $f.FullName -Raw
  if($reRedirectArg.IsMatch($txt)){
    $new = $reRedirectArg.Replace($txt,$targetExpr)
    if($new -ne $txt){
      Save-Bak $f.FullName
      if(($new -match 'kIsWeb') -and ($new -notmatch "package:flutter/foundation.dart")){
        $new = "import 'package:flutter/foundation.dart';`r`n" + $new
      }
      Set-Content $f.FullName -Value $new -Encoding UTF8
      $chg++
      Write-Host ("? 统一 redirectTo -> {0}" -f $f.FullName) -ForegroundColor Green
    }
  }
}

# 1C) 统一常量：kAuthRedirectUri / kAuthRedirectUrl / kAuthWebRedirect
$reUri  = [regex]'kAuthRedirectUri\s*=\s*["''].*?["'']'
$reUrl  = [regex]'kAuthRedirectUrl\s*=\s*["''].*?["'']'
$reWeb  = [regex]'kAuthWebRedirect\s*=\s*["''].*?["'']'
foreach($f in $dartFiles){
  $txt = Get-Content $f.FullName -Raw
  $orig = $txt
  $txt = $reUri.Replace($txt,("kAuthRedirectUri = '${DeepLinkScheme}://${DeepLinkHost}'"))
  $txt = $reUrl.Replace($txt,("kAuthRedirectUrl = '${DeepLinkScheme}://${DeepLinkHost}'"))
  $txt = $reWeb.Replace($txt,("kAuthWebRedirect = 'https://${WebHost}/auth/callback'"))
  if($orig -ne $txt){
    Save-Bak $f.FullName
    Set-Content $f.FullName -Value $txt -Encoding UTF8
    Write-Host ("? 统一常量 -> {0}" -f $f.FullName) -ForegroundColor Green
  }
}

# ========== 2) AndroidManifest Deep Link ==========
if(Test-Path $Man){
  Write-Host "[Android] 修复 AndroidManifest.xml" -ForegroundColor Cyan
  Save-Bak $Man
  $xml = New-Object System.Xml.XmlDocument
  $xml.PreserveWhitespace = $true
  $xml.Load($Man)
  $nsmgr = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
  $nsmgr.AddNamespace("android","http://schemas.android.com/apk/res/android")

  # 定位 MAIN Activity（不行则取第一个 activity）
  $activity = $xml.SelectSingleNode("//activity[intent-filter/action[@android:name='android.intent.action.MAIN']]", $nsmgr)
  if(-not $activity){ $activity = $xml.SelectSingleNode("//application/activity[1]", $nsmgr) }
  if(-not $activity){ throw "未找到 <activity> 节点" }

  # 2A) 删除 io.supabase.flutter://callback 的 <data>
  $oldNodes = $xml.SelectNodes("//intent-filter/data[@android:scheme='io.supabase.flutter' and @android:host='callback']", $nsmgr)
  foreach($n in @($oldNodes)){
    $parent = $n.ParentNode
    $parent.RemoveChild($n) | Out-Null
    Write-Host "? 移除 io.supabase.flutter://callback" -ForegroundColor Green
  }

  # 2B) 把所有 scheme=swaply 的 <data> 统一改为 cc.swaply.app（保留各自 host，如 login-callback / reset-password）
  $swaplyNodes = $xml.SelectNodes("//intent-filter/data[@android:scheme='swaply']", $nsmgr)
  foreach($n in @($swaplyNodes)){
    $n.SetAttribute("scheme","http://schemas.android.com/apk/res/android",$DeepLinkScheme) | Out-Null
    Write-Host ("? 统一 scheme=swaply -> {0}" -f $DeepLinkScheme) -ForegroundColor Green
  }

  # 2C) 若不存在 {scheme=cc.swaply.app, host=login-callback} 的 <data>，则追加一个完整 intent-filter
  $existing = $xml.SelectNodes("//intent-filter/data[@android:scheme='$DeepLinkScheme' and @android:host='$DeepLinkHost']",$nsmgr)
  if($existing.Count -eq 0){
    $if = $xml.CreateElement("intent-filter")
    $act = $xml.CreateElement("action")
    $act.SetAttribute("name","http://schemas.android.com/apk/res/android","android.intent.action.VIEW") | Out-Null
    $if.AppendChild($act) | Out-Null
    $cat1 = $xml.CreateElement("category")
    $cat1.SetAttribute("name","http://schemas.android.com/apk/res/android","android.intent.category.DEFAULT") | Out-Null
    $if.AppendChild($cat1) | Out-Null
    $cat2 = $xml.CreateElement("category")
    $cat2.SetAttribute("name","http://schemas.android.com/apk/res/android","android.intent.category.BROWSABLE") | Out-Null
    $if.AppendChild($cat2) | Out-Null
    $data = $xml.CreateElement("data")
    $data.SetAttribute("scheme","http://schemas.android.com/apk/res/android",$DeepLinkScheme) | Out-Null
    $data.SetAttribute("host","http://schemas.android.com/apk/res/android",$DeepLinkHost)   | Out-Null
    $if.AppendChild($data) | Out-Null
    $activity.AppendChild($if) | Out-Null
    Write-Host ("? 追加 {0}://{1}" -f $DeepLinkScheme,$DeepLinkHost) -ForegroundColor Green
  } else {
    Write-Host "· 已包含 {scheme=$DeepLinkScheme, host=$DeepLinkHost}" -ForegroundColor DarkGray
  }

  $xml.Save($Man)
} else {
  Write-Host "[Android] 未找到 $Man，跳过" -ForegroundColor Yellow
}

# ========== 3) iOS Info.plist ==========
if(Test-Path $Plist){
  Write-Host "[iOS] 修复 Info.plist" -ForegroundColor Cyan
  $pt = Get-Content $Plist -Raw
  if($pt -notmatch '<key>CFBundleURLTypes</key>'){
    Save-Bak $Plist
    $block = @"
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLSchemes</key>
      <array>
        <string>${DeepLinkScheme}</string>
      </array>
    </dict>
  </array>
"@
    $pt = $pt -replace '</dict>\s*</plist>',("$block`r`n</dict></plist>")
    Set-Content $Plist -Value $pt -Encoding UTF8
    Write-Host ("? 新增 CFBundleURLSchemes: {0}" -f $DeepLinkScheme) -ForegroundColor Green
  } elseif($pt -notmatch "<string>\Q${DeepLinkScheme}\E</string>") {
    Save-Bak $Plist
    $pt = $pt -replace '(<key>CFBundleURLSchemes</key>\s*<array>)',("`$1`r`n      <string>${DeepLinkScheme}</string>")
    Set-Content $Plist -Value $pt -Encoding UTF8
    Write-Host ("? 追加 Scheme: {0}" -f $DeepLinkScheme) -ForegroundColor Green
  } else {
    Write-Host "· 已包含目标 Scheme" -ForegroundColor DarkGray
  }
} else {
  Write-Host "[iOS] 未找到 $Plist，跳过" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "== 修复完成 ==" -ForegroundColor Cyan
Write-Host "Supabase → Auth → URL Configuration → Additional Redirect URLs 请确保包含：" -ForegroundColor Cyan
Write-Host ("  - {0}://{1}" -f $DeepLinkScheme,$DeepLinkHost) -ForegroundColor Gray
Write-Host ("  - https://{0}/auth/callback" -f $WebHost) -ForegroundColor Gray
