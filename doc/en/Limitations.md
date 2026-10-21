# Limitations

[Index](README.md) · [Português](../pt/Limitacoes.md)

- **Git 2.x on the PATH** (tested with 2.54; no specific version required). `fvcscrypt.dll` next to the executables.
- **Single session:** on a server without branching, a new login of the same user drops the previous session —
  including the JEDI VCS window, the IDE, the `jvcs-ai.ps1` wrapper and its hooks. Use a dedicated admin user or
  close everything. jvcs2git detects the drop, keeps the cache and exits with 9; run again with the same `-out`.
- **Renamed or moved modules:** the server keeps only the current name and folder; the whole history uses the
  current path.
- **Modules removed from the project** do not appear (the server does not list them for the project). A deleted
  but not purged project can still be exported with `-include-deleted`.
- **Branches:** only the selected JEDI VCS branch (`-branch`, default `HEAD`).
- **Dates:** the real time comes from the server log by heuristic (user + comment, no revision ID). Without the
  log, the date is the file time on the workstation. Invalid dates are replaced and listed; the committer date is
  monotonic.
- **Labels:** a label marks one revision per module; the tag points to the commit containing the most recent
  one ("approximate tag" when not all labelled revisions are in that state).
- **Case:** spelling fixed per module by the most recent revision (case-only renames are not kept); folders in
  lower case; collisions between modules are renamed (`-<ModuleID>`) and reported.
- **Paths invalid for Git for Windows** (drive `:`, UNC, reserved names, trailing dot/space) are normalized and
  reported. Paths longer than 255 characters were already truncated by the server.
- **Members:** a member no longer sent in a check-in is deleted in that commit; a member skipped by an error
  keeps the previous content and goes to the report.
- **Encrypted revisions** need the Blowfish key; without it they stay `encrypted`.
- **Contents** are copied without re-encoding; only names and comments go from cp1252 to UTF-8. Binary `.dfm`
  becomes text (unless `-nodfmtext`).
- **Timeouts:** 12 s per request; blobs and the log use `-blobtimeout` (default 120 s). On huge archives
  `-nolog` is the emergency exit.
- **One shot:** authors and dates cannot be fixed later without rewriting the history. Fill in `autores.txt`
  before the real export.
