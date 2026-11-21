# Security Policy

## Supported versions

Only the [latest release](https://github.com/Jnooo-cloud/fokus/releases/latest) gets security fixes. Fokus updates itself, so installed copies move to the newest version on their own.

## Reporting a vulnerability

Please don't open a public issue for a security problem.

Use GitHub's private reporting instead: open the [Security tab](https://github.com/Jnooo-cloud/fokus/security) of this repo and click **Report a vulnerability**. Only the maintainer sees the report.

Include what you found, how to reproduce it, and the Fokus and macOS version. Fokus is maintained by one person, so expect a first reply within 7 days. If the report holds up, the fix ships as a normal release and the report is credited to you, unless you'd rather stay unnamed.

## What Fokus does on your Mac

Knowing this helps to judge what counts as a vulnerability.

- It reads the active tab's address in Chrome, Safari and Edge through AppleScript, with the permission macOS asks you for. It never reads page content.
- It stores seconds per app and per domain in `~/Library/Application Support/Fokus/`. Page titles only if you turn them on.
- Its only network request is the update check against this repo's GitHub releases. An update is installed only if its signature matches the public key built into the app.
- The MCP server (`fokus-mcp`) is read-only and talks over stdio. It opens no network port.
- Release builds are ad-hoc signed and not notarized yet.

Things that are in scope: an update that installs without a valid signature, any way to make Fokus send data off the machine, reading Fokus data from another user account, or the MCP server changing data.

Out of scope: getting around a block as the Mac's admin. Fokus adds friction, it is not a security boundary.
