# Usage

[Index](README.md) · [Português](../pt/Uso.md)

## Syntax

```
(a) jvcs2git-cli -identity <name> [<host[:port]>] [-user <u>] -out <folder> (-project <name|id> ... | -all) [options]
(b) jvcs2git-cli <host[:port]> -user <u> -out <folder> (-project <name|id> ... | -all) [options]
    jvcs2git-cli ... -list [-include-deleted] [-json]             list the projects and exit
    jvcs2git-cli ... -dryrun (-project ... | -all) [-out <folder>] metadata only: print the commit plan
    jvcs2git-cli -selftest paths|blob [-json]                      offline self tests
    jvcs2git-cli -help
```

`-project` can be repeated or take a comma separated list; it accepts the name (`exemplo01.dpr`) or the ID.
The default port is 2106.

## Password and identity

Precedence: **`-identity` > redirected stdin > prompt**. There is no `-password` (exit code 2).

- **Form (a), recommended:** host, port, user and password come from the identity saved by the JEDI VCS
  client (Server Login → *Store Password with identity*). With `-identity` stdin is **never** read. A host or
  user also given on the command line overrides it and adds a warning to `warnings`. Missing or incomplete
  identity, or no saved password → exit code 4, without trying to log in.
- **Form (b):** the password is the first line of stdin when it is redirected; EOF or an empty line → exit code
  4 without trying to log in. On an interactive console a prompt without echo is shown.

With `-identity`, jvcs2git takes the same mutex as the JEDI VCS AI wrapper (`jvcs-ai.ps1`) and waits up to
30 s; if the wrapper is busy it exits with 12. This way an AI hook cannot drop the export halfway.

## Blowfish key (encrypted revisions)

The key is as sensitive as the password: it never goes to the command line, log, JSON or report.

| Source | How |
|---|---|
| Client registry (default) | the key saved by the JEDI VCS client in Properties → Crypt |
| `-encodekey-file <file>` | Base64 on the 1st line; the file **must not** be inside `-out` (exit code 2) |
| `-encodekey-stdin` | Base64 on a stdin line (after the password in form (b); 1st line with `-identity`) |
| `-noencodekey` | ignore the registry key |

`-encodekey <base64>` does not exist (exit code 2). An invalid key (not Base64, or outside 8 to 65 bytes) gives a
warning and encrypted revisions stay `encrypted`.

## Options

| Option | Effect |
|---|---|
| `-out <folder>` | output folder (required for the export) |
| `-branch <branch>` | JEDI VCS branch (default `HEAD`) |
| `-branch-name <name>` | Git branch (default `main`; checked with `git check-ref-format`) |
| `-group <min>` / `-nogroup` | group check-ins of the same user and comment (default 10 min) / one commit per revision |
| `-group-maxspan <h>` | max span of a group dated by file time (default 168 h = 7 days) |
| `-localtime` | dates with the local UTC offset (default `+0000`) |
| `-committer-date original` | committer = author (default: monotonic) |
| `-root <folder>` | server folder used as the repository root |
| `-nodfmtext` | keep binary `.dfm` as is (default: convert to text) |
| `-authors <file>` | author map (default `<out>\autores.txt`) |
| `-email-domain <dom>` | default e-mail domain (default `jedivcs.local`) |
| `-labels tag\|none` | labels as tags (default `tag`) |
| `-include-deleted` | also deleted (not purged) projects |
| `-skiphidden` | skip hidden modules |
| `-nolog` | do not read the server log (dates by file time) |
| `-noattributes` | no initial `.gitattributes` commit (`* -text`) |
| `-nogit` | only write `<out>\<repo>.fast-import` |
| `-keepcache` | keep `<out>\.jvcs2git-cache` |
| `-force` | recreate `<out>\<repo>` if it was made by jvcs2git |
| `-ignorecrc` | export blobs with a CRC mismatch |
| `-strictcase` | abort the project on case collisions |
| `-blobtimeout <ms>` | timeout of blob and log requests (default 120000) |
| `-log <file>` | log file (default `<out>\jvcs2git.log`) |
| `-json` | one JSON line on stdout; messages go to stderr |
| `-quiet` | no messages on the screen (log and JSON still written) |

## Generated files

| Path | Contents |
|---|---|
| `<out>\<repo>\` | Git repository; `<repo>` = project name without extension, sanitized |
| `<out>\<repo>.fast-import` | stream (rewritten on each run) |
| `<out>\.jvcs2git-cache\` | downloaded blobs; deleted only when the export ends with exit code 0, unless `-keepcache`/`-nogit` |
| `<out>\jvcs2git.log` | log; each run appends a header with date and time |
| `<out>\jvcs2git-relatorio.md` | report (rewritten) |
| `<out>\autores.txt` | author map, created on the 1st run (`-dryrun` or export) |

`autores.txt` has one line per login: `login=Full Name <email@company>`. Logins still with the default e-mail
(`login@jedivcs.local`) are listed in `unmappedAuthors`.

## JSON (`-json`)

One line, ASCII only (`\uXXXX`). Export example:

```json
{"ok":false,"command":"export","exitCode":11,"message":"1 project(s), 0 failed, 1 skipped member(s)",
 "log":"D:/git/jvcs2git.log","report":"D:/git/jvcs2git-relatorio.md",
 "authorsFile":"D:/git/autores.txt","unmappedAuthors":["john"],
 "projects":[{"id":1,"name":"exemplo01.dpr","ok":false,"exitCode":11,"repo":"D:/git/exemplo01",
   "modules":4,"revisions":30,"commits":12,"tags":1,"blobsDownloaded":55,"blobsFromCache":0,
   "bytesDownloaded":812345,"seconds":14.2,"dfmConverted":20,"dfmConvertFailed":0,
   "commitsDateFromLog":12,"commitsDateFromFile":0,"datesSubstituted":0,
   "skipped":[{"revisionId":55,"module":"x.pas","ext":".dfm","reason":"encrypted"}],"warnings":[]}]}
```

(Wrapped here for reading only.) `ok` is true only when `exitCode` is 0. Top-level fields: `ok`, `command`
(`export`, `list`, `dryrun`, `selftest`), `exitCode`, `message`, `warnings[]` (only when present), `log`,
`report`, `authorsFile` + `unmappedAuthors[]`, `projects[]`. With `-list`, `projects[]` holds
`{id, name, deleted}`.

`skipped[].reason` values: `encrypted`, `crcMismatch`, `noBlob`, `noMembers`, `noCommit`, `dfmNotConverted`,
`error`. `skipped[]` is per member: a revision with the `.pas` stored and the `.dfm` skipped still makes a commit.

Streams: with `-json` stdout holds **only** the JSON line; progress and messages go to stderr and to the log. A
usage error prints the help on stderr and still emits the JSON with `exitCode` 2.

## Exit codes

| Code | Meaning |
|---|---|
| 0 | ok |
| 2 | usage: unknown option, `-password`/`-encodekey`, `-project` with `-all`, missing `-out`, `-encodekey-file` inside `-out`, invalid `-branch-name` |
| 4 | credential: identity missing/incomplete/without password, login refused, no password on stdin |
| 5 | project or JEDI VCS branch not found |
| 9 | server/connection: server down, session dropped, failure after reconnecting |
| 11 | partial: members skipped, or a project failed with `-all` |
| 12 | environment: Git missing, `fvcscrypt.dll` missing, folder not writable, repository folder already exists, wrapper mutex busy, `git` failure |

Each project in `projects[]` has its own `ok` and `exitCode`.

## Recommended flow

1. `jvcs2git-cli -identity DEFAULT -list -json < NUL`
2. `jvcs2git-cli -identity DEFAULT -project exemplo01.dpr -out D:\git -dryrun -json < NUL`
3. Fill in `D:\git\autores.txt`.
4. `jvcs2git-cli -identity DEFAULT -project exemplo01.dpr -out D:\git -json < NUL`
5. `git -C D:\git\exemplo01 log --stat`, `git -C D:\git\exemplo01 tag -n`, read `D:\git\jvcs2git-relatorio.md`.
