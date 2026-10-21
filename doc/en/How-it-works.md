# How it works

[Index](README.md) · [Português](../pt/Como-funciona.md)

## Protocol

jvcs2git uses the same request classes as the JEDI VCS client (`TJVCSConnection` and the `TJVCSGet*` objects)
and sends read-only requests only. Per project:

| Request | Purpose |
|---|---|
| `GET_PROJECT_LIST` | projects (name, ID, deleted) |
| `GET_PROJECT_MODULE_LIST` | modules: current name and folder (hidden included unless `-skiphidden`) |
| `GET_REVISION_LIST` | project revisions: only `ModuleID`, `RevisionID`, version, revision, hidden |
| `GET_MODULE_HISTORY` | per module: one row per member; user, comment and file time |
| `GET_LABELS`, `GET_LABELS_BY_PROJECT` | labels and the revisions they mark |
| `GET_LOG_ENTRIES`, `GET_LOG_COMMENT` | server log (real check-in time) |
| `GET_USERS` | logins for the author map |
| `GET_SINGLE_BLOB` | content of each member (does not write to the server log) |

`GET_CHECKOUT_MODULE` is never used: it writes a server log entry.

## Dates and log

For each revision the server keeps only the **file** time on the workstation of whoever checked it in
(`ORIGTIME`), which can be days before the check-in. The real time is in the server log, which has no revision
ID: jvcs2git links each log entry to a revision by user + comment, from newest to oldest.

Date of a revision: the first valid one among log time, file time (latest among the members), module date (last
revision only), previous commit date + 1 s and now. Valid = from 1980-01-01 to now + 1 day. A substituted date is
noted in the commit message and in the report (`datesSubstituted`).

- **author date** = revision date (UTC `+0000`, or the local offset with `-localtime`);
- **committer date** = monotonic (never goes back), so `git log --since/--until` works;
  `-committer-date original` makes committer = author.

The report counts commits dated by the log and by file time (`commitsDateFromLog`, `commitsDateFromFile`).

## Grouping

Revisions are sorted by **revision ID** (increasing server generator), never by date. Consecutive revisions
become one commit when they have the same user, the same comment, the module is not yet in the group, and:

- both dated by the log: at most `-group` minutes apart (default 10);
- any of them dated by file time: they are adjacent in the project list, with at most `-group-maxspan` hours
  (default 168 = 7 days) between the oldest and the newest.

Commit date = the latest of the group. `-nogroup` makes one commit per revision.

Commit message: the check-in comment (or a placeholder when empty), plus the line
`JEDI VCS: <project>; <module> <version.revision> (rev <id>)[, ...]`.

## Paths

- Root: `-root`, or the folder of the module named like the project (`.dpr`), or the common prefix of the folders.
- Outside the root: `_externos/<letter>/<rest>` (no `:`) or `_externos/unc/<server>/<share>/<rest>`.
- Components invalid on Windows (`< > : " | ? *`, reserved names such as `nul`, trailing dot or space) are fixed
  and reported.
- File name spelling: one per module, from the ZIP item of the most recent revision (accepted only if equal to
  the server name ignoring case); folders in lower case. Case collision between modules → `-<ModuleID>` suffix and
  a warning (`-strictcase` aborts the project).

## Contents

`GET_SINGLE_BLOB` returns the file compressed (ZIP) or encrypted (Blowfish). jvcs2git unzips or decrypts it,
checks the CRC32 **before** any conversion, and:

- binary `.dfm`/`.fmx` (`TPF0`) → text with `ObjectBinaryToText` (unless `-nodfmtext`); on failure the binary
  is kept and counted in `dfmConvertFailed`;
- CRC mismatch → skipped (`crcMismatch`) unless `-ignorecrc`;
- blob missing on the server → `noBlob` (a 0-byte file is valid and is written empty); encrypted without key → `encrypted`.

A member that disappears in a revision (e.g. the unit lost its `.dfm`) is deleted in that commit. A member
skipped by an error keeps its previous content.

## git fast-import

The stream starts with `feature done` and ends with `done` (a truncated stream is rejected). Initial commit with
`.gitattributes` = `* -text` (exact bytes; `-noattributes` turns it off), 1 s before the first revision. Then:

```
git init -q <repo>
git -C <repo> symbolic-ref HEAD refs/heads/main
git -C <repo> fast-import --quiet --export-marks=.git/jvcs2git.marks < <repo>.fast-import
git -C <repo> checkout -q main
```

No `git init -b`: it works with any Git 2.x and ignores the machine's `init.defaultBranch`. The Git version is
written to the log.

## Tags

Each label with revisions in the project becomes an annotated tag on the commit containing the most recent
labelled revision (tagger = author of that commit; message = label description + modules and versions). Names
are sanitized with the `git check-ref-format` rules; a collision (ignoring case) gets `-<LabelID>`. If the
labelled revision was skipped, the tag goes to the closest earlier commit ("approximate tag"); without any commit
the tag is not created (`noCommit`).

## Cache and resume

Each downloaded blob is written to `<out>\.jvcs2git-cache\<RevisionID><ext>.tmp` and renamed only after the CRC
check. On resume, a cache file is accepted only if it is not `.tmp` and its size matches the history; otherwise
it is downloaded again. The JSON shows `blobsDownloaded` and `blobsFromCache`.

The cache is deleted only when the export ends with exit code 0; with `-nogit`, `-keepcache`, skipped revisions (11) or a failure it stays, so you can run again (for example after saving the Blowfish key). After a
drop (exit code 9), run again with the same `-out`.

## Existing folder and `-force`

If `<out>\<repo>` exists and is not empty, jvcs2git exits with 12 and deletes nothing. With `-force` it deletes
and recreates the folder **only** if it contains `.git\jvcs2git.marks` (a repository made by jvcs2git itself);
otherwise it is still 12. `<repo>.fast-import` and the report are rewritten; the log is appended.
