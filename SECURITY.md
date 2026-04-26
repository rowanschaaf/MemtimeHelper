# Security Policy

MemtimeHelper is a personal-scale macOS tool maintained by a single author. There are no SLAs, but security reports are taken seriously and acknowledged as quickly as practical.

## Reporting a Vulnerability

Please **do not** open a public issue for security problems.

Use GitHub's private vulnerability reporting:

1. Go to [Security → Report a vulnerability](https://github.com/rowanschaaf/MemtimeHelper/security/advisories/new)
2. Describe the issue, ideally with reproduction steps and the impact you see

If that is not workable, email **rowan@pattern.co.nz** with `[MemtimeHelper security]` in the subject.

You can expect:

- Acknowledgement within ~7 days
- An assessment and a fix plan (or a "won't fix" with reasoning) within ~30 days
- Credit in the release notes if you'd like

## Scope

In scope:

- The MemtimeHelper macOS app source in this repository
- Anything affecting the integrity of Memtime's local SQLite database via this app
- Misuse of macOS Accessibility permissions granted to the app

Out of scope:

- Vulnerabilities in Memtime, Claude, Outlook, or other monitored apps
- Issues that require physical access to an unlocked machine already running the app
- Findings that depend on the user disabling macOS protections (Gatekeeper, SIP, sandboxing of other apps)

## Threat Model — Quick Notes

For context when assessing reports:

- The app runs **unsandboxed** by design (see [CLAUDE.md](CLAUDE.md)). Sandboxing breaks the cross-process Accessibility API access that is the entire mechanism. Reports of "the app is unsandboxed" are not vulnerabilities.
- The app reads window/control titles from monitored apps via `AXUIElement` and writes only to Memtime's local SQLite database at `~/Library/Application Support/memtime/user/core.db`.
- It performs no network I/O. A finding that the app makes outbound connections **would** be a vulnerability.
- No credentials, tokens, or user data leave the machine.

## Supported Versions

Only the `main` branch is supported. There are no released binaries or version branches.
