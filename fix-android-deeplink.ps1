$ErrorActionPreference="Stop"
$Man = "android\app\src\main\AndroidManifest.xml"
$NS  = "http://schemas.android.com/apk/res/android"
$Scheme = "cc.swaply.app"
$Hosts  = @("login-callback","reset-password")  # 你已有两个 host，就都宣告
if(!(Test-Path $Man)){ Write-Error "[Android] 未找到 $Man"; exit 1 }

function TS { (Get-Date).ToString("yyyyMMddHHmmss") }
Copy-Item $Man "$Man.bak.$(TS)" -Force

$xml = New-Object System.Xml.XmlDocument
$xml.PreserveWhitespace = $true
$xml.Load($Man)
$nsm = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
$nsm.AddNamespace("android",$NS)

# 定位 MAIN Activity；找不到就取第一个
$mainAct = $xml.SelectSingleNode("//activity[intent-filter/action[@android:name='android.intent.action.MAIN']]", $nsm)
if(-not $mainAct){ $mainAct = $xml.SelectSingleNode("//application/activity[1]", $nsm) }
if(-not $mainAct){ throw "未找到 <activity> 节点" }

# 1) exported=true（Android 12+ 必须）
$exp = $mainAct.GetAttribute("exported",$NS)
if([string]::IsNullOrEmpty($exp) -or $exp -ne "true"){
  $mainAct.SetAttribute("exported",$NS,"true")
  Write-Host "? 已设置/修正 android:exported=""true""" -ForegroundColor Green
}else{
  Write-Host "· android:exported 已为 true" -ForegroundColor DarkGray
}

# 2) 移除该 Activity 里现有的 cc.swaply.app 深链声明，避免重复/脏数据
$old = $mainAct.SelectNodes(".//intent-filter[data/@android:scheme='cc.swaply.app']", $nsm)
foreach($node in @($old)){
  $mainAct.RemoveChild($node) | Out-Null
  Write-Host "· 移除旧 DeepLink intent-filter" -ForegroundColor DarkGray
}

# 3) 写入一个“干净”的 Deep Link intent-filter（含两个 host）
$if = $xml.CreateElement("intent-filter")
$act= $xml.CreateElement("action");   $act.SetAttribute("name",$NS,"android.intent.action.VIEW") | Out-Null; $if.AppendChild($act)|Out-Null
$cat= $xml.CreateElement("category"); $cat.SetAttribute("name",$NS,"android.intent.category.DEFAULT")|Out-Null; $if.AppendChild($cat)|Out-Null
$cat2= $xml.CreateElement("category");$cat2.SetAttribute("name",$NS,"android.intent.category.BROWSABLE")|Out-Null; $if.AppendChild($cat2)|Out-Null

foreach($h in $Hosts){
  $data=$xml.CreateElement("data")
  $data.SetAttribute("scheme",$NS,$Scheme) | Out-Null
  $data.SetAttribute("host",$NS,$h)       | Out-Null
  $if.AppendChild($data)|Out-Null
}
$mainAct.AppendChild($if)|Out-Null

# 输出包名+主 Activity，方便 adb 显式启动
$pkg = $xml.DocumentElement.GetAttribute("package")
$mainName = $mainAct.GetAttribute("name",$NS)
if([string]::IsNullOrEmpty($mainName)){ $mainName = ".MainActivity" }
if($mainName.StartsWith(".")){ $component = "$pkg/$mainName" } elseif($mainName -like "$pkg*"){ $component = $mainName } else { $component = "$pkg/$mainName" }

$xml.Save($Man)
Set-Content .\_android_component.txt -Value $component -Encoding UTF8
Write-Host ("? Manifest 写入完成。package={0}  activity={1}" -f $pkg,$mainName) -ForegroundColor Green
Write-Host ("? 组件名已写入 _android_component.txt -> {0}" -f $component) -ForegroundColor Green
