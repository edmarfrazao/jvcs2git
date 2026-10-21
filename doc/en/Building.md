# Building

[Index](README.md) · [Português](../pt/Como-compilar.md)

## Requirements

- RAD Studio / Delphi 13 (Win32).
- From GetIt: **JCL**, **ICS 9** (Overbyte) and **Abbrevia**.
- Git, for the submodule.

## Sources

```bat
git clone --recurse-submodules https://github.com/edmarfrazao/jvcs2git
rem or, in an existing clone:
git submodule update --init
```

The `external\JEDI_VCS` submodule brings the JEDI VCS client units (connection, requests, ZIP, Blowfish, CRC,
time zone), MidWare and `fvcscrypt.dll`. It is pinned at tag `v2.5.0.2026-beta6-build2063` (commit `65908e1`).

## Command line

```bat
tools\compilar.bat                 rem both executables, Release
tools\compilar.bat cli Release     rem jvcs2git-cli.exe only
tools\compilar.bat gui Debug       rem jvcs2git.exe only, Debug
tools\compilar.bat /info           rem show Delphi, libraries and paths without building
```

- Output: `bin\Win32\jvcs2git.exe`, `bin\Win32\jvcs2git-cli.exe` and `bin\Win32\fvcscrypt.dll`.
- DCUs in `dcu\Win32\<config>\<target>`; logs in `tools\logs`.
- Delphi and the GetIt libraries are found by the JEDI VCS `tools\versao-delphi.bat` + `versoes.ini` (default
  RAD Studio folder or `BDSROOT`; `JVCS_CATALOG` changes the CatalogRepository).
- `J2G_OUTDIR` and `J2G_DCUDIR` (optional) change the output folders, for parallel builds.
- The `.res` (version and manifest) is built with `brcc32` from `src\jvcs2git.rc` and `src\jvcs2git-cli.rc`.

## IDE

Open `src\jvcs2git.dproj` or `src\jvcs2git-cli.dproj`. Both import `tools\msbuild\jvcs2git.props`, which imports
`JediVCS2026.props` from the submodule. Output in `bin\Win32\<config>`.

## `JVCS_ROOT` (development only)

When `JVCS_ROOT` is set, the build uses the units in that folder instead of the submodule. Use it for local
development only, pointing to a JEDI VCS checkout **at the same tag** as the submodule; `compilar.bat` shows
which root it used. Releases are always built from the submodule.

## Tests

```bat
tools\compilar.bat cli Release
tests\executar.bat -Identidade DEFAULT
```

The test ([`tests/teste-jvcs2git.ps1`](../../tests/teste-jvcs2git.ps1)) runs against a **test** JEDI VCS server
with the given identity (default `DEFAULT`; the server comes from the identity or from `-Servidor`). The cases
that compare with the JEDI VCS console need the 2026 `jvcs.exe` (`-Console`, or
`%JVCS_ROOT%\bin\client\Win32\jvcs.exe`, or `%ProgramFiles(x86)%\JEDI\JVCS 2026\jvcs.exe`); without it those
cases are `[PULADO]` (skipped). Output: `[OK]`/`[FALHOU]`/`[PULADO]` lines and exit code 0 only if nothing failed.

## File encoding

`.gitattributes` = `* -text` (exact bytes). Delphi sources and `.bat` in ANSI 1252 with CRLF; `.ps1` in UTF-8
with BOM and CRLF; `.md` in UTF-8 without BOM and CRLF.
