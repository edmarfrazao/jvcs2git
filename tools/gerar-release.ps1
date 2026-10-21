param(
    [string]$Saida = '',          # pasta do zip (padrão: <raiz>\release)
    [string]$Destino = '',        # cópia opcional (ex.: pasta de instaladores); padrão: variável J2G_COPIA_RELEASE
    [switch]$SemCompilar,         # usa os exes já existentes em bin\Win32
    [switch]$ForcarRoot           # permite gerar com JVCS_ROOT definida (o aviso vai para as notas)
)
# Gera jvcs2git-<versão>-win32.zip (jvcs2git.exe, jvcs2git-cli.exe, fvcscrypt.dll,
# LICENSE, DISCLAIMER.md, LEIAME.txt, skills\) e SHA256.txt.
# A release sai SEMPRE do submódulo external\JEDI_VCS (a tag fixada); com JVCS_ROOT
# definida o script recusa, salvo -ForcarRoot. O SHA do submódulo vai para o LEIAME.
# Nenhum caminho pessoal fica no repositório: o destino da cópia vem de -Destino
# ou da variável de ambiente J2G_COPIA_RELEASE.
# Código de saída: 0 = ok; 1 = falha.
$ErrorActionPreference = 'Stop'
try {
    $raiz = Split-Path -Parent $PSScriptRoot
    if (-not $Saida) { $Saida = Join-Path $raiz 'release' }
    if (-not $Destino -and $env:J2G_COPIA_RELEASE) { $Destino = $env:J2G_COPIA_RELEASE }

    $avisoRoot = ''
    if ($env:JVCS_ROOT) {
        if (-not $ForcarRoot) { throw "JVCS_ROOT está definida ($env:JVCS_ROOT): a release deve sair do submódulo. Apague a variável ou use -ForcarRoot." }
        $avisoRoot = "ATENÇÃO: gerado com JVCS_ROOT=$env:JVCS_ROOT (não com o submódulo)."
    }
    $sub = Join-Path $raiz 'external\JEDI_VCS'
    $sha = (& git -C $sub rev-parse HEAD 2>$null)
    if (-not $sha) { throw "submódulo external\JEDI_VCS não inicializado (git submodule update --init)" }

    # versão: src\jvcs2git-ver.rh (fonte única)
    $rh = [IO.File]::ReadAllText((Join-Path $raiz 'src\jvcs2git-ver.rh'))
    if ($rh -notmatch 'J2G_VER_PRODUCTVERSION_STR\s+"([0-9.]+)\\000"') { throw 'versão não encontrada em src\jvcs2git-ver.rh' }
    $versao = $Matches[1]

    if (-not $SemCompilar) {
        $bat = Join-Path $raiz 'tools\compilar.bat'
        & cmd.exe /c "set JVCS_ROOT=&& set J2G_OUTDIR=&& set J2G_DCUDIR=&& `"$bat`" all Release"
        if ($LASTEXITCODE -ne 0) { throw "compilação falhou (código $LASTEXITCODE)" }
    }
    $bin = Join-Path $raiz 'bin\Win32'
    foreach ($f in 'jvcs2git.exe', 'jvcs2git-cli.exe', 'fvcscrypt.dll') {
        if (-not (Test-Path -LiteralPath (Join-Path $bin $f))) { throw "falta $bin\$f" }
    }

    $nome = "jvcs2git-$versao-win32"
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ("$nome-" + [Guid]::NewGuid().ToString('N'))
    $pasta = Join-Path $tmp $nome
    New-Item -ItemType Directory -Force $pasta | Out-Null
    foreach ($f in 'jvcs2git.exe', 'jvcs2git-cli.exe', 'fvcscrypt.dll') { Copy-Item -LiteralPath (Join-Path $bin $f) -Destination $pasta }
    foreach ($f in 'LICENSE', 'DISCLAIMER.md', 'README.md', 'README.pt-BR.md', 'CHANGELOG.md') {
        $p = Join-Path $raiz $f
        if (Test-Path -LiteralPath $p) { Copy-Item -LiteralPath $p -Destination $pasta }
    }
    $skills = Join-Path $raiz 'skills'
    if (Test-Path -LiteralPath $skills) { Copy-Item -LiteralPath $skills -Destination (Join-Path $pasta 'skills') -Recurse }

    $leiame = @(
        "jvcs2git $versao - JEDI VCS to Git exporter",
        '',
        'Código-fonte disponível em https://github.com/edmarfrazao/jvcs2git sob a MPL 1.1.',
        'Source code available at https://github.com/edmarfrazao/jvcs2git under the MPL 1.1.',
        'This product is based on MidWare. Freeware source code is available at http://www.overbyte.be.',
        '',
        'Uso / usage: jvcs2git.exe (janela / window) ou / or jvcs2git-cli.exe -? (console).',
        'Requisitos / requirements: Git 2.x no PATH; fvcscrypt.dll ao lado dos exes / next to the exes.',
        "Unidades do JEDI VCS / JEDI VCS units: external/JEDI_VCS @ $sha",
        'Veja README.md / README.pt-BR.md, LICENSE e DISCLAIMER.md.'
    )
    if ($avisoRoot) { $leiame += @('', $avisoRoot) }
    [IO.File]::WriteAllText((Join-Path $pasta 'LEIAME.txt'), (($leiame -join "`r`n") + "`r`n"), (New-Object Text.UTF8Encoding($true)))

    New-Item -ItemType Directory -Force $Saida | Out-Null
    $zip = Join-Path $Saida "$nome.zip"
    if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    Add-Type -AssemblyName System.IO.Compression
    # entradas com '/' (o CreateFromDirectory do .NET Framework grava '\')
    $arq = [IO.Compression.ZipFile]::Open($zip, [IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($f in (Get-ChildItem -LiteralPath $pasta -Recurse -File)) {
            $rel = $nome + '/' + $f.FullName.Substring($pasta.Length + 1).Replace('\', '/')
            [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($arq, $f.FullName, $rel, [IO.Compression.CompressionLevel]::Optimal)
        }
    } finally { $arq.Dispose() }
    Remove-Item -LiteralPath $tmp -Recurse -Force

    $hash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
    $linhas = foreach ($f in (Get-ChildItem -LiteralPath $Saida -Filter 'jvcs2git-*-win32.zip' -File | Sort-Object Name)) {
        "$((Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash)  $($f.Name)"
    }
    [IO.File]::WriteAllText((Join-Path $Saida 'SHA256.txt'), (($linhas -join "`r`n") + "`r`n"), (New-Object Text.UTF8Encoding($false)))
    "[OK] $zip (SHA-256 $hash; JEDI_VCS @ $($sha.Substring(0,7)))"
    if ($avisoRoot) { "[AVISO] $avisoRoot" }

    if ($Destino) {
        if (-not (Test-Path -LiteralPath $Destino -PathType Container)) { throw "pasta de destino não encontrada: $Destino" }
        $alvo = Join-Path $Destino (Split-Path -Leaf $zip)
        Copy-Item -LiteralPath $zip -Destination $alvo -Force
        if ((Get-FileHash -LiteralPath $alvo -Algorithm SHA256).Hash -ne $hash) { throw 'cópia com SHA-256 diferente' }
        $linhas = foreach ($f in (Get-ChildItem -LiteralPath $Destino -Filter 'jvcs2git-*-win32.zip' -File | Sort-Object Name)) {
            "$((Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash)  $($f.Name)"
        }
        [IO.File]::WriteAllText((Join-Path $Destino 'SHA256-jvcs2git.txt'), (($linhas -join "`r`n") + "`r`n"), (New-Object Text.UTF8Encoding($false)))
        "[OK] copiado para $alvo"
    }
    exit 0
} catch {
    "[FALHOU] gerar-release: $($_.Exception.Message)"
    exit 1
}
