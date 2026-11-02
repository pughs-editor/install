#!/bin/bash
# Pugh.ai Video Editor one-line installer for Mac (Apple Silicon only). Run it in the Terminal app:
#   curl -fsSL https://raw.githubusercontent.com/pughs-editor/install/main/install.sh | bash
# Safe to run again: it skips anything that is already done. It contains no editor code.
# UNTESTED on a real Mac.

REPO="pughs-editor/video-editor"
MARKET="video-editor-kit"
PLUGIN="video-editor@video-editor-kit"
TOTAL=6
HOME_DIR="${VIDEOEDITOR_HOME:-$HOME/VideoEditor}"

say()  { printf '\n\033[36m%s\033[0m\n' "$1"; }
ok()   { printf '  \033[32mOK: %s\033[0m\n' "$1"; }
stop_here() {  # step, problem, then what-to-do lines
  step="$1"; problem="$2"; shift 2
  printf '\n\033[33mStep %s stopped: %s\033[0m\nWhat to do:\n' "$step" "$problem"
  for t in "$@"; do printf '  - %s\n' "$t"; done
  printf 'Then run the same one-line command again. It picks up where it stopped.\n'
  exit 1
}
have() { command -v "$1" >/dev/null 2>&1; }
add_brew_path() {
  if [ -x /opt/homebrew/bin/brew ]; then eval "$(/opt/homebrew/bin/brew shellenv)"; fi
  export PATH="$HOME/.local/bin:$PATH"
}

if [ "$(uname -s)" != "Darwin" ]; then
  echo "This installer is for Mac. On Windows use the PowerShell line from the Quick Start."; exit 1
fi
if [ "$(uname -m)" != "arm64" ] && [ "$(sysctl -n hw.optional.arm64 2>/dev/null)" != "1" ]; then
  echo "This Mac has an Intel chip. The Pugh.ai Video Editor needs a Mac with Apple Silicon (M1 or newer), so it cannot be installed here."; exit 1
fi
[ "$(id -u)" = "0" ] && { echo "Please run this as your normal user, not with sudo."; exit 1; }

# Check this Mac BEFORE installing anything (nothing below runs if it fails).
RAM_GB=$(( $(sysctl -n hw.memsize 2>/dev/null || echo 0) / 1073741824 ))
FREE_GB=$(df -g "$HOME" | awk 'NR==2{print $4}')
if [ "$RAM_GB" -lt 8 ]; then
  echo "Cannot install on this Mac: it has $RAM_GB GB of memory and the Pugh.ai Video Editor needs at least 8 GB. Nothing was installed or changed."; exit 1
fi
if [ "${FREE_GB:-0}" -lt 15 ]; then
  echo "Cannot install on this Mac: only ${FREE_GB:-0} GB of free disk space and about 15 GB are needed. Free some space, then run the line again. Nothing was installed or changed."; exit 1
fi
echo "Computer check passed: Apple Silicon, $RAM_GB GB memory, $FREE_GB GB free disk."

# Keep the Mac awake for the whole install and the Claude setup it starts (caffeinate ends when this script,
# or the claude process that replaces it at the end, exits). Changes no setting.
if command -v caffeinate >/dev/null 2>&1; then
  caffeinate -i -w $$ >/dev/null 2>&1 &
  echo "Tip: plug in your MacBook and leave this window open. Setup can take up to 30 minutes. Your Mac will stay awake while it runs."
fi
add_brew_path

echo
echo "Pugh.ai Video Editor installer. $TOTAL short steps. You can stop any time with Control+C."

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

# Turn on automatic plugin updates for the kit. Claude Code's documented key is "autoUpdate" on the marketplace's
# entry under "extraKnownMarketplaces" in a settings file. Merges into the user's settings.json with osascript (JXA,
# built into every Mac), keeps a backup, touches nothing else, and fails (changing nothing) if the file cannot be parsed.
enable_autoupdate() {
  local dir js out py c first n
  local specs=()
  dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
  mkdir -p "$dir" || return 1
  # Preferred: Python (every Mac with Git has python3). Sets autoUpdate in settings.json AND in Claude's own
  # plugins/known_marketplaces.json, and in a project settings file inside the workspace if that names the kit.
  for c in python3 python; do
    if command -v "$c" >/dev/null 2>&1 && "$c" -c 'import json' >/dev/null 2>&1; then py="$c"; break; fi
  done
  if [ -n "$py" ]; then
    specs=("$dir/settings.json:1:0" "$dir/plugins/known_marketplaces.json:0:1")
    for n in settings.json settings.local.json; do [ -f "$HOME_DIR/.claude/$n" ] && specs+=("$HOME_DIR/.claude/$n:0:0"); done
    out="$("$py" -c "$MERGE" "$MARKET" "$REPO" "${specs[@]}")"
    first="$(printf '%s
' "$out" | sed -n 1p | cut -f2)"
    [ -n "$out" ] && [ "$first" != "unreadable" ] && return 0
    return 1
  fi
  # Fallback: osascript (JXA, built into every Mac); settings.json only.
  js="$(mktemp -t veau)" || return 1
  cat >"$js" <<'JXA'
ObjC.import('Foundation');
function run(argv) {
  var path = argv[0], market = argv[1], repo = argv[2];
  var fm = $.NSFileManager.defaultManager, obj = {};
  if (fm.fileExistsAtPath(path)) {
    var t = ObjC.unwrap($.NSString.stringWithContentsOfFileEncodingError(path, $.NSUTF8StringEncoding, null));
    if (t && t.trim()) { obj = JSON.parse(t); }
    var bak = path + '.bak-videoeditor';
    if (!fm.fileExistsAtPath(bak)) { fm.copyItemAtPathToPathError(path, bak, null); }
  }
  if (!obj.extraKnownMarketplaces) { obj.extraKnownMarketplaces = {}; }
  if (!obj.extraKnownMarketplaces[market]) { obj.extraKnownMarketplaces[market] = { source: { source: 'github', repo: repo } }; }
  obj.extraKnownMarketplaces[market].autoUpdate = true;
  $(JSON.stringify(obj, null, 2)).writeToFileAtomicallyEncodingError(path, true, $.NSUTF8StringEncoding, null);
  return 'ok';
}
JXA
  out="$(osascript -l JavaScript "$js" "$dir/settings.json" "$MARKET" "$REPO" 2>/dev/null)"
  local rc=$?
  rm -f "$js"
  [ "$rc" -eq 0 ] && [ "$out" = "ok" ]
}

# ---- Step 1: Homebrew, Git, GitHub CLI
say "Step 1 of $TOTAL: checking Homebrew, Git and the GitHub tool..."
if have brew; then ok "Homebrew is already installed"
else
  say "  Installing Homebrew. It asks for your Mac password: type it yourself (nothing shows while you type, that is normal)."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" </dev/tty
  add_brew_path
  have brew || stop_here 1 "Homebrew did not install." "Go to brew.sh, copy the one command on that page, paste it into Terminal and press Enter." "When it finishes, close Terminal, open it again and run the Pugh.ai Video Editor line."
  ok "Homebrew installed"
fi
for pair in "git:git" "gh:gh"; do
  cmd="${pair%%:*}"; pkg="${pair##*:}"
  if have "$cmd" && { [ "$cmd" != "git" ] || xcode-select -p >/dev/null 2>&1 || [ -x /opt/homebrew/bin/git ]; }; then ok "$cmd is already installed"; continue; fi
  say "  Installing $pkg..."
  brew install "$pkg" || stop_here 1 "$pkg did not install." "Type: brew install $pkg   and tell the seller what you see."
  add_brew_path
  have "$cmd" || stop_here 1 "$pkg is not available yet." "Close Terminal, open it again and run the line again."
  ok "$pkg installed"
done

# ---- Step 2: Claude Code
say "Step 2 of $TOTAL: checking Claude Code..."
if have claude; then ok "Claude Code is already installed"
else
  say "  Installing Claude Code (official installer)..."
  bash -c "$(curl -fsSL https://claude.ai/install.sh)" </dev/tty
  add_brew_path
  have claude || stop_here 2 "Claude Code did not install." "Close Terminal and open it again." "Type: curl -fsSL https://claude.ai/install.sh | bash" "Then run the Pugh.ai Video Editor line again."
  ok "Claude Code installed"
fi

# Make Homebrew and ~/.local/bin permanent for every new Terminal window (only adds lines that are missing).
touch "$HOME/.zprofile"
BREW_LINE='eval "$(/opt/homebrew/bin/brew shellenv)"'
LOCAL_LINE='export PATH="$HOME/.local/bin:$PATH"'
[ -x /opt/homebrew/bin/brew ] && { grep -qxF "$BREW_LINE" "$HOME/.zprofile" || printf '
%s
' "$BREW_LINE" >> "$HOME/.zprofile"; }
grep -qxF "$LOCAL_LINE" "$HOME/.zprofile" || printf '
%s
' "$LOCAL_LINE" >> "$HOME/.zprofile"
ok "new Terminal windows will find brew and claude (saved in ~/.zprofile)"

# ---- Step 3: GitHub sign-in
say "Step 3 of $TOTAL: GitHub sign-in..."
if gh auth status >/dev/null 2>&1; then ok "already signed in to GitHub"
else
  say "  A browser window will open. Copy the code shown here, paste it on the page, and click Authorize."
  gh auth login -h github.com -p https -w </dev/tty
  gh auth status >/dev/null 2>&1 || stop_here 3 "GitHub sign-in did not finish." "Type: gh auth login   and choose GitHub.com, HTTPS, 'Login with a web browser'."
  ok "signed in"
fi
gh auth setup-git >/dev/null 2>&1

# ---- Step 4: access to the private kit
say "Step 4 of $TOTAL: checking you can see the Pugh.ai Video Editor kit..."
if ! gh repo view "$REPO" --json name >/dev/null 2>&1; then
  stop_here 4 "your GitHub account cannot see the kit yet." "Accept your GitHub invite email first (search your inbox for an invitation from pughs-editor)." "Make sure you signed in with the same GitHub account the invite was sent to." "If you cannot find the email, tell the seller your GitHub username."
fi
ok "access confirmed"

# ---- Step 5: workspace folder and plugin
# Tested with a brand-new Claude config that was never signed in: "plugin marketplace add" and
# "plugin install" both work without a Claude sign-in. Sign-in happens when Claude starts in Step 6.
say "Step 5 of $TOTAL: installing the Pugh.ai Video Editor plugin..."
mkdir -p "$HOME_DIR" && cd "$HOME_DIR" || stop_here 5 "could not create $HOME_DIR." "Check that your home folder is writable."
if claude plugin marketplace list 2>/dev/null | grep -q "$MARKET"; then ok "kit source already added"
else
  claude plugin marketplace add "$REPO" || stop_here 5 "could not add the kit source." "Type: gh auth status   to check you are signed in." "If you see an SSH or permission error, type: export CLAUDE_CODE_PLUGIN_PREFER_HTTPS=1   and run the line again."
fi
if claude plugin list 2>/dev/null | grep -q "video-editor@"; then ok "plugin already installed"
else
  claude plugin install "$PLUGIN" || stop_here 5 "could not install the plugin." "Run the line again. If it fails twice, tell the seller exactly what you see."
fi
if enable_autoupdate; then ok "Updates install automatically."
else printf '  Note: could not turn on automatic updates. Later, in Claude Code, type /plugin, open Marketplaces, choose video-editor-kit, then Enable auto-update. Until then, /video-editor:editor-update gets new versions.
'
fi
ok "workspace folder: $HOME_DIR"

# ---- Step 6: start setup
say "Step 6 of $TOTAL: almost done."
printf '
\033[1mNext time, to open the editor:\033[0m
  cd ~/VideoEditor
  claude -c

'
# Claude is NOT launched from inside this piped installer: on macOS it crashed there (Bun "EINVAL: invalid argument, kqueue").
# The user starts it themselves in a normal Terminal prompt with the line below.
printf '\033[1;32mAll set!\033[0m Last step: copy this line, paste it and press Return:\n\n'
printf '  \033[1mcd ~/VideoEditor && claude "/video-editor:editor-setup"\033[0m\n\n'
echo "If Claude asks you to sign in, click Authorize in the browser."
exit 0
