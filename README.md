# jvcs2git — JEDI VCS to Git exporter

**English** · [Português (Brasil)](README.pt-BR.md)

**jvcs2git** migrates projects from **JEDI VCS 2.5** (the successor of **FreeVCS**) to **Git**, with the
full history: every revision, author, date and check-in comment, and JEDI VCS labels as Git tags. It talks to
the JEDI VCS application server with its own protocol (no database client needed: Firebird, MSSQL, Oracle or
MySQL archives work the same way) and builds the repositories with **`git fast-import`**: no working tree, no
`git add` loop, no case problems. Written in **Delphi** 13, on top of the JEDI VCS client units.

- One Git repository per JEDI VCS project (shared modules appear in each project that uses them).
- Check-ins of the same user with the same comment are grouped into one commit (`-group 10`, or `-nogroup`).
- Real check-in time from the server log; dates in UTC (or `-localtime`).
- Binary `.dfm` converted to text; family members (`.pas` + `.dfm`) in the same commit.
- Labels exported as annotated tags; author map `login=Name <email>`.
- Report of everything that was left out (encrypted revisions, CRC errors, missing blobs) in Markdown and JSON.
- Window for the archive administrator (`jvcs2git.exe`) and console for scripts and AI agents
  (`jvcs2git-cli.exe`, JSON output and exit codes), plus a [Claude Code skill](skills/en/jvcs2git/SKILL.md).

It only **reads** the JEDI VCS server: it never changes projects, modules or revisions and never checks
anything out.

## Requirements

- Windows; **Git 2.x on the PATH** (tested with 2.54; no specific version required).
- `fvcscrypt.dll` next to the executables (it comes in the zip).
- A JEDI VCS 2.5 server and a user with **Archive Admin** rights.
- Close the JEDI VCS window and do not run the AI wrapper (`jvcs-ai.ps1`) or its hooks during the export: on a
  server without branching a new login of the same user drops the previous session.

## Quick start

Save the login in the JEDI VCS client (Server Login → *Store Password with identity*) and use it with
`-identity` (the password is read from the saved identity, never from the command line):

```bat
jvcs2git-cli -identity DEFAULT -list -json < NUL
jvcs2git-cli -identity DEFAULT -project myapp.dpr -out D:\git -dryrun -json < NUL
rem  fill in D:\git\autores.txt  (login=Full Name <email>)
jvcs2git-cli -identity DEFAULT -project myapp.dpr -out D:\git -json < NUL
```

Without a saved identity: `jvcs2git-cli myserver:2106 -user admin -project myapp.dpr -out D:\git` asks for the
password (no echo) or reads it from the first line of a redirected stdin. There is no `-password` option.

Output in `<out>`:

| Path | Contents |
|---|---|
| `<out>\<repo>\` | the Git repository (branch `main`) |
| `<out>\<repo>.fast-import` | the `git fast-import` stream |
| `<out>\.jvcs2git-cache\` | downloaded blobs (resume after a drop; deleted at the end unless `-keepcache`/`-nogit`) |
| `<out>\jvcs2git.log` | log (appended on each run) |
| `<out>\jvcs2git-relatorio.md` | report: counts, skipped members, warnings |
| `<out>\autores.txt` | author map `login=Name <email>` |

## Recommended flow

1. `-list -json`: find the exact project name or ID.
2. `-dryrun`: commit plan without downloading contents; creates `autores.txt` and lists `unmappedAuthors`.
3. Fill in `autores.txt`. **Git cannot fix authors later without rewriting the history.**
4. Export.
5. Validate: `git log --stat`, `git tag -n`, `jvcs2git-relatorio.md` (skipped members, substituted dates,
   warnings) and a build of the project from the checkout. Keep the JEDI VCS backup.

## Exit codes

| Code | Meaning |
|---|---|
| 0 | ok |
| 2 | usage error |
| 4 | credential (identity missing or without password, login refused, no password on stdin) |
| 5 | project (or JEDI VCS branch) not found |
| 9 | server/connection (server down, session dropped by another login) |
| 11 | partial: members skipped, or a project failed with `-all` |
| 12 | environment: Git missing, `fvcscrypt.dll` missing, folder not writable, repository folder already exists, AI wrapper mutex busy |

With `-json` stdout has only one JSON line (`ok`, `command`, `exitCode`, `message`, `projects[]` with
`skipped[]` and `warnings[]`, ...); messages go to stderr. See [doc/en/Usage.md](doc/en/Usage.md).

## Limitations

- **Renamed or moved modules:** the server keeps only the current name and folder; the whole history uses the
  current path.
- **Modules removed from the project** do not appear (the server does not list them for the project).
- **Branches:** only the selected JEDI VCS branch (`HEAD` by default) is exported.
- **Dates:** the server keeps the real check-in time only in its log; without the log (`-nolog`, log disabled)
  the commit date is the file time on the workstation. Invalid dates (zero, before 1980, future) are replaced and
  listed in the report; the committer date is monotonic so `git log --since` works.
- **Labels:** a label marks one revision per module; the tag points to the commit with the most recent of them
  ("approximate tag" in the report when the state differs).
- **Case:** the file name spelling is fixed per module (from the most recent revision); folders come in lower
  case; modules that differ only by case are renamed and reported.
- **Encrypted revisions** need the Blowfish key (client registry or `-encodekey-file`); without it they are
  skipped and reported.
- **Contents** are copied byte by byte; only names and comments are converted from cp1252 to UTF-8.

More in [doc/en/Limitations.md](doc/en/Limitations.md).

## How it works

For each project: read modules, revisions, per-module history, labels and the server log (read-only requests
`GET_*`, never a checkout); sort revisions by revision ID; group them into commits; download each member with
`GET_SINGLE_BLOB` (unzip or decrypt, check the CRC, convert binary `.dfm`, cache on disk); write a
`git fast-import` stream; then `git init`, `git fast-import` and `git checkout`. Details in
[doc/en/How-it-works.md](doc/en/How-it-works.md).

## Building

Delphi 13 (Win32) with JCL, ICS 9 and Abbrevia from GetIt. The JEDI VCS units come from the submodule
`external/JEDI_VCS`, pinned at tag `v2.5.0.2026-beta6-build2063` (`65908e1`):

```bat
git clone --recurse-submodules https://github.com/edmarfrazao/jvcs2git
cd jvcs2git
tools\compilar.bat            rem all Release -> bin\Win32\jvcs2git.exe, jvcs2git-cli.exe, fvcscrypt.dll
tools\compilar.bat cli Debug
```

The `.dproj` files in `src\` open in the IDE (`tools\msbuild\jvcs2git.props`). `JVCS_ROOT` may point to a local
JEDI VCS checkout **for development only**, at the same tag as the submodule. See
[doc/pt/Como-compilar.md](doc/pt/Como-compilar.md) (Portuguese) and [doc/en/Building.md](doc/en/Building.md).

Tests against a **test** server: `tests\executar.bat` ([tests/teste-jvcs2git.ps1](tests/teste-jvcs2git.ps1)).

## Prior work

Two earlier exporters (2018, unmaintained) were studied:

- [DGH2112/JEDIVCSToGit](https://github.com/DGH2112/JEDIVCSToGit) by David Hoyle — reads the database with
  FireDAC/MSSQL and commits each revision with `git add` + `git commit --date`.
- [hbannw/JcvsToGit](https://github.com/hbannw/JcvsToGit) — FreeVCS/DBISAM era; generates a `git fast-import`
  stream, groups check-ins by day and user and converts binary `.dfm`.

jvcs2git keeps their good ideas (fast-import, grouping, author map, `.dfm` as text) and adds server-protocol
access (any database), UTC dates from the server log, labels as tags, a report of what was left out, resume, and
a CLI for automation and AI.

## License

Code in this repository: [Mozilla Public License 1.1](LICENSE). The executables also contain MPL 1.1 units from
JEDI VCS (submodule `external/JEDI_VCS`, see
[external/JEDI_VCS/doc/original/license.txt](external/JEDI_VCS/doc/original/license.txt)) and MidWare by
François Piette (freeware for non-commercial use only; modified version).

This product is based on MidWare. Freeware source code is available at http://www.overbyte.be.

## Disclaimer

jvcs2git is provided **"as is"**, without warranty of any kind. Back up the JEDI VCS server and validate every
generated repository before retiring the archive. See [DISCLAIMER.md](DISCLAIMER.md).
