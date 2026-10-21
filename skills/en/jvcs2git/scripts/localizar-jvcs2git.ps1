<#
.SYNOPSIS
    Finds jvcs2git-cli.exe (and jvcs2git.exe) for the jvcs2git skill.

.DESCRIPTION
    Read only: does not run jvcs2git, does not read the password or the key, writes nothing.
    Search order (the first folder with jvcs2git-cli.exe wins):
      1. environment variable JVCS2GIT_HOME (folder of the executables, or a root with bin\Win32);
      2. <project>\.claude\jvcs2git.managed.json ("home" or "cli" field), from the current folder upwards;
      3. bin\Win32 (or the folder itself, extracted zip), from the current folder upwards.

    Output: one JSON line, ASCII only: {ok, cli, gui, source, checked, message, exitCode}
    Exit codes: 0 found | 12 not found.
    Usage: powershell -NoProfile -ExecutionPolicy Bypass -File "<skill>/scripts/localizar-jvcs2git.ps1" [-Text]

    This file is UTF-8 WITH BOM and CRLF (Windows PowerShell 5.1).
#>
[CmdletBinding()]
param([switch]$Text)

$ErrorActionPreference = 'Stop'
$checked = New-Object System.Collections.ArrayList
$found = $null

function Test-ExeDir {
    param([string]$Dir, [string]$Source)
    if ([string]::IsNullOrWhiteSpace($Dir)) { return $false }
    $d = $Dir.Trim().Trim('"').TrimEnd('\', '/')
    foreach ($c in @($d, (Join-Path $d 'bin\Win32'))) {
        [void]$checked.Add("$Source -> $c")
        if (Test-Path -LiteralPath (Join-Path $c 'jvcs2git-cli.exe') -PathType Leaf) {
            $script:found = [pscustomobject]@{ Dir = (Resolve-Path -LiteralPath $c).Path.TrimEnd('\'); Source = $Source }
            return $true
        }
    }
    return $false
}

function Get-Ancestors {
    $list = New-Object System.Collections.ArrayList
    $d = (Get-Location).ProviderPath
    while ($d) {
        [void]$list.Add($d)
        $p = [IO.Path]::GetDirectoryName($d)
        if (-not $p -or $p -eq $d) { break }
        $d = $p
    }
    return , $list
}

$ancestors = Get-Ancestors

# 1. environment variable
if (-not $found) { [void](Test-ExeDir $env:JVCS2GIT_HOME 'JVCS2GIT_HOME') }

# 2. project manifest
if (-not $found) {
    foreach ($a in $ancestors) {
        $mf = Join-Path $a '.claude\jvcs2git.managed.json'
        if (Test-Path -LiteralPath $mf -PathType Leaf) {
            try {
                $j = [IO.File]::ReadAllText($mf) | ConvertFrom-Json
                $dir = $null
                if ($j.home) { $dir = [string]$j.home } elseif ($j.cli) { $dir = Split-Path -Parent ([string]$j.cli) }
                if ($dir -and (Test-ExeDir $dir "manifest $mf")) { break }
            } catch { [void]$checked.Add("unreadable manifest: $mf") }
        }
    }
}

# 3. bin\Win32 (or extracted zip) from the current folder upwards
if (-not $found) {
    foreach ($a in $ancestors) { if (Test-ExeDir $a 'current folder and above') { break } }
}

$res = [ordered]@{ ok = $false; cli = $null; gui = $null; source = $null; checked = $checked; message = ''; exitCode = 12 }
if ($found) {
    $res.ok = $true
    $res.cli = Join-Path $found.Dir 'jvcs2git-cli.exe'
    $g = Join-Path $found.Dir 'jvcs2git.exe'
    if (Test-Path -LiteralPath $g -PathType Leaf) { $res.gui = $g }
    $res.source = $found.Source
    $res.message = "jvcs2git-cli.exe found ($($found.Source))"
    if (-not (Test-Path -LiteralPath (Join-Path $found.Dir 'fvcscrypt.dll') -PathType Leaf)) {
        $res.message += '; WARNING: fvcscrypt.dll is not next to the executable (jvcs2git will exit with 12)'
    }
    $res.exitCode = 0
} else {
    $res.message = 'jvcs2git-cli.exe not found. Extract the jvcs2git zip and set JVCS2GIT_HOME to the folder of the executables, or run from the extracted folder.'
}

if ($Text) {
    if ($res.ok) {
        Write-Output "[OK 0] $($res.message)"
        Write-Output "  cli: $($res.cli)"
        if ($res.gui) { Write-Output "  gui: $($res.gui)" }
    } else {
        Write-Output "[ERROR 12] $($res.message)"
        foreach ($c in $checked) { Write-Output "  checked: $c" }
    }
} else {
    $json = $res | ConvertTo-Json -Compress -Depth 4
    $sb = New-Object Text.StringBuilder
    foreach ($ch in $json.ToCharArray()) {
        if ([int]$ch -gt 127) { [void]$sb.AppendFormat('\u{0:x4}', [int]$ch) } else { [void]$sb.Append($ch) }
    }
    Write-Output $sb.ToString()
}
exit $res.exitCode
