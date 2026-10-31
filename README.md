# Video Editor installer

One-line installers for the Video Editor kit. They contain no editor code: they only install the tools you need (Git, GitHub CLI, Claude Code), help you sign in to GitHub, and add the kit you were invited to.

You need a paid Claude account and a GitHub account that has accepted your invite.

**Windows** (open a normal PowerShell, not "as administrator"):

```
irm https://raw.githubusercontent.com/pughs-editor/install/main/install.ps1 | iex
```

**Mac** (Apple Silicon only, open Terminal; untested on a real Mac so far):

```
curl -fsSL https://raw.githubusercontent.com/pughs-editor/install/main/install.sh | bash
```

Safe to run again: it skips anything already done. It never asks for administrator rights and never changes security settings. You can read both scripts in this repo before running them.
