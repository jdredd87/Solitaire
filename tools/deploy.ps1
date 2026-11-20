# Command-line build + deploy (no IDE).
#   .\tools\deploy.ps1 android        build the APK and install it on every phone adb can see
#   .\tools\deploy.ps1 iossim         build, deploy to the Mac (PAServer profile MacMini) and
#                                     install + launch on the booted iOS simulator
#   .\tools\deploy.ps1 iosdevice      build an ad-hoc signed .ipa and install it on the iPhone/iPad
#                                     plugged into the Mac (pass -DeviceId for a different one)
#   .\tools\deploy.ps1 all            android + iossim
#
# The iOS bundle id, the signing settings (PF_*AdHoc) and the test device's UDID come from
# Solitaire.local.props, which is not in source control (copy Solitaire.local.props.example).
# The device must be registered in the provisioning profile named there; after renewing
# the profile, update PF_MobileProvision*AdHoc.
# Add -Launch to also start the app on the Android phones (it takes over the screen).
param([ValidateSet('android', 'iossim', 'iosdevice', 'all')][string]$Target = 'all', [switch]$Launch, [string]$Config = 'Debug',
      [string]$DeviceId)   # defaults to TestDeviceId in Solitaire.local.props

$root   = Split-Path -Parent $PSScriptRoot
$bundleId = 'com.example.solitaire'   # the project's default when there is no local props file
$localProps = Join-Path $root 'Solitaire.local.props'
if (Test-Path $localProps) {
    $lp = ([xml](Get-Content $localProps -Raw)).Project.PropertyGroup
    $v = $lp | ForEach-Object { $_.AppBundleId } | Where-Object { $_ } | Select-Object -First 1
    if ($v) { $bundleId = $v }
    if (-not $DeviceId) { $DeviceId = $lp | ForEach-Object { $_.TestDeviceId } | Where-Object { $_ } | Select-Object -First 1 }
}
$rsvars = '"C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"'
$adb    = 'C:\Users\Public\Documents\Embarcadero\Studio\37.0\CatalogRepository\AndroidSDK-37.0.60952.8797\platform-tools\adb.exe'
Set-Location $root

function Invoke-MsBuild([string]$PlatformArgs) {
    cmd /c "$rsvars && msbuild Solitaire.dproj `"/t:Build;Deploy`" /p:Config=$Config $PlatformArgs /nologo /v:minimal" |
        Where-Object { $_ -match 'error|lines,' }
    if ($LASTEXITCODE -ne 0) { throw "msbuild failed ($PlatformArgs)" }
}

if ($Target -in 'android', 'all') {
    # AndroidAPI36.1_64bit.sdk: the default SDK entry on this PC has a stale NDK library path
    Invoke-MsBuild '/p:Platform=Android64 /p:PlatformSDK=AndroidAPI36.1_64bit.sdk'
    $apk = "Android64\$Config\Solitaire\bin\Solitaire.apk"
    $devices = & $adb devices | Select-String '^(\S+)\s+device$' | ForEach-Object { $_.Matches[0].Groups[1].Value }
    foreach ($d in $devices) {
        $r = & $adb -s $d install -r $apk 2>&1 | Select-Object -Last 1
        "android ${d}: $r"
        if ($Launch) { & $adb -s $d shell am start -n com.embarcadero.Solitaire/com.embarcadero.firemonkey.FMXNativeActivity | Out-Null }
    }
}

if ($Target -in 'iossim', 'all') {
    Invoke-MsBuild '/p:Platform=iOSSimARM64 /p:PlatformSDK=iPhoneSimulator27.2.sdk /p:Profile=MacMini'
    # paclient cannot launch an app, but a file sent with flag 5 is run on the Mac
    $tmp = Join-Path $env:TEMP 'solitaire-deploy'
    New-Item -ItemType Directory -Force $tmp | Out-Null
    $sh = @'
#!/bin/sh
D="$HOME/PAServer/scratch-dir/__SCRATCH__"
APP=__BUNDLE__
{
  DEV=$(xcrun simctl list devices booted | grep -m1 -oE '[0-9A-F]{8}-[0-9A-F-]{27}')
  if [ -z "$DEV" ]; then
    DEV=$(xcrun simctl list devices available | grep iPhone | grep -m1 -oE '[0-9A-F]{8}-[0-9A-F-]{27}')
    xcrun simctl boot "$DEV"; open -a Simulator; sleep 20
  fi
  xcrun simctl terminate "$DEV" "$APP" 2>/dev/null
  xcrun simctl uninstall "$DEV" com.embarcadero.Solitaire 2>/dev/null   # id used by early builds
  xcrun simctl install "$DEV" "$D/Solitaire.app" && echo installed
  xcrun simctl launch "$DEV" "$APP" && echo launched
} > "$D/sol_sim.log" 2>&1 < /dev/null
'@
    # PAServer's scratch folder is named <Windows user>-<profile>
    $sh = $sh.Replace('__SCRATCH__', "$env:USERNAME-MacMini").Replace('__BUNDLE__', $bundleId)
    [IO.File]::WriteAllText("$tmp\sol_sim.sh", $sh.Replace("`r`n", "`n"),(New-Object Text.UTF8Encoding($false)))
    Push-Location $tmp
    cmd /c "$rsvars && paclient --put=`"sol_sim.sh,.\,5,sol_sim.sh`" MacMini" | Out-Null
    Start-Sleep -Seconds 15
    cmd /c "$rsvars && paclient --get=`"sol_sim.log,$tmp`" MacMini" | Out-Null
    Pop-Location
    Get-Content "$tmp\sol_sim.log" | ForEach-Object { "iossim: $_" }
}

if ($Target -eq 'iosdevice') {
    # BT_BuildType=Adhoc makes Deploy sign the app and fetch Solitaire.ipa back from the Mac
    Invoke-MsBuild '/p:Platform=iOSDevice64 /p:PlatformSDK=iPhoneOS27.2.sdk /p:Profile=MacMini /p:BT_BuildType=Adhoc'
    if (-not $DeviceId) { throw 'no device: pass -DeviceId or set TestDeviceId in Solitaire.local.props' }
    "ipa: $((Get-Item "iOSDevice64\$Config\Solitaire.ipa").Length) bytes"
    # the .ipa is still in PAServer's scratch folder; this waits for the device if it is not connected
    cmd /c "$rsvars && paclient -u8 --installipa=`"Solitaire.ipa,$DeviceId`" MacMini" | Out-Null
    if ($LASTEXITCODE -eq 0) { "iosdevice ${DeviceId}: installed (open it from the home screen)" } else { throw 'paclient --installipa failed' }
}
