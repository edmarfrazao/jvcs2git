# Testes do jvcs2git-cli.exe contra um servidor JEDI VCS de TESTE (só leitura no servidor).
#
# Casos (ver doc\pt\Uso.md):
#   1. pré-condições: identidade, git no PATH, jvcs2git-cli.exe + fvcscrypt.dll, console jvcs.exe (opcional);
#      -selftest paths e -selftest blob
#   2. exportação -nogroup -json (cache apagado só com código 0; com pulados, código 11, ele fica)
#   3. git rev-list --count main = R - S + 1 (R = RevIDs distintos do history do console, S = revisões com
#      TODOS os membros pulados, +1 = commit do .gitattributes); JSON commits = R - S; git fsck sem badDate;
#      git log --since=1980-01-01 --oneline = rev-list --count
#   4. -group 10: commits <= caso 2; git log --stat sem erro
#   5. conteúdo: 2-3 módulos baixados pelo console (getmodule) comparados byte a byte com o repositório
#      (-nodfmtext); sem a opção, .dfm binário (TPF0) vira texto ('object ...')
#   6. git tag -n contém os labels de listlabels <projeto> (nomes saneados), também para -ProjetoLabels
#      (exportado à parte); cada tag aponta para o commit da revisão rotulada mais recente
#   7. -nogit gera <repo>.fast-import ('feature done' ... 'done') e git fast-import num repo vazio retorna 0
#   8. -list -json contém os projetos de exemplo; -project inexistente sai 5; sem git no PATH sai 12;
#      -identity com stdin vazio funciona; <host> -user <u> com stdin vazio sai 4; -password/-encodekey saem 2;
#      -encodekey-file dentro de -out sai 2; a chave nunca aparece no stdout/stderr/log
#   9. retomada: -nogit -keepcache e depois -force reaproveita o cache (blobsDownloaded = só os membros
#      recusados na 1ª rodada, cifrados/CRC, que não entram no cache); cache com .tmp
#      ou tamanho errado é baixado de novo; pasta existente sem -force sai 12; -force numa pasta que não foi
#      gerada pelo jvcs2git sai 12 e não apaga nada
#   +  nenhum caminho do repositório difere de outro só pela caixa (git ls-files | sort -f | uniq -di vazio)
#
# Sem console: casos 3, 5 e 6 [PULADO]. Sem git: casos que usam git [PULADO].
# Enquanto a exportação não existir no exe (mensagem "not implemented"), os casos que dependem dela saem [PULADO].
#
# A senha nunca é lida por este script: o jvcs2git-cli lê a identidade sozinho (-identity) e o console é chamado
# pelo golden.ps1 do JEDI VCS. Do registro, este script só lê HostName, Port e User.
# Saída: linhas [OK]/[FALHOU]/[PULADO] e um resumo; código 0 só se nada falhou.
# Gravar em UTF-8 COM BOM e CRLF (Windows PowerShell 5.1).
param(
    [string]$Servidor = '',                                  # host[:porta]; padrão: HostName:Port da identidade
    [string]$Identidade = 'DEFAULT',
    [string]$Console = '',                                   # jvcs.exe do JEDI VCS 2026 (ver fallbacks abaixo)
    [string]$Saida = (Join-Path $env:TEMP 'jvcs2git-testes'),
    [string]$Cli = '',                                       # padrão: <repo>\bin\Win32\jvcs2git-cli.exe
    [string]$Projeto = 'exemplo01.dpr',
    [string]$ProjetoLabels = 'ex4ia.dpr',                    # projeto com label (caso 6); '' = só o -Projeto
    [string[]]$ProjetosEsperados = @('exemplo01.dpr=1', 'ex2.dpr=2', 'ex4ia.dpr=3')
)
$ErrorActionPreference = 'Stop'
$Raiz = Split-Path -Parent $PSScriptRoot
$okN = 0; $falhas = 0; $pulados = 0
function Ok([bool]$c, [string]$m) { if ($c) { Write-Output "[OK] $m"; $script:okN++ } else { Write-Output "[FALHOU] $m"; $script:falhas++ } }
function Pular([string]$m) { Write-Output "[PULADO] $m"; $script:pulados++ }
function Info([string]$m) { Write-Output "     $m" }

# ---------------------------------------------------------------- utilitários
function Format-Arg([string]$a) {
    if ($a -ne '' -and $a -notmatch '[\s"]') { return $a }
    $q = $a -replace '(\\*)"', '$1$1\"'
    $q = $q -replace '(\\+)$', '$1$1'
    return '"' + $q + '"'
}

# roda um processo; stdin = conteúdo de $EntradaArquivo ou vazio (fechado logo: EOF, como "< NUL")
function Invoke-Processo {
    param([string]$Exe, [string[]]$Argumentos, [string]$Cwd = '', [string]$EntradaArquivo = '',
        [hashtable]$Ambiente = $null, [int]$TimeoutSeg = 3600)
    $psi = New-Object Diagnostics.ProcessStartInfo $Exe
    $psi.Arguments = (@($Argumentos | ForEach-Object { Format-Arg $_ }) -join ' ')
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    if ($Cwd) { $psi.WorkingDirectory = $Cwd }
    if ($Ambiente) { foreach ($k in $Ambiente.Keys) { $psi.EnvironmentVariables[$k] = [string]$Ambiente[$k] } }
    # com InputEncoding UTF-8 com BOM o .NET escreveria o BOM no stdin ao fechar (viraria "senha")
    $old = [Console]::InputEncoding
    try {
        if ($old.GetPreamble().Length -gt 0) { [Console]::InputEncoding = [Text.Encoding]::GetEncoding(1252) }
        $p = [Diagnostics.Process]::Start($psi)
    } finally { [Console]::InputEncoding = $old }
    $ms = New-Object IO.MemoryStream
    $tOut = $p.StandardOutput.BaseStream.CopyToAsync($ms)
    $tErr = $p.StandardError.ReadToEndAsync()
    try {
        if ($EntradaArquivo) {
            $fs = [IO.File]::OpenRead($EntradaArquivo)
            try { $fs.CopyTo($p.StandardInput.BaseStream) } finally { $fs.Close() }
        }
    } finally { $p.StandardInput.Close() }
    if (-not $p.WaitForExit($TimeoutSeg * 1000)) { $p.Kill(); throw "timeout: $Exe $($psi.Arguments)" }
    $p.WaitForExit()
    $tOut.Wait()
    $b = $ms.ToArray()
    [pscustomobject]@{ Codigo = $p.ExitCode; Bytes = $b; Saida = [Text.Encoding]::UTF8.GetString($b); Erro = [string]$tErr.Result }
}

# roda o jvcs2git-cli e interpreta a linha JSON (quando houver)
function Invoke-J2G {
    param([string[]]$Argumentos, [hashtable]$Ambiente = $null)
    $r = Invoke-Processo -Exe $Cli -Argumentos $Argumentos -Ambiente $Ambiente
    $json = $null
    $linhas = @($r.Saida -split "`r?`n" | Where-Object { $_.Trim() -ne '' })
    if ($linhas.Count -gt 0) {
        try { $json = $linhas[$linhas.Count - 1] | ConvertFrom-Json } catch { $json = $null }
    }
    $r | Add-Member -NotePropertyName Json -NotePropertyValue $json
    $r | Add-Member -NotePropertyName NaoImplementado -NotePropertyValue ($r.Erro -match 'not implemented')
    return $r
}

function Invoke-Git {
    param([string]$Repo, [string[]]$Argumentos, [string]$EntradaArquivo = '')
    $a = @()
    if ($Repo) { $a += @('-C', $Repo) }
    $a += $Argumentos
    return Invoke-Processo -Exe $GitExe -Argumentos $a -EntradaArquivo $EntradaArquivo
}

function Get-RepoDir($json) {
    $p = @($json.projects)
    if ($p.Count -lt 1 -or -not $p[0].repo) { return $null }
    return ([string]$p[0].repo) -replace '/', '\'
}

function Test-ExportOk($r) { return ($r.Codigo -eq 0 -or $r.Codigo -eq 11) -and $r.Json -and (@($r.Json.projects).Count -ge 1) }

# saneamento de nome de tag (mesmas regras do git check-ref-format usadas pelo jvcs2git)
#  (J2GPaths.J2GSanitizeTagName: também < > | " viram '-'; '-' e '.' saem das pontas de cada componente;
#   nomes de dispositivo do Windows ganham '_' - não reproduzido aqui)
function Get-TagSaneado([string]$Nome, [string]$Id) {
    $s = -join ($Nome.Trim().ToCharArray() | ForEach-Object { if ([int]$_ -lt 32 -or [int]$_ -eq 127 -or ' ~^:?*[\<>|"'.Contains([string]$_)) { '-' } else { $_ } })
    while ($s.Contains('..')) { $s = $s.Replace('..', '-') }
    while ($s.Contains('@{')) { $s = $s.Replace('@{', '-') }
    while ($s.Contains('--')) { $s = $s.Replace('--', '-') }
    if ($s.Length -gt 120) { $s = $s.Substring(0, 120) }
    $comp = @($s -split '/' | ForEach-Object {
            $c = $_
            do {
                $antes = $c; $c = $c.Trim('-').Trim('.')
                if ($c.Length -ge 5 -and $c.EndsWith('.lock', [StringComparison]::OrdinalIgnoreCase)) { $c = $c.Substring(0, $c.Length - 5) }
            } while ($c -ne $antes)
            $c } | Where-Object { $_ -ne '' })
    $s = $comp -join '/'
    if ($s -eq '' -or $s -eq '@') { $s = "label-$Id" }
    return $s
}

# console do JEDI VCS pelo golden.ps1 (senha da identidade DEFAULT direto no stdin do console)
$Golden = Join-Path $Raiz 'external\JEDI_VCS\tests\console\golden.ps1'
$SaidaConsole = Join-Path $Saida 'console'
function Invoke-Console([string]$Nome, [string[]]$Linhas, [string]$Cwd = '') {
    $a = @{ Nome = $Nome; Exe = $Console; Saida = $SaidaConsole; Linhas = $Linhas; Servidor = $HostSrv; Porta = [int]$PortaSrv }
    if ($Cwd) { $a.Cwd = $Cwd }
    & $Golden @a | Out-Null
    $t = [IO.File]::ReadAllText((Join-Path $SaidaConsole "$Nome.txt"), [Text.Encoding]::GetEncoding(1252)).Replace([string][char]0, ' ')
    return $t
}

# ---------------------------------------------------------------- 1. pré-condições
Write-Output '==== 1. pré-condições'
if (-not $Cli) { $Cli = Join-Path $Raiz 'bin\Win32\jvcs2git-cli.exe' }
$temCli = Test-Path -LiteralPath $Cli -PathType Leaf
Ok $temCli "jvcs2git-cli.exe: $Cli"
if (-not $temCli) { Write-Output "==== OK: $okN  FALHOU: $falhas  PULADO: $pulados"; exit 1 }
Ok (Test-Path -LiteralPath (Join-Path (Split-Path -Parent $Cli) 'fvcscrypt.dll')) 'fvcscrypt.dll ao lado do exe'

$chaveReg = "HKCU:\Software\JEDI\JEDIVCS\Identities\$Identidade"
$ident = Get-Item -LiteralPath $chaveReg -ErrorAction SilentlyContinue
$HostSrv = ''; $PortaSrv = ''; $UserSrv = ''
if ($ident) {
    # só estes valores; a senha não é lida
    $HostSrv = [string]$ident.GetValue('HostName'); $PortaSrv = [string]$ident.GetValue('Port'); $UserSrv = [string]$ident.GetValue('User')
}
Ok ([bool]$ident -and $HostSrv -ne '' -and $UserSrv -ne '') "identidade $Identidade cadastrada (HostName e User)"
$servidorDado = $PSBoundParameters.ContainsKey('Servidor') -and $Servidor
if ($servidorDado) {
    $i = $Servidor.LastIndexOf(':')
    if ($i -gt 0) { $HostSrv = $Servidor.Substring(0, $i); $PortaSrv = $Servidor.Substring($i + 1) } else { $HostSrv = $Servidor }
}
if (-not $PortaSrv) { $PortaSrv = '2106' }
if (-not $Servidor) { $Servidor = "$($HostSrv):$PortaSrv" }
Info "servidor: $Servidor  identidade: $Identidade  projeto: $Projeto"
# argumentos de conexão do jvcs2git-cli: sempre -identity; host só se -Servidor foi dado
$Con = @('-identity', $Identidade)
if ($servidorDado) { $Con = @($Servidor) + $Con }

$GitExe = $null
$g = Get-Command git -ErrorAction SilentlyContinue
if ($g) { $GitExe = $g.Source }
if ($GitExe) {
    $v = Invoke-Processo -Exe $GitExe -Argumentos @('--version')
    Ok ($v.Codigo -eq 0) "git no PATH: $($v.Saida.Trim())"
} else { Pular 'git não está no PATH: casos que usam git serão pulados' }

if (-not $Console -and $env:JVCS_ROOT) {
    $c = Join-Path $env:JVCS_ROOT 'bin\client\Win32\jvcs.exe'
    if (Test-Path -LiteralPath $c) { $Console = $c }
}
if (-not $Console -and ${env:ProgramFiles(x86)}) {
    $c = Join-Path ${env:ProgramFiles(x86)} 'JEDI\JVCS 2026\jvcs.exe'
    if (Test-Path -LiteralPath $c) { $Console = $c }
}
$temConsole = $Console -and (Test-Path -LiteralPath $Console -PathType Leaf) -and (Test-Path -LiteralPath $Golden) -and ($Identidade -eq 'DEFAULT')
if ($temConsole) { Info "console: $Console" } else { Pular 'console jvcs.exe/golden.ps1 não encontrado (ou identidade diferente de DEFAULT): casos 3, 5 e 6 serão pulados' }

# pasta de trabalho: só apaga o que este teste criou (marcador)
$marca = Join-Path $Saida '.jvcs2git-teste'
if (Test-Path -LiteralPath $Saida) {
    if (@(Get-ChildItem -LiteralPath $Saida -Force).Count -gt 0 -and -not (Test-Path -LiteralPath $marca)) {
        throw "a pasta $Saida existe e não foi criada por este teste; use -Saida <outra pasta>"
    }
    Get-ChildItem -LiteralPath $Saida -Force | Where-Object { $_.Name -ne '.jvcs2git-teste' } | Remove-Item -Recurse -Force
}
New-Item -ItemType Directory -Force $Saida | Out-Null
[IO.File]::WriteAllText($marca, "pasta de trabalho de tests\teste-jvcs2git.ps1`r`n")

foreach ($st in @('paths', 'blob')) {
    $r = Invoke-J2G @('-selftest', $st, '-json')
    $w = ''; if ($r.Json -and $r.Json.warnings) { $w = ' (' + (@($r.Json.warnings) -join '; ') + ')' }
    Ok ($r.Codigo -eq 0 -and $r.Json -and $r.Json.ok) "-selftest $st sai 0$w"
}

# ---------------------------------------------------------------- 8. lista, códigos de uso e de credencial
Write-Output '==== 8. -list, códigos 2/4/5, chave'
$r = Invoke-J2G (@($Con) + @('-list', '-json'))
Ok ($r.Codigo -eq 0 -and $r.Json -and $r.Json.ok -and $r.Json.command -eq 'list') "-identity $Identidade -list -json com stdin vazio sai 0"
$lista = @(); if ($r.Json) { $lista = @($r.Json.projects) }
foreach ($e in $ProjetosEsperados) {
    $n, $id = $e -split '=', 2
    Ok (@($lista | Where-Object { $_.name -ieq $n -and [string]$_.id -eq $id }).Count -eq 1) "-list contém $n (ID $id)"
}
$ProjetoInfo = $lista | Where-Object { $_.name -ieq $Projeto } | Select-Object -First 1

$r = Invoke-J2G (@($Con) + @('-project', 'zz-nao-existe-jvcs2git.dpr', '-out', (Join-Path $Saida 'naoexiste'), '-json'))
Ok ($r.Codigo -eq 5 -and $r.Json -and $r.Json.exitCode -eq 5) '-project inexistente sai 5'

$r = Invoke-J2G @("$($HostSrv):$PortaSrv", '-user', $UserSrv, '-list', '-json')
Ok ($r.Codigo -eq 4 -and $r.Json -and $r.Json.exitCode -eq 4) '<host> -user <u> com stdin vazio sai 4 (senha não informada)'
$r = Invoke-J2G @('-identity', 'zz-identidade-inexistente-jvcs2git', '-list', '-json')
Ok ($r.Codigo -eq 4) 'identidade inexistente sai 4'
$r = Invoke-J2G (@($Con) + @('-list', '-password', 'x', '-json'))
Ok ($r.Codigo -eq 2 -and $r.Json -and $r.Json.exitCode -eq 2) '-password não existe: sai 2'
$r = Invoke-J2G (@($Con) + @('-project', $Projeto, '-dryrun', '-encodekey', 'QUJDREVGR0g=', '-json'))
Ok ($r.Codigo -eq 2) '-encodekey <base64> não existe: sai 2'
$r = Invoke-J2G @('-list', '-json')
Ok ($r.Codigo -eq 2) 'sem <host> nem -identity: sai 2'
$r = Invoke-J2G (@($Con) + @('-project', $Projeto, '-all', '-out', (Join-Path $Saida 'x'), '-json'))
Ok ($r.Codigo -eq 2) '-project com -all: sai 2'

# chave de teste aleatória (não é chave real); nunca pode aparecer em stdout, stderr ou log
$rnd = New-Object byte[] 16; (New-Object Security.Cryptography.RNGCryptoServiceProvider).GetBytes($rnd)
$chave = [Convert]::ToBase64String($rnd)
$dentro = Join-Path $Saida 'chave-dentro'
New-Item -ItemType Directory -Force $dentro | Out-Null
$arqDentro = Join-Path $dentro 'chave.txt'; [IO.File]::WriteAllText($arqDentro, "$chave`r`n")
$r = Invoke-J2G (@($Con) + @('-project', $Projeto, '-out', $dentro, '-encodekey-file', $arqDentro, '-json'))
Ok ($r.Codigo -eq 2) '-encodekey-file dentro de -out sai 2'
Ok (-not ($r.Saida + $r.Erro).Contains($chave)) 'a chave não aparece na saída (caso -encodekey-file dentro de -out)'
$fora = Join-Path $Saida 'chave-fora'
New-Item -ItemType Directory -Force $fora | Out-Null
$arqFora = Join-Path $fora 'chave.txt'; [IO.File]::WriteAllText($arqFora, "$chave`r`n")
$logChave = Join-Path $Saida 'chave-log\jvcs2git.log'
$r = Invoke-J2G (@($Con) + @('-project', $Projeto, '-dryrun', '-encodekey-file', $arqFora, '-log', $logChave, '-json'))
$txtLog = ''; if (Test-Path -LiteralPath $logChave) { $txtLog = [IO.File]::ReadAllText($logChave) }
Ok (-not ($r.Saida + $r.Erro + $txtLog).Contains($chave)) "-dryrun -encodekey-file: a chave não aparece no JSON, na stderr nem no log (código $($r.Codigo))"
Remove-Item -Recurse -Force $dentro, $fora

# ---------------------------------------------------------------- 2. exportação -nogroup
Write-Output '==== 2. exportação -nogroup'
$exportOk = $false
$Repo2 = $null; $J2 = $null
$out2 = Join-Path $Saida 'nogroup'
$r2 = Invoke-J2G (@($Con) + @('-project', $Projeto, '-out', $out2, '-nogroup', '-json'))
if ($r2.NaoImplementado) {
    Pular "exportação ainda não implementada neste exe (código $($r2.Codigo)): casos 2-7, 9 e extras pulados"
} else {
    $exportOk = Test-ExportOk $r2
    Ok $exportOk "exportação -nogroup sai 0 ou 11 (código $($r2.Codigo): $($r2.Json.message))"
    if ($exportOk) {
        $J2 = @($r2.Json.projects)[0]
        $Repo2 = Get-RepoDir $r2.Json
        Info "repo: $Repo2  commits: $($J2.commits)  revisões: $($J2.revisions)  tags: $($J2.tags)  pulados: $(@($J2.skipped).Count)"
        Ok (Test-Path -LiteralPath (Join-Path $Repo2 '.git')) 'repositório criado'
        Ok (Test-Path -LiteralPath (Join-Path $out2 'jvcs2git.log')) 'jvcs2git.log criado'
        Ok (Test-Path -LiteralPath (Join-Path $out2 'jvcs2git-relatorio.md')) 'jvcs2git-relatorio.md criado'
        Ok (Test-Path -LiteralPath (Join-Path $out2 'autores.txt')) 'autores.txt criado'
        # o cache só é apagado quando tudo deu certo (código 0); com pulados (11) ele fica para a nova tentativa
        $temCache2 = Test-Path -LiteralPath (Join-Path $out2 '.jvcs2git-cache')
        if ($r2.Codigo -eq 0) { Ok (-not $temCache2) 'cache apagado após importação sem pulados (código 0, sem -keepcache)' }
        else { Ok $temCache2 'cache preservado quando há pulados (código 11)' }
        Ok ($r2.Codigo -eq 11 -or @($J2.skipped).Count -eq 0) 'código 0 só quando não há pulados'
    }
}
$podeGit = $exportOk -and $GitExe

# ---------------------------------------------------------------- 3. contagem de commits
Write-Output '==== 3. contagem de commits e datas'
$histRev = @{}   # RevID -> nº de membros (extensões) ; $null se a coluna Files veio truncada
$modulos = @()
if (-not $podeGit) { Pular 'caso 3: exportação ou git indisponível' }
elseif (-not $temConsole) { Pular 'caso 3: sem console jvcs.exe' }
else {
    $t = Invoke-Console 'j2g_listmodules' @("listmodules $Projeto")
    foreach ($l in ($t -split "`r?`n")) {
        $m = [regex]::Match($l, '^(\d+)\s+(\S*)\s+(.*)\|(.+)$')
        if ($m.Success) { $modulos += [pscustomobject]@{ Id = $m.Groups[1].Value; Flags = $m.Groups[2].Value.Trim(); Path = $m.Groups[3].Value; Name = $m.Groups[4].Value.Trim(); Exts = @() } }
    }
    Ok ($modulos.Count -gt 0) "listmodules $Projeto : $($modulos.Count) módulo(s)"
    $linhas = @("openproject $Projeto") + @($modulos | ForEach-Object { "history $($_.Id)" })
    $t = Invoke-Console 'j2g_history' $linhas
    $atual = $null
    foreach ($l in ($t -split "`r?`n")) {
        $mm = [regex]::Match($l, '^Module: .*\(ID (\d+)\)')
        if ($mm.Success) { $atual = $modulos | Where-Object { $_.Id -eq $mm.Groups[1].Value } | Select-Object -First 1; continue }
        $m = [regex]::Match($l, '^\d+\.\d+\s+(\d+)\s')
        if ($m.Success) {
            $files = ''; if ($l.Length -gt 73) { $files = $l.Substring(73, [Math]::Min(30, $l.Length - 73)).Trim() }
            $n = $null; if ($files -and -not $files.EndsWith('...')) { $n = @($files -split ',').Count }
            $histRev[$m.Groups[1].Value] = $n
            if ($atual -and -not $atual.Exts.Count -and $files) { $atual.Exts = @($files -split ',') }
        }
    }
    $R = $histRev.Count
    $S = 0
    foreach ($grp in (@($J2.skipped) | Group-Object revisionId)) {
        $n = $histRev[[string]$grp.Name]
        if ($null -eq $n) { Info "aviso: membros da revisão $($grp.Name) desconhecidos (coluna Files truncada)" }
        elseif ($grp.Count -ge $n) { $S++ }
    }
    $mais1 = 1
    $c = Invoke-Git $Repo2 @('rev-list', '--count', 'main')
    $cont = [int]($c.Saida.Trim())
    Ok ($cont -eq ($R - $S + $mais1)) "git rev-list --count main = $cont; esperado R - S + 1 = $R - $S + 1"
    Ok ([int]$J2.commits -eq ($R - $S)) "JSON commits = $($J2.commits); esperado R - S = $($R - $S)"
}
if ($podeGit) {
    $f = Invoke-Git $Repo2 @('fsck', '--full')
    Ok ($f.Codigo -eq 0 -and ($f.Saida + $f.Erro) -notmatch 'badDate') 'git fsck sem erro e sem badDate'
    $c = Invoke-Git $Repo2 @('rev-list', '--count', 'main')
    $s = Invoke-Git $Repo2 @('log', '--since=1980-01-01', '--oneline', 'main')
    $nSince = @($s.Saida -split "`r?`n" | Where-Object { $_ -ne '' }).Count
    Ok ($nSince -eq [int]($c.Saida.Trim())) "git log --since=1980-01-01 --oneline ($nSince) = rev-list --count ($($c.Saida.Trim()))"
    $ls = Invoke-Git $Repo2 @('ls-files')
    $dup = @($ls.Saida -split "`r?`n" | Where-Object { $_ -ne '' } | Group-Object { $_.ToLowerInvariant() } | Where-Object { $_.Count -gt 1 })
    Ok ($dup.Count -eq 0) 'nenhum caminho difere de outro só pela caixa (git ls-files | sort -f | uniq -di vazio)'
    if ($dup.Count -gt 0) { $dup | ForEach-Object { Info "colisão: $($_.Group -join ' / ')" } }
    $ga = Invoke-Git $Repo2 @('show', 'main:.gitattributes')
    Ok ($ga.Codigo -eq 0 -and $ga.Saida -match '\* -text') '.gitattributes com "* -text"'
}

# ---------------------------------------------------------------- 4. -group 10
Write-Output '==== 4. -group 10'
if (-not $podeGit) { Pular 'caso 4: exportação ou git indisponível' }
else {
    $out4 = Join-Path $Saida 'group10'
    $r4 = Invoke-J2G (@($Con) + @('-project', $Projeto, '-out', $out4, '-group', '10', '-json'))
    Ok (Test-ExportOk $r4) "exportação -group 10 sai 0 ou 11 (código $($r4.Codigo))"
    if (Test-ExportOk $r4) {
        $J4 = @($r4.Json.projects)[0]
        Ok ([int]$J4.commits -le [int]$J2.commits) "commits com -group 10 ($($J4.commits)) <= -nogroup ($($J2.commits))"
        $st = Invoke-Git (Get-RepoDir $r4.Json) @('log', '--stat', 'main')
        Ok ($st.Codigo -eq 0) 'git log --stat sem erro'
        $tn = Invoke-Git (Get-RepoDir $r4.Json) @('tag', '-n')
        Ok ($tn.Codigo -eq 0) 'git tag -n sem erro'
    }
}

# ---------------------------------------------------------------- 5. conteúdo
Write-Output '==== 5. conteúdo byte a byte'
function Get-GitBlob([string]$Repo, [string]$Caminho) {
    $b = Invoke-Git $Repo @('cat-file', 'blob', "main:$Caminho")
    if ($b.Codigo -ne 0) { return $null }
    return , $b.Bytes
}
function Find-GitPath([string]$Repo, [string]$Folha) {
    $ls = Invoke-Git $Repo @('ls-files')
    return @($ls.Saida -split "`r?`n" | Where-Object { $_ -ne '' -and ($_ -split '/')[-1] -ieq $Folha })
}
function Test-MesmosBytes([byte[]]$A, [byte[]]$B) {
    if ($null -eq $A -or $null -eq $B -or $A.Length -ne $B.Length) { return $false }
    for ($i = 0; $i -lt $A.Length; $i++) { if ($A[$i] -ne $B[$i]) { return $false } }
    return $true
}
if (-not $podeGit) { Pular 'caso 5: exportação ou git indisponível' }
elseif (-not $temConsole -or $modulos.Count -eq 0) { Pular 'caso 5: sem console jvcs.exe (ou sem módulos lidos no caso 3)' }
else {
    $out5 = Join-Path $Saida 'nodfmtext'
    $r5 = Invoke-J2G (@($Con) + @('-project', $Projeto, '-out', $out5, '-nodfmtext', '-json'))
    Ok (Test-ExportOk $r5) "exportação -nodfmtext sai 0 ou 11 (código $($r5.Codigo))"
    $Repo5 = Get-RepoDir $r5.Json
    # até 3 módulos com revisão: de preferência um com .dfm
    $cands = @($modulos | Where-Object { $_.Flags -notmatch 'B' -and $_.Exts.Count -gt 0 })
    $escolha = @($cands | Where-Object { $_.Exts -contains '.dfm' } | Select-Object -First 1) + @($cands | Where-Object { $_.Exts -notcontains '.dfm' } | Select-Object -First 2)
    $escolha = @($escolha | Where-Object { $_ })
    $puladosRev = @(@($J2.skipped) | ForEach-Object { [string]$_.module })
    foreach ($m in $escolha) {
        $dest = Join-Path $Saida "getmodule\$($m.Id)"
        New-Item -ItemType Directory -Force $dest | Out-Null
        Invoke-Console "j2g_get_$($m.Id)" @("openproject $Projeto", "getmodule $($m.Id) dest=""$dest"" noprompt") | Out-Null
        $arqs = @(Get-ChildItem -LiteralPath $dest -File -Recurse)
        if ($arqs.Count -eq 0) { Ok $false "getmodule $($m.Name) (ID $($m.Id)) não baixou arquivos"; continue }
        foreach ($a in $arqs) {
            $orig = [IO.File]::ReadAllBytes($a.FullName)
            $c5 = @(Find-GitPath $Repo5 $a.Name)
            if ($puladosRev -contains $a.Name) {
                # alguma revisão do módulo foi pulada: só confere se a última foi exportada (bytes iguais)
                if ($c5.Count -eq 1 -and (Test-MesmosBytes $orig (Get-GitBlob $Repo5 $c5[0]))) { Ok $true "$($c5[0]) (-nodfmtext) igual byte a byte ao getmodule (módulo com revisão pulada)" }
                else { Pular "$($a.Name): membro pulado na exportação" }
                continue
            }
            if ($c5.Count -ne 1) { Ok $false "$($a.Name): $($c5.Count) caminho(s) no repositório"; continue }
            Ok (Test-MesmosBytes $orig (Get-GitBlob $Repo5 $c5[0])) "$($c5[0]) (-nodfmtext) igual byte a byte ao getmodule"
            $c2 = @(Find-GitPath $Repo2 $a.Name)
            if ($c2.Count -ne 1) { continue }
            $g2 = Get-GitBlob $Repo2 $c2[0]
            $ehTpf0 = $orig.Length -ge 4 -and $orig[0] -eq 0x54 -and $orig[1] -eq 0x50 -and $orig[2] -eq 0x46 -and $orig[3] -eq 0x30
            if ($a.Extension -ieq '.dfm' -and $ehTpf0) {
                $txt = ''; if ($g2) { $txt = [Text.Encoding]::ASCII.GetString($g2, 0, [Math]::Min(20, $g2.Length)) }
                Ok ($txt -match '^(object|inherited|inline) ') "$($c2[0]): .dfm binário (TPF0) exportado como texto"
            } else {
                Ok (Test-MesmosBytes $orig $g2) "$($c2[0]) (padrão) igual byte a byte ao getmodule"
            }
        }
    }
}

# ---------------------------------------------------------------- 6. labels -> tags
Write-Output '==== 6. labels como tags'
if (-not $podeGit) { Pular 'caso 6: exportação ou git indisponível' }
elseif (-not $temConsole) { Pular 'caso 6: sem console jvcs.exe' }
else {
    # o projeto principal e, se for outro, o projeto com labels (exportado com -nogroup em <Saida>\labels)
    $alvos = @([pscustomobject]@{ Projeto = $Projeto; Repo = $Repo2; J = $J2 })
    if ($ProjetoLabels -and $ProjetoLabels -ine $Projeto) {
        $r6 = Invoke-J2G (@($Con) + @('-project', $ProjetoLabels, '-out', (Join-Path $Saida 'labels'), '-nogroup', '-json'))
        Ok (Test-ExportOk $r6) "exportação de $ProjetoLabels sai 0 ou 11 (código $($r6.Codigo))"
        if (Test-ExportOk $r6) { $alvos += [pscustomobject]@{ Projeto = $ProjetoLabels; Repo = (Get-RepoDir $r6.Json); J = @($r6.Json.projects)[0] } }
    }
    foreach ($alvo in $alvos) {
        $t = Invoke-Console "j2g_listlabels_$($alvo.J.id)" @("listlabels $($alvo.Projeto)")
        $labels = @()
        foreach ($l in ($t -split "`r?`n")) {
            $m = [regex]::Match($l, '^(\d+)\s+(.{50})\s+(\d+)\s')
            if ($m.Success) { $labels += [pscustomobject]@{ Id = $m.Groups[1].Value; Nome = $m.Groups[2].Value.Trim() } }
        }
        $tg = Invoke-Git $alvo.Repo @('tag', '-l')
        $tags = @($tg.Saida -split "`r?`n" | Where-Object { $_ -ne '' })
        Ok ($tags.Count -eq [int]$alvo.J.tags) "$($alvo.Projeto): git tag -l ($($tags.Count)) = JSON tags ($($alvo.J.tags))"
        $semCommit = @(@($alvo.J.skipped) | Where-Object { $_.reason -eq 'noCommit' }).Count
        if ($labels.Count -eq 0) { Info "$($alvo.Projeto) não tem labels" }
        foreach ($lb in $labels) {
            if ($lb.Nome.EndsWith('...')) { Info "label $($lb.Id) com nome truncado pelo console: não conferido"; continue }
            $s = Get-TagSaneado $lb.Nome $lb.Id
            $achados = @($tags | Where-Object { $_ -ieq $s -or $_ -ieq "$s-$($lb.Id)" -or $_ -like "*-$($lb.Id)" })
            Ok ($achados.Count -gt 0 -or $semCommit -gt 0) "$($alvo.Projeto): label '$($lb.Nome)' -> tag '$s'"
            if ($achados.Count -gt 0) {
                # alvo: o commit da revisão rotulada mais recente ('(rev N)' na mensagem da tag e na do commit)
                $msg = Invoke-Git $alvo.Repo @('tag', '-l', '--format=%(contents)', $achados[0])
                $revs = @([regex]::Matches($msg.Saida, '\(rev (\d+)\)') | ForEach-Object { [int]$_.Groups[1].Value })
                if ($revs.Count -gt 0) {
                    $max = ($revs | Measure-Object -Maximum).Maximum
                    $cm = Invoke-Git $alvo.Repo @('log', '-1', '--format=%B', "refs/tags/$($achados[0])^{commit}")
                    Ok ($cm.Saida -match "\(rev $max\)") "tag '$($achados[0])' aponta para o commit da revisão $max"
                } else { Info "tag '$($achados[0])' sem '(rev N)' na mensagem: alvo não conferido" }
            }
        }
        $tn = Invoke-Git $alvo.Repo @('tag', '-n')
        Ok ($tn.Codigo -eq 0) "$($alvo.Projeto): git tag -n sem erro"
    }
}

# ---------------------------------------------------------------- 7. -nogit
Write-Output '==== 7. -nogit + git fast-import manual'
if (-not $podeGit) { Pular 'caso 7: exportação ou git indisponível' }
else {
    $out7 = Join-Path $Saida 'nogit'
    $r7 = Invoke-J2G (@($Con) + @('-project', $Projeto, '-out', $out7, '-nogit', '-json'))
    Ok (Test-ExportOk $r7) "exportação -nogit sai 0 ou 11 (código $($r7.Codigo))"
    $rep7 = Get-RepoDir $r7.Json
    $fi = "$rep7.fast-import"
    Ok (Test-Path -LiteralPath $fi) "$([IO.Path]::GetFileName($fi)) gerado"
    Ok (-not (Test-Path -LiteralPath (Join-Path $rep7 '.git'))) '-nogit não cria o repositório'
    Ok (Test-Path -LiteralPath (Join-Path $out7 '.jvcs2git-cache')) '-nogit preserva o cache'
    if (Test-Path -LiteralPath $fi) {
        $lin = [IO.File]::ReadAllLines($fi)
        Ok ($lin.Count -gt 1 -and $lin[0] -eq 'feature done') "primeira linha do stream = 'feature done'"
        $ult = @($lin | Where-Object { $_ -ne '' })[-1]
        Ok ($ult -eq 'done') "última linha do stream = 'done'"
        $vazio = Join-Path $Saida 'manual'
        $i = Invoke-Git '' @('init', '-q', $vazio)
        $f = Invoke-Git $vazio @('fast-import', '--quiet') -EntradaArquivo $fi
        Ok ($i.Codigo -eq 0 -and $f.Codigo -eq 0) "git fast-import < arquivo num repo vazio retorna 0"
        $c = Invoke-Git $vazio @('rev-list', '--count', 'main')
        $c2 = Invoke-Git $Repo2 @('rev-list', '--count', 'main')
        Ok ($c.Codigo -eq 0) "branch main importada ($($c.Saida.Trim()) commits; -nogroup: $($c2.Saida.Trim()))"
    }
}

# ---------------------------------------------------------------- 9. retomada / cache / -force
Write-Output '==== 9. retomada, cache e -force'
if (-not $podeGit) { Pular 'caso 9: exportação ou git indisponível' }
else {
    $out9 = Join-Path $Saida 'cache'
    $cache = Join-Path $out9 '.jvcs2git-cache'
    $a = Invoke-J2G (@($Con) + @('-project', $Projeto, '-out', $out9, '-nogit', '-keepcache', '-json'))
    Ok (Test-ExportOk $a) "1ª rodada -nogit -keepcache (código $($a.Codigo))"
    $Ja = @($a.Json.projects)[0]
    $total = [int]$Ja.blobsDownloaded + [int]$Ja.blobsFromCache
    Ok ((Test-Path -LiteralPath $cache) -and $total -gt 0) "cache preenchido ($total blob(s))"
    # membros baixados mas recusados (cifrados sem chave, CRC errado) não entram no cache: são baixados de novo
    $falhosA = @(@($Ja.skipped) | Where-Object { $_.reason -eq 'encrypted' -or $_.reason -eq 'crcMismatch' }).Count
    $b = Invoke-J2G (@($Con) + @('-project', $Projeto, '-out', $out9, '-force', '-keepcache', '-json'))
    $Jb = @($b.Json.projects)[0]
    Ok ((Test-ExportOk $b) -and [int]$Jb.blobsDownloaded -eq $falhosA -and [int]$Jb.blobsFromCache -eq ($total - $falhosA)) "2ª rodada reaproveita o cache: blobsDownloaded = $($Jb.blobsDownloaded), blobsFromCache = $($Jb.blobsFromCache) (esperado $falhosA recusado(s) e $($total - $falhosA))"
    $c = Invoke-J2G (@($Con) + @('-project', $Projeto, '-out', $out9, '-json'))
    Ok ($c.Codigo -eq 12) 'pasta do repositório já existe, sem -force: sai 12'
    # corrompe dois arquivos do cache: um vira .tmp, outro fica com tamanho errado
    # (só blobs: <RevisionID><ext>.zipname guarda a grafia do item do ZIP e não é conferido por tamanho)
    $arqs = @(Get-ChildItem -LiteralPath $cache -File | Where-Object { $_.Extension -ne '.tmp' -and $_.Extension -ne '.zipname' -and $_.Length -gt 1 } | Sort-Object Name)
    if ($arqs.Count -ge 2) {
        Rename-Item -LiteralPath $arqs[0].FullName -NewName ($arqs[0].Name + '.tmp')
        $fs = [IO.File]::Open($arqs[1].FullName, 'Open', 'ReadWrite'); $fs.SetLength($fs.Length - 1); $fs.Close()
        $d = Invoke-J2G (@($Con) + @('-project', $Projeto, '-out', $out9, '-force', '-json'))
        $Jd = @($d.Json.projects)[0]
        Ok ((Test-ExportOk $d) -and [int]$Jd.blobsDownloaded -eq (2 + $falhosA)) "cache com .tmp e com tamanho errado: os 2 blobs baixados de novo (blobsDownloaded = $($Jd.blobsDownloaded); esperado 2 + $falhosA recusado(s))"
        $temCache9 = Test-Path -LiteralPath $cache
        if ($d.Codigo -eq 0) { Ok (-not $temCache9) 'cache apagado no fim (sem -keepcache, código 0)' }
        else { Ok $temCache9 'cache preservado no fim (código 11: há pulados)' }
        $rd = Invoke-Git (Get-RepoDir $d.Json) @('rev-list', '--count', 'main')
        Ok ($rd.Codigo -eq 0) "repositório recriado com -force ($($rd.Saida.Trim()) commits)"
    } else { Pular 'cache com menos de 2 blobs: corrupção não testada' }
    # -force numa pasta que não foi gerada pelo jvcs2git
    $alheio = Join-Path $Saida 'alheio'
    $nomeRepo = Split-Path -Leaf (Get-RepoDir $a.Json)
    $pAlheia = Join-Path $alheio $nomeRepo
    New-Item -ItemType Directory -Force $pAlheia | Out-Null
    $sent = Join-Path $pAlheia 'nao-apagar.txt'; [IO.File]::WriteAllText($sent, "x`r`n")
    $e = Invoke-J2G (@($Con) + @('-project', $Projeto, '-out', $alheio, '-force', '-json'))
    Ok ($e.Codigo -eq 12) '-force numa pasta que não é do jvcs2git: sai 12'
    Ok (Test-Path -LiteralPath $sent) '... e não apaga nada'
}

# ---------------------------------------------------------------- 8 (fim). sem git no PATH
Write-Output '==== 8. sem git no PATH'
if (-not $exportOk) { Pular 'sem git no PATH: exportação indisponível' }
else {
    # [IO.File]::Exists em vez de Join-Path/Test-Path: o PATH pode ter unidades que não existem (Join-Path falha)
    function Test-TemGit([string]$d) {
        foreach ($n in @('git.exe', 'git.cmd')) { try { if ([IO.File]::Exists([IO.Path]::Combine($d, $n))) { return $true } } catch { } }
        return $false
    }
    $semGit = (@($env:PATH -split ';' | Where-Object { $_ -and -not (Test-TemGit $_) }) -join ';')
    $r = Invoke-J2G -Argumentos (@($Con) + @('-project', $Projeto, '-out', (Join-Path $Saida 'semgit'), '-json')) -Ambiente @{ PATH = $semGit }
    Ok ($r.Codigo -eq 12) "sem git no PATH: sai 12 (código $($r.Codigo))"
}

Write-Output "==== OK: $okN  FALHOU: $falhas  PULADO: $pulados"
if ($falhas -gt 0) { exit 1 } else { exit 0 }
