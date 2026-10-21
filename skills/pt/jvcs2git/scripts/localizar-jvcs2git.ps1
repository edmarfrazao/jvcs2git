<#
.SYNOPSIS
    Localiza o jvcs2git-cli.exe (e o jvcs2git.exe) para a skill jvcs2git.

.DESCRIPTION
    Só leitura: não roda o jvcs2git, não lê senha nem chave, não grava nada.
    Ordem de busca (a primeira pasta com jvcs2git-cli.exe vence):
      1. variável de ambiente JVCS2GIT_HOME (pasta dos exes, ou raiz com bin\Win32);
      2. <projeto>\.claude\jvcs2git.managed.json (campo "home" ou "cli"), da pasta atual para cima;
      3. bin\Win32 (ou a própria pasta, zip extraído), da pasta atual para cima.

    Saída: JSON numa linha, só ASCII: {ok, cli, gui, source, checked, message, exitCode}
    Códigos: 0 encontrado | 12 não encontrado.
    Uso: powershell -NoProfile -ExecutionPolicy Bypass -File "<skill>/scripts/localizar-jvcs2git.ps1" [-Text]

    Este arquivo é UTF-8 COM BOM e CRLF (Windows PowerShell 5.1).
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

# 1. variável de ambiente
if (-not $found) { [void](Test-ExeDir $env:JVCS2GIT_HOME 'JVCS2GIT_HOME') }

# 2. manifesto no projeto
if (-not $found) {
    foreach ($a in $ancestors) {
        $mf = Join-Path $a '.claude\jvcs2git.managed.json'
        if (Test-Path -LiteralPath $mf -PathType Leaf) {
            try {
                $j = [IO.File]::ReadAllText($mf) | ConvertFrom-Json
                $dir = $null
                if ($j.home) { $dir = [string]$j.home } elseif ($j.cli) { $dir = Split-Path -Parent ([string]$j.cli) }
                if ($dir -and (Test-ExeDir $dir "manifesto $mf")) { break }
            } catch { [void]$checked.Add("manifesto ilegível: $mf") }
        }
    }
}

# 3. bin\Win32 (ou zip extraído) da pasta atual para cima
if (-not $found) {
    foreach ($a in $ancestors) { if (Test-ExeDir $a 'pasta atual e acima') { break } }
}

$res = [ordered]@{ ok = $false; cli = $null; gui = $null; source = $null; checked = $checked; message = ''; exitCode = 12 }
if ($found) {
    $res.ok = $true
    $res.cli = Join-Path $found.Dir 'jvcs2git-cli.exe'
    $g = Join-Path $found.Dir 'jvcs2git.exe'
    if (Test-Path -LiteralPath $g -PathType Leaf) { $res.gui = $g }
    $res.source = $found.Source
    $res.message = "jvcs2git-cli.exe encontrado ($($found.Source))"
    if (-not (Test-Path -LiteralPath (Join-Path $found.Dir 'fvcscrypt.dll') -PathType Leaf)) {
        $res.message += '; ATENÇÃO: fvcscrypt.dll não está ao lado do exe (o jvcs2git sairá com 12)'
    }
    $res.exitCode = 0
} else {
    $res.message = 'jvcs2git-cli.exe não encontrado. Extraia o zip do jvcs2git e defina JVCS2GIT_HOME com a pasta dos exes, ou rode a partir da pasta extraída.'
}

if ($Text) {
    if ($res.ok) {
        Write-Output "[OK 0] $($res.message)"
        Write-Output "  cli: $($res.cli)"
        if ($res.gui) { Write-Output "  gui: $($res.gui)" }
    } else {
        Write-Output "[ERRO 12] $($res.message)"
        foreach ($c in $checked) { Write-Output "  verificado: $c" }
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
