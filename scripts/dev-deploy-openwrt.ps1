[CmdletBinding()]
param(
    [string]$Router = '192.168.1.1',
    [string]$User = 'root',
    [int]$Port = 22
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

function Get-RepoRoot {
    param([string]$StartPath)

    $currentPath = [System.IO.Path]::GetFullPath($StartPath)

    while ($true) {
        $hasPodkop = Test-Path -LiteralPath (Join-Path $currentPath 'podkop')
        $hasLuciApp = Test-Path -LiteralPath (Join-Path $currentPath 'luci-app-podkop-plus')

        if ($hasPodkop -and $hasLuciApp) {
            return $currentPath
        }

        $parentPath = Split-Path -Parent $currentPath
        if ([string]::IsNullOrEmpty($parentPath) -or $parentPath -eq $currentPath) {
            throw "Failed to locate repository root from script path: $StartPath"
        }

        $currentPath = $parentPath
    }
}

$RepoRoot = Get-RepoRoot -StartPath $PSScriptRoot

Add-Type -TypeDefinition @"
using System;

public static class PodkopLmoHash
{
    private static uint Get16(byte[] data, int offset)
    {
        return (uint)(data[offset] | (data[offset + 1] << 8));
    }

    public static uint Compute(byte[] data, uint init)
    {
        if (data == null || data.Length == 0)
            return 0;

        uint hash = init;
        uint tmp;
        int rem = data.Length & 3;
        int len = data.Length >> 2;
        int offset = 0;

        while (len-- > 0)
        {
            hash += Get16(data, offset);
            tmp = (Get16(data, offset + 2) << 11) ^ hash;
            hash = (hash << 16) ^ tmp;
            offset += 4;
            hash += hash >> 11;
        }

        switch (rem)
        {
            case 3:
                hash += Get16(data, offset);
                hash ^= hash << 16;
                hash ^= (uint)(((sbyte)data[offset + 2]) << 18);
                hash += hash >> 11;
                break;

            case 2:
                hash += Get16(data, offset);
                hash ^= hash << 11;
                hash += hash >> 17;
                break;

            case 1:
                hash += (uint)(sbyte)data[offset];
                hash ^= hash << 10;
                hash += hash >> 1;
                break;
        }

        hash ^= hash << 3;
        hash += hash >> 5;
        hash ^= hash << 4;
        hash += hash >> 17;
        hash ^= hash << 25;
        hash += hash >> 6;

        return hash;
    }
}
"@

function Write-Step {
    param([string]$Message)

    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Get-RequiredCommand {
    param([string]$Name)

    $command = Get-Command -Name $Name -ErrorAction SilentlyContinue
    if (-not $command) {
        throw "Required command '$Name' was not found in PATH."
    }

    return $command.Source
}

function Invoke-External {
    param(
        [string]$FilePath,
        [string[]]$Arguments,
        [string]$Description
    )

    if ($Description) {
        Write-Step $Description
    }

    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        $argString = ($Arguments | ForEach-Object { "'$_'" }) -join ' '
        throw "Command failed with exit code ${LASTEXITCODE}: $FilePath $argString"
    }
}

function Invoke-ExternalCapture {
    param(
        [string]$FilePath,
        [string[]]$Arguments
    )

    $output = & $FilePath @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        $argString = ($Arguments | ForEach-Object { "'$_'" }) -join ' '
        throw "Command failed with exit code ${LASTEXITCODE}: $FilePath $argString`n$($output -join [Environment]::NewLine)"
    }

    return ($output -join [Environment]::NewLine).Trim()
}

function Assert-RepoPath {
    param([string]$RelativePath)

    $fullPath = Join-Path $RepoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $fullPath)) {
        throw "Expected repository path is missing: $RelativePath"
    }

    return $fullPath
}

function Get-DeployVersion {
    $makefilePath = Assert-RepoPath 'luci-app-podkop-plus\Makefile'
    $makefile = Get-Content -LiteralPath $makefilePath -Raw -Encoding UTF8
    $pkgVersion = 'dev'

    if ($makefile -match 'PKG_VERSION:=.*?([0-9]+\.[0-9]+\.[0-9]+)') {
        $pkgVersion = $Matches[1]
    }

    $git = Get-Command -Name git -ErrorAction SilentlyContinue
    if ($git) {
        try {
            $gitShort = Invoke-ExternalCapture -FilePath $git.Source -Arguments @('-C', $RepoRoot, 'rev-parse', '--short', 'HEAD')
            if ($gitShort) {
                return "$pkgVersion-dev+$gitShort"
            }
        }
        catch {
        }
    }

    return "$pkgVersion-dev"
}

function Copy-Tree {
    param(
        [string]$Source,
        [string]$Destination
    )

    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    Get-ChildItem -LiteralPath $Source -Force | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $Destination -Recurse -Force
    }
}

function Write-Utf8NoBom {
    param(
        [string]$Path,
        [string]$Content
    )

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

function Replace-VersionPlaceholder {
    param(
        [string]$Path,
        [string]$Version
    )

    $content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    if ($content.Contains('__COMPILED_VERSION_VARIABLE__')) {
        Write-Utf8NoBom -Path $Path -Content $content.Replace('__COMPILED_VERSION_VARIABLE__', $Version)
    }
}

function New-PoMessageState {
    return @{
        PluralNum = -1
        Ctxt = $null
        Id = $null
        IdPlural = $null
        Values = (New-Object string[] 10)
        CurrentField = $null
        CurrentIndex = -1
    }
}

function Get-PoStringSegment {
    param([string]$Line)

    if ([string]::IsNullOrEmpty($Line) -or $Line[0] -eq '#') {
        return $null
    }

    $quoteIndex = $Line.IndexOf('"')
    if ($quoteIndex -lt 0) {
        return $null
    }

    $builder = New-Object System.Text.StringBuilder
    $escape = $false

    for ($index = $quoteIndex + 1; $index -lt $Line.Length; $index++) {
        $char = $Line[$index]

        if ($escape) {
            if (($char -eq '"') -or ($char -eq '\')) {
                [void]$builder.Remove($builder.Length - 1, 1)
            }

            [void]$builder.Append($char)
            $escape = $false
            continue
        }

        if ($char -eq '\') {
            [void]$builder.Append($char)
            $escape = $true
            continue
        }

        if ($char -eq '"') {
            break
        }

        [void]$builder.Append($char)
    }

    return $builder.ToString()
}

function Add-PoSegment {
    param(
        [hashtable]$Message,
        [string]$Segment
    )

    if ([string]::IsNullOrEmpty($Segment)) {
        return
    }

    switch ($Message.CurrentField) {
        'ctxt' {
            if ($null -eq $Message.Ctxt) {
                $Message.Ctxt = ''
            }

            $Message.Ctxt += $Segment
        }
        'id' {
            if ($null -eq $Message.Id) {
                $Message.Id = ''
            }

            $Message.Id += $Segment
        }
        'idPlural' {
            if ($null -eq $Message.IdPlural) {
                $Message.IdPlural = ''
            }

            $Message.IdPlural += $Segment
        }
        'value' {
            if ($Message.CurrentIndex -lt 0 -or $Message.CurrentIndex -ge $Message.Values.Length) {
                throw "Invalid PO plural index: $($Message.CurrentIndex)"
            }

            if ($null -eq $Message.Values[$Message.CurrentIndex]) {
                $Message.Values[$Message.CurrentIndex] = ''
            }

            $Message.Values[$Message.CurrentIndex] += $Segment
        }
    }
}

function Get-SignedByte {
    param([byte]$Value)

    if ($Value -ge 128) {
        return [int]$Value - 256
    }

    return [int]$Value
}

function Get-UInt16Le {
    param(
        [byte[]]$Bytes,
        [int]$Index
    )

    return [uint32]($Bytes[$Index] -bor ($Bytes[$Index + 1] -shl 8))
}

function Convert-ToUInt32 {
    param([long]$Value)

    return [uint32]($Value -band 0xffffffffL)
}

function Get-SfhHash {
    param(
        [byte[]]$Data,
        [uint32]$Init
    )

    return [PodkopLmoHash]::Compute($Data, $Init)
}

function Write-UInt32BigEndian {
    param(
        [System.IO.BinaryWriter]$Writer,
        [uint32]$Value
    )

    $bytes = [System.BitConverter]::GetBytes($Value)
    if ([System.BitConverter]::IsLittleEndian) {
        [Array]::Reverse($bytes)
    }

    $Writer.Write($bytes)
}

function Write-AlignedBytes {
    param(
        [System.IO.BinaryWriter]$Writer,
        [byte[]]$Bytes
    )

    $Writer.Write($Bytes)
    $padding = (4 - ($Bytes.Length % 4)) % 4

    for ($index = 0; $index -lt $padding; $index++) {
        $Writer.Write([byte]0)
    }
}

function Add-LmoEntry {
    param(
        [System.Collections.Generic.List[object]]$Entries,
        [System.IO.BinaryWriter]$DataWriter,
        [System.IO.MemoryStream]$DataStream,
        [uint32]$KeyId,
        [uint32]$ValId,
        [string]$Value
    )

    $utf8 = [System.Text.Encoding]::UTF8
    $valueBytes = $utf8.GetBytes($Value)
    $entry = [pscustomobject]@{
        KeyId = $KeyId
        ValId = $ValId
        Offset = [uint32]$DataStream.Length
        Length = [uint32]$valueBytes.Length
    }

    Write-AlignedBytes -Writer $DataWriter -Bytes $valueBytes
    [void]$Entries.Add($entry)
}

function Flush-PoMessage {
    param(
        [hashtable]$Message,
        [System.Collections.Generic.List[object]]$Entries,
        [System.IO.BinaryWriter]$DataWriter,
        [System.IO.MemoryStream]$DataStream
    )

    $utf8 = [System.Text.Encoding]::UTF8

    if ($null -ne $Message.Id -and $null -ne $Message.Values[0]) {
        $pluralLimit = if ($Message.PluralNum -lt 0) { 0 } else { $Message.PluralNum }

        for ($index = 0; $index -le $pluralLimit; $index++) {
            $value = $Message.Values[$index]
            if ($null -eq $value) {
                continue
            }

            if (($null -ne $Message.Ctxt) -and ($null -ne $Message.IdPlural)) {
                $key = '{0}{1}{2}{3}{4}' -f $Message.Ctxt, [char]1, $Message.Id, [char]2, $index
            }
            elseif ($null -ne $Message.Ctxt) {
                $key = '{0}{1}{2}' -f $Message.Ctxt, [char]1, $Message.Id
            }
            elseif ($null -ne $Message.IdPlural) {
                $key = '{0}{1}{2}' -f $Message.Id, [char]2, $index
            }
            else {
                $key = $Message.Id
            }

            $keyBytes = $utf8.GetBytes($key)
            $valueBytes = $utf8.GetBytes($value)
            $keyHash = Get-SfhHash -Data $keyBytes -Init ([uint32]$keyBytes.Length)
            $valueHash = Get-SfhHash -Data $valueBytes -Init ([uint32]$valueBytes.Length)

            if ($keyHash -eq $valueHash) {
                continue
            }

            Add-LmoEntry -Entries $Entries -DataWriter $DataWriter -DataStream $DataStream -KeyId $keyHash -ValId ([uint32]($Message.PluralNum + 1)) -Value $value
        }
    }
    elseif ($null -ne $Message.Values[0]) {
        foreach ($field in ($Message.Values[0] -split '\\n')) {
            if ($field.StartsWith('Plural-Forms: ')) {
                $pluralDefinition = $field.Substring(14)
                Add-LmoEntry -Entries $Entries -DataWriter $DataWriter -DataStream $DataStream -KeyId ([uint32]0) -ValId ([uint32]0) -Value $pluralDefinition
                break
            }
        }
    }

    $Message.PluralNum = -1
    $Message.Ctxt = $null
    $Message.Id = $null
    $Message.IdPlural = $null
    $Message.Values = (New-Object string[] 10)
    $Message.CurrentField = $null
    $Message.CurrentIndex = -1
}

function Convert-PoToLmo {
    param(
        [string]$PoPath,
        [string]$LmoPath
    )

    $entries = [System.Collections.Generic.List[object]]::new()
    $dataStream = New-Object System.IO.MemoryStream
    $dataWriter = New-Object System.IO.BinaryWriter($dataStream)
    $message = New-PoMessageState

    try {
        foreach ($line in (Get-Content -LiteralPath $PoPath -Encoding UTF8)) {
            if ($line.StartsWith('msgctxt "')) {
                if (($null -ne $message.Id) -or ($null -ne $message.Values[0])) {
                    Flush-PoMessage -Message $message -Entries $entries -DataWriter $dataWriter -DataStream $dataStream
                }

                $message.CurrentField = 'ctxt'
                $message.CurrentIndex = -1
                $message.Ctxt = $null
            }
            elseif ($line.StartsWith('msgid "')) {
                if (($null -ne $message.Id) -or ($null -ne $message.Values[0])) {
                    Flush-PoMessage -Message $message -Entries $entries -DataWriter $dataWriter -DataStream $dataStream
                }

                $message.CurrentField = 'id'
                $message.CurrentIndex = -1
                $message.Id = $null
            }
            elseif ($line.StartsWith('msgid_plural "')) {
                $message.CurrentField = 'idPlural'
                $message.CurrentIndex = -1
                $message.IdPlural = $null
            }
            elseif ($line.StartsWith('msgstr "')) {
                $message.PluralNum = 0
                $message.CurrentField = 'value'
                $message.CurrentIndex = 0
                $message.Values[0] = $null
            }
            elseif ($line.StartsWith('msgstr[')) {
                if ($line -notmatch '^msgstr\[(\d+)\]') {
                    throw "Failed to parse plural msgstr line: $line"
                }

                $pluralIndex = [int]$Matches[1]
                if ($pluralIndex -ge $message.Values.Length) {
                    throw "Too many plural forms in $PoPath"
                }

                $message.PluralNum = $pluralIndex
                $message.CurrentField = 'value'
                $message.CurrentIndex = $pluralIndex
                $message.Values[$pluralIndex] = $null
            }

            $segment = Get-PoStringSegment -Line $line
            if ($null -ne $segment) {
                Add-PoSegment -Message $message -Segment $segment
            }
        }

        Flush-PoMessage -Message $message -Entries $entries -DataWriter $dataWriter -DataStream $dataStream

        if ($dataStream.Length -le 0) {
            throw "No translatable data was produced from $PoPath"
        }

        $indexStream = New-Object System.IO.MemoryStream
        $indexWriter = New-Object System.IO.BinaryWriter($indexStream)
        try {
            foreach ($entry in ($entries | Sort-Object -Property KeyId)) {
                Write-UInt32BigEndian -Writer $indexWriter -Value ([uint32]$entry.KeyId)
                Write-UInt32BigEndian -Writer $indexWriter -Value ([uint32]$entry.ValId)
                Write-UInt32BigEndian -Writer $indexWriter -Value ([uint32]$entry.Offset)
                Write-UInt32BigEndian -Writer $indexWriter -Value ([uint32]$entry.Length)
            }

            $finalStream = New-Object System.IO.MemoryStream
            $finalWriter = New-Object System.IO.BinaryWriter($finalStream)
            try {
                $finalWriter.Write($dataStream.ToArray())
                $finalWriter.Write($indexStream.ToArray())
                Write-UInt32BigEndian -Writer $finalWriter -Value ([uint32]$dataStream.Length)
                [System.IO.File]::WriteAllBytes($LmoPath, $finalStream.ToArray())
            }
            finally {
                $finalWriter.Dispose()
                $finalStream.Dispose()
            }
        }
        finally {
            $indexWriter.Dispose()
            $indexStream.Dispose()
        }
    }
    finally {
        $dataWriter.Dispose()
        $dataStream.Dispose()
    }
}

function Get-RemoteInstallScript {
    return @'
#!/bin/sh
set -eu

BUNDLE_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"

replace_file() {
    src="$1"
    dest="$2"
    mode="$3"
    tmp="${dest}.podkop-plus-new.$$"

    mkdir -p "$(dirname "$dest")"
    cp "$src" "$tmp"
    chmod "$mode" "$tmp"
    mv -f "$tmp" "$dest"
}

replace_dir() {
    src="$1"
    dest="$2"
    base_dir="$(dirname "$dest")"
    dir_name="$(basename "$dest")"
    tmp="${base_dir}/.${dir_name}.podkop-plus-new.$$"

    mkdir -p "$base_dir"
    rm -rf "$tmp"
    mkdir -p "$tmp"

    (cd "$src" && tar -cf - .) | (cd "$tmp" && tar -xf -)

    rm -rf "$dest"
    mv "$tmp" "$dest"
}

if [ -x /etc/init.d/podkop ]; then
    /etc/init.d/podkop running >/dev/null 2>&1 && /etc/init.d/podkop stop >/dev/null 2>&1 || true
    /etc/init.d/podkop enabled >/dev/null 2>&1 && /etc/init.d/podkop disable >/dev/null 2>&1 || true
fi
[ -x /etc/init.d/podkop-plus ] && /etc/init.d/podkop-plus stop >/dev/null 2>&1 || true

replace_file "$BUNDLE_DIR/etc/init.d/podkop-plus" "/etc/init.d/podkop-plus" 0755
replace_file "$BUNDLE_DIR/usr/bin/podkop-plus" "/usr/bin/podkop-plus" 0755

replace_dir "$BUNDLE_DIR/usr/lib/podkop-plus" "/usr/lib/podkop-plus"
replace_dir "$BUNDLE_DIR/www/luci-static/resources/view/podkop_plus" "/www/luci-static/resources/view/podkop_plus"

replace_file "$BUNDLE_DIR/usr/share/luci/menu.d/luci-app-podkop-plus.json" "/usr/share/luci/menu.d/luci-app-podkop-plus.json" 0644
replace_file "$BUNDLE_DIR/usr/share/rpcd/acl.d/luci-app-podkop-plus.json" "/usr/share/rpcd/acl.d/luci-app-podkop-plus.json" 0644
replace_file "$BUNDLE_DIR/usr/lib/lua/luci/i18n/podkop_plus.ru.lmo" "/usr/lib/lua/luci/i18n/podkop_plus.ru.lmo" 0644
replace_file "$BUNDLE_DIR/etc/uci-defaults/50_luci-podkop-plus" "/etc/uci-defaults/50_luci-podkop-plus" 0755

is_original_podkop_present() {
    opkg list-installed 2>/dev/null | grep -Eq '^podkop([[:space:]-]|$)' ||
    opkg list-installed 2>/dev/null | grep -Eq '^luci-app-podkop([[:space:]-]|$)' ||
    [ -x /etc/init.d/podkop ] ||
    [ -x /usr/bin/podkop ] ||
    [ -d /usr/lib/podkop ] ||
    [ -f /usr/share/luci/menu.d/luci-app-podkop.json ] ||
    [ -f /usr/share/rpcd/acl.d/luci-app-podkop.json ]
}

if [ ! -f /etc/config/podkop_plus ]; then
    if [ -f /etc/config/podkop ] &&
        { [ -x /etc/init.d/podkop-plus ] || [ -x /usr/bin/podkop-plus ] || [ -d /usr/lib/podkop-plus ]; } &&
        ! is_original_podkop_present; then
        cp /etc/config/podkop /etc/config/podkop_plus
        chmod 0644 /etc/config/podkop_plus || true
    else
        replace_file "$BUNDLE_DIR/etc/config/podkop_plus" "/etc/config/podkop_plus" 0644
    fi
fi

rm -f /var/luci-indexcache* /tmp/luci-indexcache*
[ -x /etc/init.d/rpcd ] && /etc/init.d/rpcd reload >/dev/null 2>&1 || true

/etc/init.d/podkop-plus enable >/dev/null 2>&1 || true

get_status_json() {
    /usr/bin/podkop-plus get_status 2>/dev/null || true
}

wait_for_service() {
    attempts=90
    consecutive=0
    LAST_STATUS_JSON='{}'

    while [ "$attempts" -gt 0 ]; do
        LAST_STATUS_JSON="$(get_status_json)"

        if printf '%s\n' "$LAST_STATUS_JSON" | grep -q '"running":1'; then
            consecutive=$((consecutive + 1))
            if [ "$consecutive" -ge 3 ]; then
                return 0
            fi
        else
            consecutive=0
        fi

        attempts=$((attempts - 1))
        sleep 1
    done

    return 1
}

/etc/init.d/podkop-plus restart >/dev/null 2>&1 || true

echo "System LuCI language: $(uci -q get luci.main.lang || echo auto)"
echo "Podkop Plus RU catalog: $( [ -f /usr/lib/lua/luci/i18n/podkop_plus.ru.lmo ] && echo installed || echo absent )"
echo "Autostart enabled: $(/etc/init.d/podkop-plus enabled >/dev/null 2>&1 && echo yes || echo no)"
echo "Service status:"
if ! wait_for_service; then
    printf '%s\n' "$LAST_STATUS_JSON"
    exit 1
fi

printf '%s\n' "$LAST_STATUS_JSON"
'@
}

function New-DeployBundle {
    param(
        [string]$StageRoot,
        [string]$Version
    )

    $bundleFiles = @{
        'podkop/files/etc/init.d/podkop' = 'etc/init.d/podkop-plus'
        'podkop/files/etc/config/podkop' = 'etc/config/podkop_plus'
        'podkop/files/usr/bin/podkop' = 'usr/bin/podkop-plus'
        'luci-app-podkop-plus/root/usr/share/luci/menu.d/luci-app-podkop-plus.json' = 'usr/share/luci/menu.d/luci-app-podkop-plus.json'
        'luci-app-podkop-plus/root/usr/share/rpcd/acl.d/luci-app-podkop-plus.json' = 'usr/share/rpcd/acl.d/luci-app-podkop-plus.json'
        'luci-app-podkop-plus/root/etc/uci-defaults/50_luci-podkop-plus' = 'etc/uci-defaults/50_luci-podkop-plus'
    }

    foreach ($entry in $bundleFiles.GetEnumerator()) {
        $source = Assert-RepoPath $entry.Key
        $destination = Join-Path $StageRoot $entry.Value
        New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
        Copy-Item -LiteralPath $source -Destination $destination -Force
    }

    Copy-Tree -Source (Assert-RepoPath 'podkop/files/usr/lib') -Destination (Join-Path $StageRoot 'usr/lib/podkop-plus')
    Copy-Tree -Source (Assert-RepoPath 'luci-app-podkop-plus/htdocs/luci-static/resources/view/podkop') -Destination (Join-Path $StageRoot 'www/luci-static/resources/view/podkop_plus')

    Replace-VersionPlaceholder -Path (Join-Path $StageRoot 'usr/lib/podkop-plus/constants.sh') -Version $Version
    $mainJsPath = Join-Path $StageRoot 'www/luci-static/resources/view/podkop_plus/main.js'
    if (Test-Path -LiteralPath $mainJsPath) {
        Replace-VersionPlaceholder -Path $mainJsPath -Version $Version
    }

    $poPath = Assert-RepoPath 'luci-app-podkop-plus\po\ru\podkop_plus.po'
    $lmoPath = Join-Path $StageRoot 'usr/lib/lua/luci/i18n/podkop_plus.ru.lmo'
    New-Item -ItemType Directory -Path (Split-Path -Parent $lmoPath) -Force | Out-Null
    Convert-PoToLmo -PoPath $poPath -LmoPath $lmoPath

    $remoteScriptPath = Join-Path $StageRoot '.devdeploy\install.sh'
    New-Item -ItemType Directory -Path (Split-Path -Parent $remoteScriptPath) -Force | Out-Null
    Write-Utf8NoBom -Path $remoteScriptPath -Content (Get-RemoteInstallScript)
}

function New-TarArchive {
    param(
        [string]$TarExe,
        [string]$SourceDirectory,
        [string]$ArchivePath
    )

    if (Test-Path -LiteralPath $ArchivePath) {
        Remove-Item -LiteralPath $ArchivePath -Force
    }

    Push-Location $SourceDirectory
    try {
        Invoke-External -FilePath $TarExe -Arguments @('-czf', $ArchivePath, '.') -Description 'Packing deploy bundle'
    }
    finally {
        Pop-Location
    }
}

$sshExe = Get-RequiredCommand -Name 'ssh.exe'
$scpExe = Get-RequiredCommand -Name 'scp.exe'
$tarExe = Get-RequiredCommand -Name 'tar.exe'

[void](Assert-RepoPath 'podkop')
[void](Assert-RepoPath 'luci-app-podkop-plus')

$version = Get-DeployVersion
$target = "$User@$Router"
$sshArgs = @('-p', $Port.ToString(), '-o', 'BatchMode=yes')
$scpArgs = @('-O', '-P', $Port.ToString(), '-o', 'BatchMode=yes')
$remoteId = "podkop-plus-devdeploy-$PID"
$remoteArchive = "/tmp/$remoteId.tgz"
$remoteWorkDir = "/tmp/$remoteId"

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) "$remoteId-local"
$stageRoot = Join-Path $tempRoot 'bundle'
$archivePath = Join-Path $tempRoot "$remoteId.tgz"

try {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }

    New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null

    Write-Step "Preparing deploy bundle for $target"
    New-DeployBundle -StageRoot $stageRoot -Version $version
    New-TarArchive -TarExe $tarExe -SourceDirectory $stageRoot -ArchivePath $archivePath

    Invoke-External -FilePath $scpExe -Arguments ($scpArgs + @($archivePath, "${target}:$remoteArchive")) -Description "Uploading archive to $target"

    $remoteCommand = @'
set -eu
archive='__ARCHIVE__'
work='__WORKDIR__'
cleanup() {
    rm -rf "$work" "$archive"
}
trap cleanup EXIT INT TERM
rm -rf "$work"
mkdir -p "$work"
tar -xzf "$archive" -C "$work"
sh "$work/.devdeploy/install.sh"
'@
    $remoteCommand = $remoteCommand.Replace('__ARCHIVE__', $remoteArchive)
    $remoteCommand = $remoteCommand.Replace('__WORKDIR__', $remoteWorkDir)

    Invoke-External -FilePath $sshExe -Arguments ($sshArgs + @($target, $remoteCommand)) -Description "Installing bundle on $target"

    Write-Step 'Deploy finished successfully'
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
