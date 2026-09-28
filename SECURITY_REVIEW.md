# Security review

Reviewed version 1.1.0 on 2026-09-27. Scope: this plugin's source and installed files, sampler
process, configuration writes, and its use of the local Omarchy shell IPC.
This is a targeted code/runtime review, not an operating-system penetration
test or a source-level vulnerability audit of Python, Qt, Quickshell, or graphics
drivers. A separate dependency advisory check is recorded below.

No critical or high-severity issue was identified within this scope.

## Attack surface and checks

- **Network:** the plugin contains no listener, HTTP client, download, remote
  import, telemetry, or update mechanism. It reads network counters from
  procfs without sending traffic. The live sampler had no socket descriptors.
  The host shell may use networking for other plugins; that is outside this
  plugin's scope.
- **Execution:** one child process is launched with an argument array and the
  absolute `/usr/bin/python3` path. No shell interpreter, command interpolation,
  `eval`, `exec`, pickle, or user-supplied executable path is used.
- **Privileges:** the live sampler runs as the desktop user with zero effective
  Linux capabilities. The plugin does not invoke sudo/pkexec, modify firewall
  rules, or install services. Its Python imports are standard-library modules.
- **Inputs and writes:** metric reads use fixed procfs paths and `statvfs("/")`.
  The root device path obtained from mount metadata is only inspected with
  `stat`; it is never executed or opened for writing. JSON is parsed as data.
  Settings changes go through the shell's plugin-scoped update API and preserve
  other settings. The toggle accepts only `on`, `off`, `toggle`, and `status`.
- **Local IPC:** the plugin adds no IPC server. It uses the existing shell's
  local command channel. Quickshell socket files were owned by the current user
  under `/run/user/1000`, which was mode `0700` with no extended ACL grant.
  Six invalid/injection-shaped toggle arguments were rejected; no command ran
  and the settings file was byte-for-byte unchanged.
- **File permissions:** no symlinks, group/world-writable entries, setuid/setgid
  entries, unexpected owners, or active Git hooks were found in either the
  installed plugin or development checkout. The home directory was `0700` and
  `shell.json` was `0600`; inspected ACLs granted no additional access.
- **Input capture:** all four meter windows have empty input regions and request
  no keyboard focus. The plugin contains no clipboard or credential handling.

## Hardening applied

The sampler now starts with `python3 -I -u`. Python's
[isolated mode](https://docs.python.org/3/using/cmdline.html#cmdoption-I) excludes
the script directory and user site-packages from imports and ignores `PYTHON*`
environment overrides. This prevents inherited Python configuration or adjacent
modules from changing the sampler's standard-library imports.

`tests/test_security.py` checks the isolated launch from a directory containing
trap modules, with hostile `PYTHONPATH`, `PYTHONHOME`, `PYTHONUSERBASE`, and
`PYTHONINSPECT` values. The sampler still emits valid JSON without importing the
traps. The live process's arguments were separately checked for `-I -u`.
All 40 Python tests pass after the change.

## Trust boundary

Omarchy plugins execute QML inside the user's shell process; they are not
OS-sandboxed. Python isolated mode is import hardening, not a filesystem or
network sandbox. System Python modules, the desktop shell, and the installed
plugin code remain trusted.

Software already running as the same user can access that user's IPC and edit
their plugin files. Root can also do so. The plugin's scoped shell API does not
prevent a malicious replacement plugin from exercising the user's other
permissions. These checks therefore do not establish safety against a
compromised account, malicious future update, or vulnerable dependency.

No network or system-wide security setting was changed by this review.

## Dependency advisory check

Checked 2026-09-27 against installed packages: Python `3.14.7-1`, Qt base
`6.11.2-3`, Qt declarative `6.11.2-2`, and Quickshell `0.3.1-1`.
The Arch tracker lists no outstanding issue for these packages:
[Python](https://security.archlinux.org/package/python),
[Qt base](https://security.archlinux.org/package/qt6-base),
[Qt declarative](https://security.archlinux.org/package/qt6-declarative), and
[Quickshell](https://security.archlinux.org/package/quickshell).
The tracker's sparse historical coverage is not proof of safety.

Recent vendor advisories were checked separately. Installed Qt 6.11.2 is in
the fixed range for the following issues:

| Advisory | Affected operation | Fixed in this installed Qt series |
| --- | --- | --- |
| [CVE-2026-79616](https://www.qt.io/blog/security-advisory-cve-2026-79616) | Qt Quick SVG path parsing, out-of-bounds read | 6.11.2 |
| [CVE-2026-76151](https://www.qt.io/blog/security-advisory-cve-2026-76151) | HTTP cache-header parsing, buffer over-read | 6.11.2 |
| [CVE-2026-78253](https://www.qt.io/blog/security-advisory-cve-2026-78253) | XML stream parsing, stack exhaustion | 6.11.2 |
| [CVE-2026-19248](https://www.qt.io/blog/security-advisory-cve-2026-19248) | XML DOM destruction, stack exhaustion | 6.11.2 |
| [CVE-2026-11573](https://www.qt.io/blog/security-advisory-cve-2026-11573) | XML DOM serialization, stack exhaustion | 6.9.0 |

This plugin does not consume HTTP, XML, or SVG path strings. On the review date,
Python 3.14.7 matched the stable release listed by the
[Python release site](https://www.python.org/downloads/release/python-3147/).
No applicable unpatched advisory was identified in the sources reviewed.
This check does not cover every transitive system library, graphics driver,
unpublished vulnerability, or future advisory. No system packages were changed.
