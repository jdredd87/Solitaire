# Regenerates Solitaire.deployproj (what msbuild's Deploy target reads).
# Artwork comes from res\ (see tools\make-artwork.ps1). Run this again after
# adding files that must ship with the app.
$proj = 'Solitaire'
$root = Split-Path -Parent $PSScriptRoot
$art  = '$(BDS)\bin\Artwork'

function Entry($include, $remoteDir, $remoteName, $class, $op = 1, $required = $false) {
    $req = if ($required) { "`r`n            <Required>True</Required>" } else { '' }
@"
        <DeployFile Include="$include" Condition="'`$(Config)'=='__CFG__'">
            <RemoteDir>$remoteDir</RemoteDir>
            <RemoteName>$remoteName</RemoteName>
            <DeployClass>$class</DeployClass>
            <Operation>$op</Operation>
            <LocalCommand/>
            <RemoteCommand/>
            <Overwrite>True</Overwrite>$req
        </DeployFile>
"@
}

# ---------- Android64 ----------
$a = @()
$out = 'Android64\__CFG__'
$res = "$proj\res"
foreach ($p in @(@(36,'ldpi'),@(48,'mdpi'),@(72,'hdpi'),@(96,'xhdpi'),@(144,'xxhdpi'),@(192,'xxxhdpi'))) {
    $a += Entry "res\android\ic_launcher_$($p[0]).png" "$res\drawable-$($p[1])\" 'ic_launcher.png' "Android_LauncherIcon$($p[0])"
}
# the app shows no notifications, so Delphi's stock notification icons are never seen
foreach ($p in @(@(24,'mdpi'),@(36,'hdpi'),@(48,'xhdpi'),@(72,'xxhdpi'),@(96,'xxxhdpi'))) {
    $a += Entry "$art\Android\FM_NotificationIcon_$($p[0])x$($p[0]).png" "$res\drawable-$($p[1])\" 'ic_notification.png' "Android_NotificationIcon$($p[0])"
}
foreach ($p in @(@('426x320','small',426),@('470x320','normal',470),@('640x480','large',640),@('960x720','xlarge',960))) {
    $a += Entry "res\android\splash_$($p[0]).png" "$res\drawable-$($p[1])\" 'splash_image.png' "Android_SplashImage$($p[2])"
}
# adaptive icon (Android 8+) and themed icon (Android 13+)
$a += Entry "$out\ic_launcher.xml"                  "$res\drawable-anydpi-v26\"       'ic_launcher.xml'            'Android_AdaptiveIcon'
$a += Entry "$out\ic_launcher-v33.xml"              "$res\drawable-anydpi-v33\"       'ic_launcher.xml'            'Android_AdaptiveIconV33'
$a += Entry 'res\android\adaptive_foreground.xml'   "$res\drawable\"                  'ic_launcher_foreground.xml' 'Android_AdaptiveIconForeground'
$a += Entry 'res\android\adaptive_background.xml'   "$res\drawable\"                  'ic_launcher_background.xml' 'Android_AdaptiveIconBackground'
$a += Entry 'res\android\adaptive_monochrome.xml'   "$res\drawable\"                  'ic_launcher_monochrome.xml' 'Android_AdaptiveIconMonochrome'
# vector splash screen
$a += Entry 'res\android\splash.xml'                "$res\drawable\"                  'splash_vector.xml'          'Android_VectorizedSplash'
$a += Entry 'res\android\splash_dark.xml'           "$res\drawable-night-anydpi-v21\" 'splash_vector.xml'          'Android_VectorizedSplashDark'
$a += Entry 'res\android\splash_v31.xml'            "$res\drawable-anydpi-v31\"       'splash_vector.xml'          'Android_VectorizedSplashV31'
$a += Entry 'res\android\splash_v31_dark.xml'       "$res\drawable-night-anydpi-v31\" 'splash_vector.xml'          'Android_VectorizedSplashV31Dark'
# files the build generates
$a += Entry "$out\AndroidManifest.xml"        "$proj\"                    'AndroidManifest.xml'  'ProjectAndroidManifest'
$a += Entry "$out\styles.xml"                 "$res\values\"              'styles.xml'           'AndroidSplashStyles'
$a += Entry "$out\styles-v21.xml"             "$res\values-v21\"          'styles.xml'           'AndroidSplashStylesV21'
$a += Entry "$out\styles-v31.xml"             "$res\values-v31\"          'styles.xml'           'AndroidSplashStylesV31'
$a += Entry "$out\styles-v35.xml"             "$res\values-v35\"          'styles.xml'           'AndroidSplashStylesV35'
$a += Entry "$out\colors.xml"                 "$res\values\"              'colors.xml'           'Android_Colors'
$a += Entry "$out\colors-night-v21.xml"       "$res\values-night-v21\"    'colors.xml'           'Android_ColorsDark'
$a += Entry "$out\strings.xml"                "$res\values\"              'strings.xml'          'Android_Strings'
$a += Entry "$out\splash_image_def.xml"       "$res\drawable\"            'splash_image_def.xml' 'AndroidSplashImageDef'
$a += Entry "$out\splash_image_def-v21.xml"   "$res\drawable-anydpi-v21\" 'splash_image_def.xml' 'AndroidSplashImageDefV21'
$a += Entry '$(BDS)\lib\android\__LCFG__\mips\libnative-activity.so'        "$proj\library\lib\mips\"        "lib$proj.so" 'AndroidLibnativeMipsFile'
$a += Entry '$(BDS)\lib\android\__LCFG__\armeabi\libnative-activity.so'     "$proj\library\lib\armeabi\"     "lib$proj.so" 'AndroidLibnativeArmeabiFile'
$a += Entry '$(BDS)\lib\android\__LCFG__\armeabi-v7a\libnative-activity.so' "$proj\library\lib\armeabi-v7a\" "lib$proj.so" 'AndroidLibnativeArmeabiv7aFile'
$a += Entry "$out\lib$proj.so"                "$proj\library\lib\arm64-v8a\"   "lib$proj.so"          'ProjectOutput' 1 $true

# ---------- iOS (device + simulator share the layout) ----------
function IosGroup($plat) {
    $i = @()
    $o = "$plat\__CFG__"
    $icons  = "$proj.app\..\`$(PROJECTNAME).launchscreen\Assets\AppIcon.appiconset\"
    $launch = "$proj.app\..\`$(PROJECTNAME).launchscreen\Assets\LaunchScreenImage.imageset\"
    # The icon set's Contents.json is built from the SOURCE file names, so each
    # slot needs its own file and the remote name must equal the source name.
    $set = @(
        @('AppIcon_120',         'iPhone_AppIcon120'),
        @('AppIcon_180',         'iPhone_AppIcon180'),
        @('AppIcon_1024',        'iOS_AppStore1024'),
        @('Spotlight_80',        'iPhone_Spotlight80'),
        @('Spotlight_120',       'iPhone_Spotlight120'),
        @('Setting_58',          'iPhone_Setting58'),
        @('Setting_87',          'iPhone_Setting87'),
        @('Notification_40',     'iPhone_Notification40'),
        @('Notification_60',     'iPhone_Notification60'),
        @('iPadIcon_152',        'iPad_AppIcon152'),
        @('iPadIcon_167',        'iPad_AppIcon167'),
        @('iPadSpotlight_80',    'iPad_SpotLight80'),
        @('iPadSetting_58',      'iPad_Setting58'),
        @('iPadNotification_40', 'iPad_Notification40'))
    foreach ($s in $set) { $i += Entry "res\ios\$($s[0]).png" $icons "$($s[0]).png" $s[1] }
    # the launch image set, by contrast, expects Delphi's own file names
    $ls = @(
        @('Launch_2x',         'FM_LaunchScreenImage_iPhone@2x.png',     'iPhone_Launch2x'),
        @('LaunchDark_2x',     'FM_LaunchScreenImage_iPhoneDark@2x.png', 'iPhone_LaunchDark2x'),
        @('Launch_3x',         'FM_LaunchScreenImage_iPhone@3x.png',     'iPhone_Launch3x'),
        @('LaunchDark_3x',     'FM_LaunchScreenImage_iPhoneDark@3x.png', 'iPhone_LaunchDark3x'),
        @('iPadLaunch_2x',     'FM_LaunchScreenImage_iPad@2x.png',       'iPad_Launch2x'),
        @('iPadLaunchDark_2x', 'FM_LaunchScreenImage_iPadDark@2x.png',   'iPad_LaunchDark2x'))
    foreach ($s in $ls) { $i += Entry "res\ios\$($s[0]).png" $launch $s[1] $s[2] }
    $i += Entry "$o\$proj.launchscreen" "$proj.app\..\`$(PROJECTNAME).launchscreen\" "$proj.launchscreen" 'ProjectiOSLaunchScreen' 64
    $i += Entry "$o\$proj.entitlements" "$proj.app\..\" "$proj.entitlements" 'ProjectiOSEntitlements'
    $i += Entry "$o\$proj.info.plist"   "$proj.app\"    'Info.plist'         'ProjectiOSInfoPList'
    $i += Entry "$o\$proj"              "$proj.app\"    $proj                'ProjectOutput' 1 $true
    $i
}

function New-PlatformGroup($plat, $entries) {
    $body = ''
    foreach ($cfg in 'Debug', 'Release') {
        $body += (($entries -join "`r`n").Replace('__CFG__', $cfg).Replace('__LCFG__', $cfg.ToLower())) + "`r`n"
    }
    "    <ItemGroup Condition=`"'`$(Platform)'=='$plat'`">`r`n$body    </ItemGroup>`r`n"
}

$xml = @"
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
    <Import Condition="Exists('`$(BDS)\bin\CodeGear.Deployment.targets')" Project="`$(BDS)\bin\CodeGear.Deployment.targets"/>
    <ProjectExtensions>
        <ProjectFileVersion>12</ProjectFileVersion>
    </ProjectExtensions>
    <PropertyGroup>
        <DeviceId Condition="'`$(Platform)'=='Android'"/>
        <DeviceId Condition="'`$(Platform)'=='Android64'"/>
        <DeviceId Condition="'`$(Platform)'=='iOSDevice64'"/>
        <DeviceId Condition="'`$(Platform)'=='iOSSimARM64'"/>
    </PropertyGroup>
    <ItemGroup Condition="'`$(Platform)'=='Win32'"/>
    <ItemGroup Condition="'`$(Platform)'=='Win64'"/>
    <ItemGroup Condition="'`$(Platform)'=='Android'"/>

"@
$xml += New-PlatformGroup 'Android64' $a
$xml += New-PlatformGroup 'iOSDevice64' (IosGroup 'iOSDevice64')
$xml += New-PlatformGroup 'iOSSimARM64' (IosGroup 'iOSSimARM64')
$xml += "</Project>`r`n"
[IO.File]::WriteAllText((Join-Path $root "$proj.deployproj"), $xml, (New-Object Text.UTF8Encoding($true)))
"wrote $proj.deployproj ($($xml.Length) chars)"
