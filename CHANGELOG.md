# Changelog

## 1.1.0 — 2026-09-27

### Added

- Optional logical CPU row above the total CPU row, each 3 logical pixels tall.
  Slots follow the CPUs reported by Linux, including SMT threads, sparse CPU
  IDs, and hotplug changes. No configured core count is needed.
- Persistent `logicalCpu on|off|toggle|status` commands. The option is off by
  default; disabling it restores the original single-row thickness.
- CPU, storage, network, display-scaling, and isolated-launch regression tests,
  plus documented compatibility and security review results.

### Changed

- The CPU strip reserves its top space automatically and adjusts it when the
  logical row is toggled. Logical CPU usage updates reuse existing meters;
  topology changes rebuild the slots.
- The sampler launches Python in isolated mode to prevent inherited Python
  settings and adjacent modules from overriding standard-library imports.

### Fixed

- Network interface selection ignores rejected or inactive default routes and
  requires a zero IPv4 destination mask for default-route detection.
- Missing aggregate CPU counters clear their baseline. New, reset, or unchanged
  logical CPU counters remain unfilled until a valid interval is available.
- Disabling peak markers clears existing markers and stops their timers.

### Upgrade note

Remove the manual top reservation previously added for mini-omatop from each
monitor rule. Retain space required by other panels and the plugin's side and
bottom reservations. See [update instructions](README.md#update).

Earlier changes are recorded in the repository's Git history.
