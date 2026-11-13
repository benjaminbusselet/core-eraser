# Security policy

## Reporting a vulnerability

Please **do not open a public issue** for a security problem.
Use GitHub's private reporting instead: **Security** tab > **Report a vulnerability**.
You will get an answer as soon as possible; a fix is released before details are made public.

## Supported versions

Only the latest release receives security fixes.

## Design principles

core-eraser deletes files, so it is built to fail safe:

- It runs with your normal user rights and **never runs `sudo` itself**. Commands needing administrator rights are printed, with every path quoted (`printf %q`) so that a crafted file name cannot run code when pasted.
- Files are moved to the **Trash** rather than deleted, except caches and logs. Moving to the Trash is refused outside your home folder and `/Applications`, and for any item on the exclusion list.
- Values inserted into AppleScript (app identifiers) are restricted to letters, digits, dots and hyphens.
- Data read from the internet (Sparkle update feeds) is fetched over HTTPS only, and version strings are filtered to safe characters.
- No `eval`, no `source` of external files, no downloaded code.

## Scope

In scope: anything that could make core-eraser delete, move or expose something the user did not choose, or run unintended code.
