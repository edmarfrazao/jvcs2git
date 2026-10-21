# Como compilar

[Índice](README.md) · [English](../en/Building.md)

## Requisitos

- RAD Studio / Delphi 13 (Win32).
- Pelo GetIt: **JCL**, **ICS 9** (Overbyte) e **Abbrevia**.
- Git, para o submódulo.

## Fontes

```bat
git clone --recurse-submodules https://github.com/edmarfrazao/jvcs2git
rem ou, num clone já existente:
git submodule update --init
```

O submódulo `external\JEDI_VCS` traz as units do cliente JEDI VCS (conexão, requisições, ZIP, Blowfish, CRC,
fuso horário), o MidWare e a `fvcscrypt.dll`. Ele está fixado na tag `v2.5.0.2026-beta6-build2063`
(commit `65908e1`).

## Linha de comando

```bat
tools\compilar.bat                 rem os dois exes, Release
tools\compilar.bat cli Release     rem só jvcs2git-cli.exe
tools\compilar.bat gui Debug       rem só jvcs2git.exe, Debug
tools\compilar.bat /info           rem mostra Delphi, bibliotecas e caminhos sem compilar
```

- Saída: `bin\Win32\jvcs2git.exe`, `bin\Win32\jvcs2git-cli.exe` e `bin\Win32\fvcscrypt.dll`.
- DCUs em `dcu\Win32\<config>\<alvo>`; logs em `tools\logs`.
- O Delphi e as bibliotecas do GetIt são achados pelo `tools\versao-delphi.bat` + `versoes.ini` do JEDI VCS
  (pasta padrão do RAD Studio ou `BDSROOT`; `JVCS_CATALOG` muda o CatalogRepository).
- `J2G_OUTDIR` e `J2G_DCUDIR` (opcionais) mudam as pastas de saída, para builds em paralelo.
- O `.res` (versão e manifesto) é gerado com o `brcc32` a partir de `src\jvcs2git.rc` e `src\jvcs2git-cli.rc`.

## IDE

Abra `src\jvcs2git.dproj` ou `src\jvcs2git-cli.dproj`. Os dois importam `tools\msbuild\jvcs2git.props`, que
importa `JediVCS2026.props` do submódulo. Saída em `bin\Win32\<config>`.

## `JVCS_ROOT` (só desenvolvimento)

Se a variável `JVCS_ROOT` estiver definida, o build usa as units dessa pasta em vez do submódulo. Use só para
desenvolvimento local e aponte para um checkout do JEDI VCS **na mesma tag** do submódulo; o `compilar.bat`
mostra qual raiz usou. Releases são feitas sempre a partir do submódulo.

## Testes

```bat
tools\compilar.bat cli Release
tests\executar.bat -Identidade DEFAULT
```

O teste ([`tests/teste-jvcs2git.ps1`](../../tests/teste-jvcs2git.ps1)) roda contra um servidor JEDI VCS **de
teste**, com a identidade indicada (padrão `DEFAULT`; o servidor vem da identidade ou de `-Servidor`). Os
casos que comparam com o console do JEDI VCS precisam do `jvcs.exe` 2026 (`-Console`, ou
`%JVCS_ROOT%\bin\client\Win32\jvcs.exe`, ou `%ProgramFiles(x86)%\JEDI\JVCS 2026\jvcs.exe`); sem ele, esses casos
saem como `[PULADO]`. Resultado: linhas `[OK]`/`[FALHOU]`/`[PULADO]` e código 0 só se nada falhou.

## Codificação dos arquivos

`.gitattributes` = `* -text` (bytes exatos). Fontes Delphi e `.bat` em ANSI 1252 com CRLF; `.ps1` em UTF-8 com
BOM e CRLF; `.md` em UTF-8 sem BOM e CRLF.
