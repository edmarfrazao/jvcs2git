# AI (Claude Code skill)

[Index](README.md) · [Português](../pt/IA.md)

`jvcs2git-cli.exe` is designed to be called by AI agents: the password only through the saved identity, one
JSON line on stdout and stable exit codes. The `jvcs2git` skill teaches the flow to Claude Code.

## Installation

Copy the skill folder to the project's `.claude\skills\` (or to `%USERPROFILE%\.claude\skills\`):

- English: [`skills/en/jvcs2git`](../../skills/en/jvcs2git/SKILL.md)
- Portuguese: [`skills/pt/jvcs2git`](../../skills/pt/jvcs2git/SKILL.md)

Copy the whole folder, including `scripts\localizar-jvcs2git.ps1`.

## Finding the executable

The `scripts\localizar-jvcs2git.ps1` script (read only) returns `{ok, cli, gui, source, exitCode}` and searches,
in this order:

1. environment variable `JVCS2GIT_HOME` (folder of the executables or a root with `bin\Win32`);
2. `<project>\.claude\jvcs2git.managed.json` with `{"home": "<folder of the executables>"}` (or `"cli"`);
3. `bin\Win32` (or the extracted zip folder itself), from the current folder upwards.

Exit code 12 = not found.

## Rules enforced by the skill

- Always `-identity <name>` with an empty stdin (`< NUL`) and `-json`.
- Never ask for, receive, show or pass the password or the Blowfish key; never read the JEDI VCS registry.
- Flow: `-list` → `-dryrun` → fill in `autores.txt` with the administrator → export → validation.
- Never `-all` without the administrator confirming the folder; never delete the output folder; `-force` and
  `-ignorecrc` only with approval.
- Do not call the `jvcs-ai.ps1` wrapper or edit Delphi sources during the export (its hooks log in with the same
  identity).
- Action table per exit code (0, 2, 4, 5, 9, 11, 12) and per `skipped[]` reason.

## Example request

> Export the ex4ia.dpr project to D:\git and tell me what was left out.

The agent finds the executable, runs `-list` and `-dryrun`, shows the `unmappedAuthors` and asks for
`autores.txt` to be filled in, exports and summarizes `skipped[]`, `warnings` and the report.
