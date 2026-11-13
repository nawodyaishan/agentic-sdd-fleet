# agentic-sdd-fleet

Personal backup and definition of one OpenCode agent fleet, for use with the
`asdx-core fleet` commands of [agentic-sdd](https://github.com/nawodyaishan/agentic-sdd).

This repository holds **configuration only**. It contains no credentials, no
API keys, no `opencode.json`, and no provider account state.

## What is here

| Path | Role |
|---|---|
| `fleet.json` | Desired-state definition: 27 instances, each bound to one canonical source (`agent:` or `preset:`) plus its model lane. |
| `agents/` | Verbatim snapshot of the 27 agent files installed at `~/.config/opencode/agents/` at capture time. Backup of record for files the pack cannot render. |
| `manifest.json` | Tool and pack provenance plus SHA-256 for every snapshot file. |
| `sync.sh` | Re-capture the snapshot from the live profile directory; `--check` verifies without writing. |

The two layers are deliberate:

- `fleet.json` is reproducible. `asdx-core fleet plan` renders each file from the
  canonical pack and replaces only the `model:` scalar, so the same pack version
  plus this file yields byte-identical managed agents.
- `agents/` preserves what is actually installed now. Seven files
  (`sdd-implement-9r-*`, `sdd-implement-free-*`, `vision`) have no matching
  canonical source in the pack, so `fleet.json` binds them to the closest
  `preset:`/`agent:` source instead. Applying the fleet would rewrite their
  descriptions and permission blocks to the canonical body. The snapshot keeps
  the current bytes so nothing is lost.

## Known divergence

`sdd-implement-9r-1` is bound to `9router/ag/gemini-4-hydrogen-xhigh` in
`fleet.json`, replacing the former `9router/ag/gemini-3.8-flash-high` lane.
The installed file in `agents/` still carries the Flash model until an apply is
reviewed and authorized. This is the only intentional difference between the
definition and the snapshot.

## Restore on this machine

```sh
# 1. Reinstate the exact installed bytes (the snapshot)
cp agents/*.md ~/.config/opencode/agents/

# 2. Or re-render the managed set from the definition (writes on apply only)
asdx-core fleet status --config ./fleet.json     # read-only
asdx-core fleet plan   --config ./fleet.json     # preview, writes nothing
asdx-core fleet plan   --config ./fleet.json --output /tmp/fleet.plan.json
asdx-core fleet apply  --plan /tmp/fleet.plan.json   # separate authorization

# 3. Undo a fleet apply
asdx-core fleet restore --backup <fleet-backup-id>
```

`fleet plan` and `fleet apply` write to the real home and take ownership of the
managed files. Preview first; a plan ID is a consistency token, not an
authorization.

## Reproduce on another machine

```sh
git clone git@github.com:nawodyaishan/agentic-sdd-fleet.git ~/github/agentic-sdd-fleet
asdx-core apply --with-opencode          # install the canonical pack first
asdx-core fleet plan --config ~/github/agentic-sdd-fleet/fleet.json
```

The pack commit in `manifest.json` is the reference. A different pack version
changes rendered bodies even when `fleet.json` is unchanged.

## Refresh the snapshot

```sh
./sync.sh          # copy live files into agents/, regenerate manifest.json
./sync.sh --check  # exit 1 if the repo no longer matches the live directory
git diff --stat
```

Review the diff before committing. Never add credentials; `opencode.json`,
`secrets/` and provider tokens are out of scope.

## Use it with the `asdx` TUI

The TUI never scans for a file, so point it at the repository explicitly.

```sh
asdx --fleet-config ~/github/agentic-sdd-fleet/fleet.json
```

`asdx-core tui --fleet-config PATH` is the equivalent entry point. If the TUI is
already open:

1. Open **Install & Manage** (`i` or the hub), then **Fleet Manager** (`f`).
2. On **Overview**, press `s` and type
   `/home/<you>/github/agentic-sdd-fleet/fleet.json`.
3. Press `r` after you edit `fleet.json` in the repo; the source is re-read.

When running a local build instead of an installed pair, `asdx` may not be on
`PATH`. These are the same launch:

```sh
~/github/agentic-sdd/bin/tui-pair/asdx --fleet-config ~/github/agentic-sdd-fleet/fleet.json
~/github/agentic-sdd/bin/asdx-core tui --fleet-config ~/github/agentic-sdd-fleet/fleet.json
```

| Key | View | What this repo shows |
|---|---|---|
| `1` / `o` | Overview | Source path, 27 configured / 27 enabled / 0 managed |
| `2` / `p` | Profiles | One row per instance with its current model lane |
| `3` / `c` | Review | Preview-only plan; every file is a conflict until the fleet is adopted |
| `4` / `e` | Recovery | Empty until a fleet apply has created a managed backup |

**Expect "unmanaged" and "conflict" on first open.** This repository is a
backup, not an ownership claim. The installed files carry no fleet provenance,
so Overview counts 27 `unmanaged` and Review stops with
`unmanaged file already exists; use --adopt after review`. That is the safe
default: nothing is written. Taking ownership is a deliberate
`asdx-core fleet plan --adopt` → reviewed apply, run in a terminal.

What the current build cannot do for you:

- Deployment and restore are **preview only**; the write is disabled.
- The in-app source editor stages model edits in memory but cannot save
  `fleet.json`. Edit the file in this repo instead, then press `r`.
- Clearing an override back to canonical inheritance is a text edit, not a
  picker action.
- The TUI makes no Git call. Commit and push from a terminal.
- The source choice is session-only. There is no stored preference, so either
  pass `--fleet-config` every launch or retype the path after `s`.

## Keep it private

Model lanes describe provider routing, paid and free tiers, and local proxy
usage. That is personal infrastructure metadata, so this repository is
intentionally private.
