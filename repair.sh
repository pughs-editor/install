#!/bin/bash
# Pugh.ai Video Editor repair for Mac. Paste this one line into Terminal:
#   curl -fsSL https://raw.githubusercontent.com/pughs-editor/install/main/repair.sh | bash
# To also move your own edits into the protected custom folder (one time), paste this instead:
#   curl -fsSL https://raw.githubusercontent.com/pughs-editor/install/main/repair.sh | VE_MIGRATE=1 bash
#
# What it does, in order. It never reinstalls, never touches your videos or settings other than the one entry below:
#   1. turns automatic updates on for the video editor (in both places Claude Code looks)
#   2. makes sure your GitHub sign-in can be used for background updates (gh auth setup-git)
#   3. pulls the newest video editor version right now
#   4. optional: moves your edits and added effects into the custom folder (VE_MIGRATE)
# It contains no editor code.

REPO="pughs-editor/video-editor"
MARKET="video-editor-kit"
PLUGIN="video-editor@video-editor-kit"
HOME_DIR="${VIDEOEDITOR_HOME:-$HOME/VideoEditor}"
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

say() { printf '\033[36m%s\033[0m\n' "$1"; }
ok() { printf '\033[32m  OK: %s\033[0m\n' "$1"; }
warn() { printf '\033[33m  Note: %s\033[0m\n' "$1"; }
have() { command -v "$1" >/dev/null 2>&1; }

if ! have claude; then
  printf '\033[33mClaude Code is not installed on this computer, so there is nothing to repair. Run the install line from the Quick Start instead.\033[0m\n'
  exit 1
fi
# The workspace's own Python if setup finished, else the system one (Macs with Git have python3).
PY=""
for c in "$HOME_DIR/.venv/bin/python" "$HOME_DIR/.venv/Scripts/python.exe" python3 python; do
  if { [ -x "$c" ] || command -v "$c" >/dev/null 2>&1; } && "$c" -c 'import json' >/dev/null 2>&1; then PY="$c"; break; fi
done
if [ -z "$PY" ]; then
  printf '\033[33mPython was not found. Open the editor (cd ~/VideoEditor && claude -c) and say: repair my automatic updates.\033[0m\n'
  exit 1
fi

# Turn "autoUpdate": true on for the video editor's marketplace entry in JSON files. Keeps every other value, keeps a
# .bak-videoeditor copy, leaves a file it cannot parse untouched. Args: market repo, then "file:create:top" triples.
read -r -d '' MERGE <<'PY'
import json, os, shutil, sys

market, repo = sys.argv[1], sys.argv[2]


def set_autoupdate(path, create, top):
    try:
        data = {}
        if os.path.exists(path):
            raw = open(path, encoding="utf-8").read()
            if raw.strip():
                data = json.loads(raw)
            if not isinstance(data, dict):
                return "unreadable"
        elif not create:
            return "skipped"
        if top:
            mk = data
        else:
            if "extraKnownMarketplaces" not in data:
                if not create:
                    return "skipped"
                data["extraKnownMarketplaces"] = {}
            mk = data["extraKnownMarketplaces"]
        if market not in mk:
            if not create:
                return "skipped"
            mk[market] = {"source": {"source": "github", "repo": repo}}
        if mk[market].get("autoUpdate") is True:
            return "already"
        mk[market]["autoUpdate"] = True
        if os.path.exists(path) and not os.path.exists(path + ".bak-videoeditor"):
            shutil.copy2(path, path + ".bak-videoeditor")
        os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
            f.write("\n")
        return "changed"
    except Exception:
        return "unreadable"


for spec in sys.argv[3:]:
    path, create, top = spec.rsplit(":", 2)
    print(path + "\t" + set_autoupdate(path, create == "1", top == "1"))
PY

say "Step 1 of 4: turning on automatic updates..."
if ! claude plugin marketplace list 2>/dev/null | grep -q "$MARKET"; then
  claude plugin marketplace add "$REPO" >/dev/null 2>&1 || {
    printf '\033[33mCould not add the video editor source. In Terminal type: gh auth status   (it must say you are signed in). If not, type: gh auth login   then run this line again.\033[0m\n'
    exit 1
  }
  ok "video editor source added"
fi
specs=("$CFG/settings.json:1:0" "$CFG/plugins/known_marketplaces.json:0:1")
for d in "$HOME_DIR" "$PWD"; do
  for n in settings.json settings.local.json; do
    [ -f "$d/.claude/$n" ] && specs+=("$d/.claude/$n:0:0")
  done
done
result="$("$PY" -c "$MERGE" "$MARKET" "$REPO" "${specs[@]}")"
if [ -z "$result" ]; then
  warn "could not read or change the Claude settings, so I left them alone. In Claude Code type /plugin, open Marketplaces, choose $MARKET, then Enable auto-update."
fi
first="$(printf '%s\n' "$result" | sed -n 1p | cut -f2)"
second="$(printf '%s\n' "$result" | sed -n 2p | cut -f2)"
if [ "$first" = "unreadable" ]; then
  warn "your Claude settings file could not be read, so I left it alone. In Claude Code type /plugin, open Marketplaces, choose $MARKET, then Enable auto-update."
else
  ok "settings: $first; Claude's own list: $second"
fi
printf '%s\n' "$result" | sed -n '3,$p' | while IFS="$(printf '\t')" read -r f r; do
  [ "$r" = "changed" ] && ok "also fixed $f (it named the video editor without automatic updates)"
done

say "Step 2 of 4: checking your GitHub sign-in..."
if have gh; then
  if gh auth status >/dev/null 2>&1; then
    gh auth setup-git >/dev/null 2>&1
    ok "GitHub sign-in is ready for background updates"
  else
    warn "you are not signed in to GitHub. Type: gh auth login   (choose GitHub.com, HTTPS, web browser), then run this line again."
  fi
else
  warn "the GitHub tool (gh) is not installed. Run the install line from the Quick Start once; it installs it."
fi

say "Step 3 of 4: getting the newest video editor version..."
installed() {  # prints "version<TAB>installPath" of the plugin, or nothing
  claude plugin list --json 2>/dev/null | "$PY" -c '
import json, sys
try:
    for e in json.load(sys.stdin):
        if e.get("id") == sys.argv[1]:
            print(e.get("version", "") + "\t" + e.get("installPath", ""))
            break
except Exception:
    pass' "$PLUGIN"
}
before="$(installed)"
if [ -z "$before" ]; then claude plugin install "$PLUGIN" >/dev/null 2>&1; before="$(installed)"; fi
claude plugin marketplace update "$MARKET" >/dev/null 2>&1
upd="$(claude plugin update "$PLUGIN" 2>&1)"
after="$(installed)"
if [ -z "$after" ]; then
  printf '\033[33mThe video editor is not installed. Tell the seller what you see when you type: claude plugin install %s\033[0m\n' "$PLUGIN"
  exit 1
fi
vb="${before%%$(printf '\t')*}"; va="${after%%$(printf '\t')*}"; path="${after#*$(printf '\t')}"
if [ -n "$vb" ] && [ "$vb" != "$va" ]; then ok "updated from $vb to $va"; else ok "already on the newest version ($va)"; fi
if printf '%s' "$upd" | grep -qiE 'fail|error|denied|authent'; then warn "the update check said: $upd"; fi

if [ -n "$VE_MIGRATE" ]; then
  say "Step 4 of 4: moving your own edits into the protected custom folder..."
  if [ ! -d "$HOME_DIR" ]; then warn "no workspace folder found at $HOME_DIR (set VIDEOEDITOR_HOME if yours is elsewhere)"
  else VIDEOEDITOR_HOME="$HOME_DIR" PYTHONIOENCODING=utf-8 "$PY" "$path/tools/workspace.py" migrate-custom
  fi
else
  say "Step 4 of 4: nothing else to do."
fi

printf '\n\033[1mDone. Close this window. To open the editor: open Terminal, type  cd ~/VideoEditor  then  claude -c\033[0m\n'
printf '\033[1mVersion now: %s.\033[0m\n' "$va"
