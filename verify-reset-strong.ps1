$ErrorActionPreference="Stop"
$Root  = (Get-Location).Path
$Lib   = Join-Path $Root "lib"
$Man   = Join-Path $Root "android\app\src\main\AndroidManifest.xml"
$Plist = Join-Path $Root "ios\Runner\Info.plist"
$Scheme="cc.swaply.app"; $DeepLinkHost="login-callback"

Write-Host "== Strong Verify ==" -ForegroundColor Cyan

# --- Android ---
if(Test-Path $Man){
  $xml = New-Object System.Xml.XmlDocument
  $xml.PreserveWhitespace=$true
  $xml.Load($Man)
  $nsm = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
  $nsm.AddNamespace("android","http://schemas.android.com/apk/res/android")

  $main = $xml.SelectSingleNode("//activity[intent-filter/action[@android:name='android.intent.action.MAIN']]", $nsm)
  if($null -eq $main){
    Write-Host "Android: δ�ҵ� MAIN activity" -ForegroundColor Red
  } else {
    $exp  = $main.GetAttribute("exported","http://schemas.android.com/apk/res/android")
    if([string]::IsNullOrEmpty($exp)){ $expText = "<nil>" } else { $expText = $exp }

    $data = $main.SelectNodes(".//intent-filter/data", $nsm)
    $ok   = $false
    foreach($d in $data){
      $s=$d.GetAttribute("scheme","http://schemas.android.com/apk/res/android")
      $h=$d.GetAttribute("host","http://schemas.android.com/apk/res/android")
      if($s -eq $Scheme -and $h -eq $DeepLinkHost){ $ok=$true }
    }
    if($ok){ $mainText="YES" } else { $mainText="NO" }
    Write-Host ("Android: exported={0} ; {1}://{2} on MAIN={3}" -f $expText,$Scheme,$DeepLinkHost,$mainText)
  }
}else{
  Write-Host "Android: Manifest ȱʧ" -ForegroundColor Yellow
}

# --- iOS ---
if(Test-Path $Plist){
  $txt = Get-Content $Plist -Raw
  $hasURLTypes = $false
  $hasScheme   = $false
  if($txt -match '<key>CFBundleURLTypes</key>'){ $hasURLTypes = $true }
  if($txt -match '<string>cc\.swaply\.app</string>'){ $hasScheme = $true }
  $urlText = if($hasURLTypes){"YES"} else {"NO"}
  $schText = if($hasScheme){"YES"} else {"NO"}
  Write-Host ("iOS: CFBundleURLTypes={0} ; contains cc.swaply.app={1}" -f $urlText,$schText)
}else{
  Write-Host "iOS: Info.plist ȱʧ" -ForegroundColor Yellow
}
