# Pugh.ai Video Editor installer

One-line installers for the Pugh.ai Video Editor kit. They contain no editor code: they only install the tools you need (Git, GitHub CLI, Claude Code), help you sign in to GitHub, and add the kit you were invited to.

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

## Repair (already installed, but updates are not arriving)

Run the line for your computer. It turns automatic updates on in both places Claude Code looks, makes sure your GitHub sign-in can be used for background updates, and pulls the newest version right now. It does not reinstall anything and does not touch your videos.

**Windows** (normal PowerShell):

```
irm https://raw.githubusercontent.com/pughs-editor/install/main/repair.ps1 | iex
```

**Mac** (Terminal):

```
curl -fsSL https://raw.githubusercontent.com/pughs-editor/install/main/repair.sh | bash
```

If you edited the editor's own files or added effects to them, run it once with the migration switch. It saves a copy of everything first, then moves your work into the protected `custom` folder so future updates cannot overwrite it:

```
$env:VE_MIGRATE = 1; irm https://raw.githubusercontent.com/pughs-editor/install/main/repair.ps1 | iex
```

```
curl -fsSL https://raw.githubusercontent.com/pughs-editor/install/main/repair.sh | VE_MIGRATE=1 bash
```

