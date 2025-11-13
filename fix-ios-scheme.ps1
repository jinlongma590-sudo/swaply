$ErrorActionPreference="Stop"
$Plist = "ios\Runner\Info.plist"
$Scheme = "cc.swaply.app"

if(!(Test-Path $Plist)){ Write-Error "[iOS] 未找到 $Plist"; exit 1 }

function TS { (Get-Date).ToString("yyyyMMddHHmmss") }
Copy-Item $Plist "$Plist.bak.$(TS)" -Force

$pt = Get-Content $Plist -Raw

# 1) 若没有 CFBundleURLTypes，整块插入
if($pt -notmatch '<key>CFBundleURLTypes</key>'){
  $block = @"
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLSchemes</key>
      <array>
        <string>$Scheme</string>
      </array>
    </dict>
  </array>
"@
  $pt = $pt -replace '</dict>\s*</plist>',("$block`r`n</dict></plist>")
  Set-Content $Plist -Value $pt -Encoding UTF8
  Write-Host "? 已新增 CFBundleURLTypes / CFBundleURLSchemes = $Scheme" -ForegroundColor Green
  exit 0
}

# 2) 已有 CFBundleURLTypes，但未包含 cc.swaply.app，则在第一个 CFBundleURLSchemes 数组里追加
if($pt -notmatch '<string>cc\.swaply\.app</string>'){
  # 在第一个 <key>CFBundleURLSchemes</key><array> 后面插入一行 <string>cc.swaply.app</string>
  $pt = $pt -replace '(<key>CFBundleURLSchemes</key>\s*<array>)',("`$1`r`n        <string>$Scheme</string>")
  Set-Content $Plist -Value $pt -Encoding UTF8
  Write-Host "? 已追加 Scheme: $Scheme" -ForegroundColor Green
} else {
  Write-Host "· iOS 已包含 Scheme: $Scheme" -ForegroundColor DarkGray
}
