param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9]+(\.[0-9]+)*-[0-9]+$')]
    [string]$ReleaseVersion,

    [string]$RouterHost = "192.168.1.1",
    [string]$RouterUser = "root",
    [int]$SshPort = 22,

    # Включи, если opkg ругается на зависимости и ты точно хочешь форсить их
    [switch]$ForceDepends
)

$ErrorActionPreference = "Stop"

function Assert-LastExitCode {
    param([string]$Step)

    if ($LASTEXITCODE -ne 0) {
        throw "$Step failed with exit code $LASTEXITCODE"
    }
}

function Convert-ToWslPath {
    param([Parameter(Mandatory = $true)][string]$WindowsPath)

    $ResolvedPath = (Resolve-Path -LiteralPath $WindowsPath).Path

    # Важно: wslpath плохо получает Windows-пути с обратными слэшами через wsl.exe.
    # Поэтому передаем путь в виде C:/Users/...
    $SafeWindowsPath = $ResolvedPath -replace '\\', '/'

    $result = & wsl.exe wslpath -a -u "$SafeWindowsPath"
    Assert-LastExitCode "wslpath"

    return $result.Trim()
}

function Quote-Bash {
    param([Parameter(Mandatory = $true)][string]$Value)

    return "'" + ($Value -replace "'", "'\''") + "'"
}

$CurrentDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Скрипт можно положить в корень репозитория или в папку scripts
if (Test-Path (Join-Path $CurrentDir "scripts\build-openwrt-packages-wsl.sh")) {
    $RepoRoot = $CurrentDir
} elseif (Test-Path (Join-Path (Split-Path -Parent $CurrentDir) "scripts\build-openwrt-packages-wsl.sh")) {
    $RepoRoot = Split-Path -Parent $CurrentDir
} else {
    throw "Не найден scripts\build-openwrt-packages-wsl.sh. Запусти скрипт из корня репозитория или положи его в корень/scripts."
}

$BuildScriptWin = Join-Path $RepoRoot "scripts\build-openwrt-packages-wsl.sh"
$OutputDirWin = Join-Path $RepoRoot "dist\release-final"

New-Item -ItemType Directory -Force -Path $OutputDirWin | Out-Null

$BuildScriptWsl = Convert-ToWslPath $BuildScriptWin
$OutputDirWsl = Convert-ToWslPath $OutputDirWin

Write-Host "Building OpenWrt packages..."
Write-Host "Release version: $ReleaseVersion"
Write-Host "Output dir: $OutputDirWin"

$BuildCommand = "bash $(Quote-Bash $BuildScriptWsl) $(Quote-Bash $ReleaseVersion) $(Quote-Bash $OutputDirWsl)"
& wsl.exe bash -lc $BuildCommand
Assert-LastExitCode "Package build"

$Ipks = Get-ChildItem -Path $OutputDirWin -Filter "*.ipk" -File | Sort-Object Name

if (-not $Ipks -or $Ipks.Count -eq 0) {
    throw "В $OutputDirWin не найдены .ipk пакеты."
}

Write-Host "Found IPK packages:"
$Ipks | ForEach-Object { Write-Host " - $($_.Name)" }

$RemoteDir = "/tmp/openwrt-ipk-deploy"
$Remote = "${RouterUser}@${RouterHost}"

$SshArgs = @()
if ($SshPort -ne 22) {
    $SshArgs += @("-p", "$SshPort")
}

$ScpArgs = @("-O")
if ($SshPort -ne 22) {
    $ScpArgs += @("-P", "$SshPort")
}

Write-Host "Preparing router temp dir: $RemoteDir"
& ssh.exe @SshArgs $Remote "rm -rf '$RemoteDir' && mkdir -p '$RemoteDir'"
Assert-LastExitCode "Router temp dir preparation"

Write-Host "Copying IPK packages to router..."
$Ipks.FullName | ForEach-Object {
    & scp.exe @ScpArgs "$_" "${Remote}:$RemoteDir/"
    Assert-LastExitCode "SCP upload: $_"
}

$ForceOptions = @(
    "--force-reinstall",
    "--force-overwrite",
    "--force-downgrade"
)

if ($ForceDepends) {
    $ForceOptions += "--force-depends"
}

$ForceOptionsText = $ForceOptions -join " "

$InstallCommand = @"
set -e

echo 'Installing IPK packages from $RemoteDir...'

for pkg in \
  $RemoteDir/podkop-plus_*.ipk \
  $RemoteDir/luci-app-podkop-plus_*.ipk \
  $RemoteDir/luci-i18n-podkop-plus-ru_*.ipk
do
  [ -e "`$pkg" ] || continue
  echo "Installing `$pkg"
  opkg $ForceOptionsText install "`$pkg"
done

rm -rf /tmp/luci-indexcache.* /tmp/luci-modulecache/ 2>/dev/null || true
/etc/init.d/rpcd restart 2>/dev/null || killall -HUP rpcd 2>/dev/null || true

echo 'Done.'
"@

Write-Host "Installing packages on router..."
& ssh.exe @SshArgs $Remote $InstallCommand
$InstallParts = @(
    "set -e",
    "echo 'Installing IPK packages from $RemoteDir...'",
    "for pkg in $RemoteDir/podkop-plus_*.ipk $RemoteDir/luci-app-podkop-plus_*.ipk $RemoteDir/luci-i18n-podkop-plus-ru_*.ipk; do [ -e `"`$pkg`" ] || continue; echo `"Installing `$pkg`"; opkg $ForceOptionsText install `"`$pkg`"; done",
    "rm -rf /tmp/luci-indexcache.* /tmp/luci-modulecache/ 2>/dev/null || true",
    "/etc/init.d/rpcd restart 2>/dev/null || killall -HUP rpcd 2>/dev/null || true",
    "echo 'Done.'"
)

$InstallCommand = $InstallParts -join "; "

Write-Host "Installing packages on router..."
& ssh.exe @SshArgs $Remote $InstallCommand
Assert-LastExitCode "Remote opkg install"

Write-Host "Deployment completed successfully."