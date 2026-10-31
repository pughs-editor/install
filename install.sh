#!/bin/bash
# Video Editor one-line installer for Mac (Apple Silicon only). Run it in the Terminal app:
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
  echo "This Mac has an Intel chip. The Video Editor needs a Mac with Apple Silicon (M1 or newer), so it cannot be installed here."; exit 1
fi
[ "$(id -u)" = "0" ] && { echo "Please run this as your normal user, not with sudo."; exit 1; }
add_brew_path

echo
echo "Video Editor installer. $TOTAL short steps. You can stop any time with Control+C."

# ---- Step 1: Homebrew, Git, GitHub CLI
say "Step 1 of $TOTAL: checking Homebrew, Git and the GitHub tool..."
if have brew; then ok "Homebrew is already installed"
else
  say "  Installing Homebrew. It asks for your Mac password: type it yourself (nothing shows while you type, that is normal)."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" </dev/tty
  add_brew_path
  have brew || stop_here 1 "Homebrew did not install." "Go to brew.sh, copy the one command on that page, paste it into Terminal and press Enter." "When it finishes, close Terminal, open it again and run the Video Editor line."
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
  curl -fsSL https://claude.ai/install.sh | bash </dev/tty
  add_brew_path
  have claude || stop_here 2 "Claude Code did not install." "Close Terminal and open it again." "Type: curl -fsSL https://claude.ai/install.sh | bash" "Then run the Video Editor line again."
  ok "Claude Code installed"
fi

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
say "Step 4 of $TOTAL: checking you can see the Video Editor kit..."
if ! gh repo view "$REPO" --json name >/dev/null 2>&1; then
  stop_here 4 "your GitHub account cannot see the kit yet." "Accept your GitHub invite email first (search your inbox for an invitation from pughs-editor)." "Make sure you signed in with the same GitHub account the invite was sent to." "If you cannot find the email, tell the seller your GitHub username."
fi
ok "access confirmed"

# ---- Step 5: workspace folder and plugin
say "Step 5 of $TOTAL: installing the Video Editor plugin..."
mkdir -p "$HOME_DIR" && cd "$HOME_DIR" || stop_here 5 "could not create $HOME_DIR." "Check that your home folder is writable."
if claude plugin marketplace list 2>/dev/null | grep -q "$MARKET"; then ok "kit source already added"
else
  claude plugin marketplace add "$REPO" || stop_here 5 "could not add the kit source." "Type: gh auth status   to check you are signed in." "If you see an SSH or permission error, type: export CLAUDE_CODE_PLUGIN_PREFER_HTTPS=1   and run the line again."
fi
if claude plugin list 2>/dev/null | grep -q "video-editor@"; then ok "plugin already installed"
else
  claude plugin install "$PLUGIN" || stop_here 5 "could not install the plugin." "Run the line again. If it fails twice, tell the seller exactly what you see."
fi
ok "workspace folder: $HOME_DIR"

# ---- Step 6: start setup
say "Step 6 of $TOTAL: starting Claude. It will set up the rest, one step at a time."
if [ -n "$INSTALL_NO_LAUNCH" ]; then ok "test mode: not starting Claude"; exit 0; fi
echo "  If Claude asks you to sign in, click Authorize in the browser."
exec claude "/video-editor:editor-setup" </dev/tty
