#!/usr/bin/env bash
# Capture (or verify) a backup of the installed OpenCode agent fleet.
#
#   ./sync.sh            copy live agent files into agents/, regenerate manifest.json
#   ./sync.sh --check    verify the repo still matches the live directory (no writes)
#
# Environment:
#   OPENCODE_AGENTS   live profile directory (default: ~/.config/opencode/agents)
#   AGENTIC_SDD_REPO  canonical pack checkout used for provenance
#                     (default: ~/github/agentic-sdd, may be absent)
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIVE="${OPENCODE_AGENTS:-$HOME/.config/opencode/agents}"
PACK="${AGENTIC_SDD_REPO:-$HOME/github/agentic-sdd}"
MODE="${1:-capture}"

[[ -d "$LIVE" ]] || { echo "error: live profile directory not found: $LIVE" >&2; exit 1; }

shopt -s nullglob
files=("$LIVE"/*.md)
shopt -u nullglob
[[ ${#files[@]} -gt 0 ]] || { echo "error: no agent files in $LIVE" >&2; exit 1; }

for f in "${files[@]}"; do
  [[ -f "$f" && ! -L "$f" ]] || { echo "error: refusing non-regular or symlinked file: $f" >&2; exit 1; }
done

tool_version="unknown"; tool_commit="unknown"
for bin in asdx-core agentic-sdd; do
  if command -v "$bin" >/dev/null 2>&1; then
    out="$("$bin" --version 2>/dev/null || true)"
    v="$(sed -n 's/^agentic-sdd \(v[^ ]*\).*/\1/p' <<<"$out" | head -1)"
    c="$(sed -n 's/^ *commit: *//p' <<<"$out" | head -1)"
    [[ -n "$v" ]] && tool_version="$v"
    [[ -n "$c" ]] && tool_commit="$c"
    break
  fi
done

pack_commit="unknown"
if git -C "$PACK" rev-parse --short HEAD >/dev/null 2>&1; then
  pack_commit="$(git -C "$PACK" rev-parse --short HEAD)"
fi

if [[ "$MODE" == "--check" ]]; then
  python3 - "$REPO" "$LIVE" <<'PY'
import hashlib, json, os, sys
repo, live = sys.argv[1], sys.argv[2]
manifest = json.load(open(os.path.join(repo, "manifest.json")))
problems = []
listed = set()
for entry in manifest["agents"]:
    listed.add(os.path.basename(entry["path"]))
    path = os.path.join(repo, entry["path"])
    if not os.path.isfile(path):
        problems.append(f"missing in repo: {entry['path']}")
        continue
    digest = hashlib.sha256(open(path, "rb").read()).hexdigest()
    if digest != entry["sha256"]:
        problems.append(f"repo file differs from its manifest digest: {entry['path']}")
    live_path = os.path.join(live, os.path.basename(entry["path"]))
    if not os.path.isfile(live_path):
        problems.append(f"missing in live directory: {live_path}")
        continue
    if hashlib.sha256(open(live_path, "rb").read()).hexdigest() != entry["sha256"]:
        problems.append(f"live file differs from snapshot: {entry['path']}")
current = {f for f in os.listdir(live) if f.endswith(".md")}
for extra in sorted(current - listed):
    problems.append(f"not captured: agents/{extra}")
if problems:
    print("drift detected:")
    for p in problems:
        print("  -", p)
    sys.exit(1)
print(f"ok: {len(listed)} agent files match the snapshot and manifest")
PY
  exit $?
fi

[[ "$MODE" == "capture" ]] || { echo "error: unknown mode '$MODE' (use --check)" >&2; exit 1; }

rm -rf "$REPO/agents"
mkdir -p "$REPO/agents"
for f in "${files[@]}"; do
  cp -p "$f" "$REPO/agents/$(basename "$f")"
done

python3 - "$REPO" "$LIVE" "$tool_version" "$tool_commit" "$pack_commit" <<'PY'
import hashlib, json, os, sys
repo, live, tool_version, tool_commit, pack_commit = sys.argv[1:6]
files = []
for name in sorted(os.listdir(os.path.join(repo, "agents"))):
    if not name.endswith(".md"):
        continue
    data = open(os.path.join(repo, "agents", name), "rb").read()
    files.append({"path": f"agents/{name}", "sha256": hashlib.sha256(data).hexdigest(), "bytes": len(data)})
fleet = open(os.path.join(repo, "fleet.json"), "rb").read()
manifest = {
    "format": 1,
    "source": "~/.config/opencode/agents",
    "tool": {"name": "asdx-core", "version": tool_version, "commit": tool_commit},
    "pack": {"repository": "agentic-sdd", "commit": pack_commit},
    "fleetConfig": {"path": "fleet.json", "sha256": hashlib.sha256(fleet).hexdigest()},
    "agents": files,
}
with open(os.path.join(repo, "manifest.json"), "w") as fh:
    json.dump(manifest, fh, indent=2)
    fh.write("\n")
print(f"captured {len(files)} agent files")
PY

echo "next: git diff --stat, then commit the reviewed change"
