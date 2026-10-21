# FAQ

[Index](README.md) · [Português](../pt/FAQ.md)

**Do I need the database client (Firebird, MSSQL...)?**
No. jvcs2git talks to the JEDI VCS application server through its protocol, like the client.

**Does jvcs2git change anything on the server?**
No. It only sends read requests and never checks anything out.

**How do I give the password?**
Save the identity in the JEDI VCS client and use `-identity <name>`. Without an identity, the password comes from
the first line of a redirected stdin or from the prompt without echo. There is no `-password`.

**It exited with 4.**
Identity missing, no saved password, login refused or (`<host> -user` form) empty stdin. Save the identity with
*Store Password with identity*.

**It exited with 9 in the middle of the export.**
Another session of the same user logged in (JEDI VCS window, IDE, AI wrapper) or the server went down. Close
whatever is open and run again with the same `-out`: the blobs already downloaded come from the cache.

**It exited with 12 saying the folder already exists.**
`<out>\<repo>` already exists. Use another `-out`, or `-force` (which deletes only folders made by jvcs2git).

**It exited with 12 and "another jvcs-ai call ... is running".**
The AI wrapper is using the same identity. Wait for it to finish and do not call the wrapper during the export.

**Some revisions are `encrypted`.**
The archive uses Blowfish encryption. The administrator saves the key in the JEDI VCS client
(Properties → Crypt) or uses `-encodekey-file <file>` (outside the output folder), and runs again.

**Some revisions are `crcMismatch`.**
The content on the server does not match the stored CRC. Evaluate it; `-ignorecrc` stores it anyway.

**The commits have strange dates.**
Without the server log (disabled or `-nolog`) the date is the file time on the workstation. Check
`commitsDateFromFile` and `datesSubstituted` in the report.

**Authors came out as `login <login@jedivcs.local>`.**
`autores.txt` was not filled in. Run `-dryrun` first, fill in the file and export again with `-force`.

**Can I export only the `.fast-import`?**
Yes, with `-nogit`. Then: `git init -q repo`, `git -C repo fast-import < <repo>.fast-import`,
`git -C repo checkout -q main`.

**The Windows checkout reports colliding paths.**
It should not: jvcs2git fixes one spelling per module and renames collisions. If it happens, open an issue with
the report (without confidential data).
