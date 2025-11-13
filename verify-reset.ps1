$ErrorActionPreference="Stop"
$DeepLinkScheme = "cc.swaply.app"
$DeepLinkHost   = "login-callback"
$WebHost        = "swaply.cc"

$Root  = (Get-Location).Path
$Lib   = Join-Path $Root "lib"
$Man   = Join-Path $Root "android\app\src\main\AndroidManifest.xml"
$Plist = Join-Path $Root "ios\Runner\Info.plist"

function ReadUtf8($p){ if(!(Test-Path $p)){ return $null }; [IO.File]::ReadAllText($p,[Text.UTF8Encoding]::new($false)) }

Write-Host "== Swaply Reset-Link 体检 ==" -ForegroundColor Cyan
Write-Host "Project: $Root"
Write-Host ("期望移动端回调  : {0}://{1}" -f $DeepLinkScheme,$DeepLinkHost) -ForegroundColor Gray
Write-Host ("期望 Web 回调   : https://{0}/auth/callback" -f $WebHost) -ForegroundColor Gray
Write-Host ""

if(!(Test-Path $Lib)){ throw "未找到 lib 目录：$Lib" }
$dartFiles = Get-ChildItem -Path $Lib -Recurse -Include *.dart

Write-Host "【redirectTo 参数】" -ForegroundColor Cyan
$redirectHits = Select-String -Path $dartFiles.FullName -Pattern 'redirectTo\s*:' -ErrorAction SilentlyContinue
if($redirectHits){
  $redirectHits | Select-Object -First 20 | ForEach-Object{
    Write-Host (" - {0}:{1}" -f $_.Path, $_.LineNumber) -ForegroundColor DarkGray
    Write-Host ("   {0}" -f $_.Line.Trim()) -ForegroundColor DarkGray
  }
  if(($redirectHits | Measure-Object).Count -gt 20){ Write-Host "   ...(仅显示前20处)" -ForegroundColor DarkGray }
}else{
  Write-Host "未找到 redirectTo 使用，可能导致白屏。" -ForegroundColor Yellow
}
Write-Host ""

Write-Host "【过期回调 io.supabase.flutter】" -ForegroundColor Cyan
$old = Select-String -Path $dartFiles.FullName -Pattern 'io\.supabase\.flutter://callback' -ErrorAction SilentlyContinue
if($old){
  Write-Host ("发现旧回调，请替换为 {0}://{1}" -f $DeepLinkScheme,$DeepLinkHost) -ForegroundColor Red
  $old | ForEach-Object{ Write-Host (" - {0}:{1}" -f $_.Path,$_.LineNumber) -ForegroundColor DarkGray }
} else {
  Write-Host "未发现旧回调引用。" -ForegroundColor Green
}
Write-Host ""

Write-Host "【passwordRecovery 监听】" -ForegroundColor Cyan
$pr = Select-String -Path $dartFiles.FullName -Pattern 'AuthChangeEvent\.passwordRecovery' -ErrorAction SilentlyContinue
if($pr){
  Write-Host "已监听 AuthChangeEvent.passwordRecovery ?" -ForegroundColor Green
  $pr | Select-Object -First 5 | ForEach-Object{ Write-Host (" - {0}:{1}" -f $_.Path,$_.LineNumber) -ForegroundColor DarkGray }
}else{
  Write-Host "未监听 passwordRecovery ?（点击邮件链接后可能白屏）" -ForegroundColor Red
}
Write-Host ""

Write-Host "【exchangeCodeForSession/recoverSessionFromUrl】" -ForegroundColor Cyan
$ex = Select-String -Path $dartFiles.FullName -Pattern 'exchangeCodeForSession|recoverSessionFromUrl' -ErrorAction SilentlyContinue
if($ex){
  Write-Host "找到 Session 置换调用 ?" -ForegroundColor Green
  $ex | Select-Object -First 5 | ForEach-Object{ Write-Host (" - {0}:{1}" -f $_.Path,$_.LineNumber) -ForegroundColor DarkGray }
}else{
  Write-Host "未找到，会导致 Web/通用链接无法进 Session ?" -ForegroundColor Red
}
Write-Host ""

Write-Host "【Android Manifest DeepLink】" -ForegroundColor Cyan
if(Test-Path $Man){
  $xml = New-Object System.Xml.XmlDocument
  $xml.PreserveWhitespace = $true
  $xml.Load($Man)
  $nsmgr = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
  $nsmgr.AddNamespace("android","http://schemas.android.com/apk/res/android")
  $dataNodes = $xml.SelectNodes("//intent-filter/data",$nsmgr)
  if($dataNodes){
    $ok = $false
    foreach($d in $dataNodes){
      $s = $d.GetAttribute("scheme","http://schemas.android.com/apk/res/android")
      $h = $d.GetAttribute("host","http://schemas.android.com/apk/res/android")
      if(!$s -and !$h){ continue }
      Write-Host (" - scheme={0}  host={1}" -f $s,$h) -ForegroundColor DarkGray
      if(($s -eq $DeepLinkScheme) -and ($h -eq $DeepLinkHost)){ $ok = $true }
    }
    if($ok){
      Write-Host "Android 回调匹配 ?" -ForegroundColor Green
    } else {
      Write-Host ( "未匹配到 {0}://{1} ?" -f $DeepLinkScheme,$DeepLinkHost ) -ForegroundColor Red
    }
  } else {
    Write-Host "未找到任何 <intent-filter><data .../>，需补。" -ForegroundColor Red
  }
}else{
  Write-Host "未找到 $Man" -ForegroundColor Yellow
}
Write-Host ""

Write-Host "【iOS CFBundleURLSchemes】" -ForegroundColor Cyan
if(Test-Path $Plist){
  $pt = ReadUtf8 $Plist
  $schemes = @()
  if($pt -match '<key>CFBundleURLTypes</key>\s*<array>(.*?)</array>'){
    $arr = $Matches[1]
    $m = [regex]::Matches($arr,'<string>(.*?)</string>')
    foreach($mm in $m){ $schemes += $mm.Groups[1].Value }
  }
  if($schemes.Count -gt 0){
    Write-Host ("检测到 iOS Schemes: " + ($schemes -join ", ")) -ForegroundColor DarkGray
    if($schemes -contains $DeepLinkScheme){
      Write-Host "iOS 回调匹配 ?" -ForegroundColor Green
    } else {
      Write-Host ( "iOS 未包含 {0} ?" -f $DeepLinkScheme ) -ForegroundColor Red
    }
  } else {
    Write-Host ( "未检测到 CFBundleURLSchemes，需添加 {0}。" -f $DeepLinkScheme ) -ForegroundColor Red
  }
}else{
  Write-Host "未找到 $Plist" -ForegroundColor Yellow
}
Write-Host ""

Write-Host "== 体检完成 ==" -ForegroundColor Cyan
