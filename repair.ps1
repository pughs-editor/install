# Pugh.ai Video Editor repair for Windows. Paste this one line into a normal PowerShell window:
#   irm https://raw.githubusercontent.com/pughs-editor/install/main/repair.ps1 | iex
# To also move your own edits into the protected custom folder (one time), paste this instead:
#   $env:VE_MIGRATE = 1; irm https://raw.githubusercontent.com/pughs-editor/install/main/repair.ps1 | iex
#
# What it does, in order. It never reinstalls, never touches your videos or settings other than the one entry below:
#   1. turns automatic updates on for the video editor (in both places Claude Code looks)
#   2. makes sure your GitHub sign-in can be used for background updates (gh auth setup-git)
#   3. pulls the newest video editor version right now
#   4. optional: moves your edits and added effects into the custom folder (VE_MIGRATE)
# It contains no editor code.

function Repair-VideoEditor {
    $Repo = "pughs-editor/video-editor"
    $Market = "video-editor-kit"
    $Plugin = "video-editor@video-editor-kit"
    $Home2 = if ($env:VIDEOEDITOR_HOME) { $env:VIDEOEDITOR_HOME } else { Join-Path $HOME "VideoEditor" }
    $Cfg = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME ".claude" }

    function Say($m) { Write-Host $m -ForegroundColor Cyan }
    function Ok($m) { Write-Host "  OK: $m" -ForegroundColor Green }
    function Warn($m) { Write-Host "  Note: $m" -ForegroundColor Yellow }
    function Have($name) { return [bool](Get-Command $name -ErrorAction SilentlyContinue) }
    # Native commands can write to stderr; that must not stop this script. Exit codes only.
    function Native-Code([scriptblock]$sb) {
        $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        $global:LASTEXITCODE = 0
        try { & $sb *> $null } catch { if ($global:LASTEXITCODE -eq 0) { $global:LASTEXITCODE = 1 } }
        $code = $global:LASTEXITCODE
        $ErrorActionPreference = $old
        return [int]$code
    }
    function Native-Text([scriptblock]$sb) {
        $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        $out = ""
        try { $out = (& $sb 2>$null) -join "`n" } catch { }
        $ErrorActionPreference = $old
        return $out
    }

    # ---- JSON helpers. Windows PowerShell 5.1's ConvertFrom-Json turns date-looking strings into dates and
    # ConvertTo-Json then writes them back in a different format, which would damage Claude's own files.
    # JavaScriptSerializer keeps every value exactly as it is.
    try { Add-Type -AssemblyName System.Web.Extensions } catch { }
    function New-Ser { $s = New-Object System.Web.Script.Serialization.JavaScriptSerializer; $s.MaxJsonLength = [int]::MaxValue; $s.RecursionLimit = 200; return $s }
    function Format-Json([string]$json) {
        $sb = New-Object System.Text.StringBuilder
        $chars = $json.ToCharArray()
        $indent = 0; $inStr = $false; $esc = $false
        for ($i = 0; $i -lt $chars.Length; $i++) {
            $c = $chars[$i]
            if ($inStr) {
                [void]$sb.Append($c)
                if ($esc) { $esc = $false } elseif ($c -eq [char]92) { $esc = $true } elseif ($c -eq '"') { $inStr = $false }
                continue
            }
            if (($c -eq '{' -and $i + 1 -lt $chars.Length -and $chars[$i + 1] -eq '}') -or ($c -eq '[' -and $i + 1 -lt $chars.Length -and $chars[$i + 1] -eq ']')) {
                [void]$sb.Append($c).Append($chars[$i + 1]); $i++; continue   # empty {} or []
            }
            switch ($c) {
                '"' { $inStr = $true; [void]$sb.Append($c) }
                '{' { $indent++; [void]$sb.Append($c).Append("`n").Append(' ' * (2 * $indent)) }
                '[' { $indent++; [void]$sb.Append($c).Append("`n").Append(' ' * (2 * $indent)) }
                '}' { $indent--; [void]$sb.Append("`n").Append(' ' * (2 * $indent)).Append($c) }
                ']' { $indent--; [void]$sb.Append("`n").Append(' ' * (2 * $indent)).Append($c) }
                ',' { [void]$sb.Append($c).Append("`n").Append(' ' * (2 * $indent)) }
                ':' { [void]$sb.Append(': ') }
                default { if (-not [char]::IsWhiteSpace($c)) { [void]$sb.Append($c) } }
            }
        }
        return $sb.ToString()
    }
    # Turn "autoUpdate": true on for the video editor's marketplace entry in one JSON file.
    # $create: add the entry (with its GitHub source) if the file has none. Returns: changed | already | skipped | unreadable
    function Set-AutoUpdate([string]$file, [bool]$create, [bool]$topLevel) {
        try {
            $ser = New-Ser
            $obj = $ser.DeserializeObject('{}')   # plain .NET dictionaries (not PowerShell-wrapped), so Serialize can write them
            if (Test-Path $file) {
                $raw = [IO.File]::ReadAllText($file)
                if ($raw.Trim()) { $obj = $ser.DeserializeObject($raw) }
            } elseif (-not $create) { return "skipped" }
            # known_marketplaces.json keeps the entries at the top level; settings files keep them under extraKnownMarketplaces
            if ($topLevel) { $mk = $obj } else {
                if (-not $obj.ContainsKey("extraKnownMarketplaces")) {
                    if (-not $create) { return "skipped" }
                    $obj["extraKnownMarketplaces"] = $ser.DeserializeObject('{}')
                }
                $mk = $obj["extraKnownMarketplaces"]
            }
            if (-not $mk.ContainsKey($Market)) {
                if (-not $create) { return "skipped" }
                $mk[$Market] = $ser.DeserializeObject('{"source":{"source":"github","repo":"' + $Repo + '"}}')
            }
            $entry = $mk[$Market]
            if ($entry.ContainsKey("autoUpdate") -and $entry["autoUpdate"] -eq $true) { return "already" }
            $entry["autoUpdate"] = $true
            if ((Test-Path $file) -and -not (Test-Path "$file.bak-videoeditor")) { Copy-Item $file "$file.bak-videoeditor" }
            New-Item -ItemType Directory -Force -Path (Split-Path $file) | Out-Null
            [IO.File]::WriteAllText($file, (Format-Json ($ser.Serialize($obj))), (New-Object Text.UTF8Encoding($false)))
            return "changed"
        } catch { return "unreadable" }
    }

    if (-not (Have claude)) {
        $env:Path = ([Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User") + ";$HOME\.local\bin")
    }
    if (-not (Have claude)) {
        Write-Host "Claude Code is not installed on this computer, so there is nothing to repair. Run the install line from the Quick Start instead." -ForegroundColor Yellow
        return
    }

    # ---- 1. the marketplace is added, and automatic updates are on in both places
    Say "Step 1 of 4: turning on automatic updates..."
    $markets = Native-Text { claude plugin marketplace list }
    if ($markets -notmatch $Market) {
        if ((Native-Code { claude plugin marketplace add $Repo }) -ne 0) {
            Write-Host "Could not add the video editor source. In PowerShell type: gh auth status   (it must say you are signed in). If not, type: gh auth login   then run this line again." -ForegroundColor Yellow
            return
        }
        Ok "video editor source added"
    }
    $r1 = Set-AutoUpdate (Join-Path $Cfg "settings.json") $true $false
    $r2 = Set-AutoUpdate (Join-Path (Join-Path $Cfg "plugins") "known_marketplaces.json") $false $true
    if ($r1 -eq "unreadable") {
        Warn "your Claude settings file could not be read, so I left it alone. In Claude Code type /plugin, open Marketplaces, choose $Market, then Enable auto-update."
    } else { Ok "settings: $r1; Claude's own list: $r2" }
    # A project or local settings file that names the marketplace without autoUpdate would override the setting above.
    foreach ($d in @($Home2, (Get-Location).Path)) {
        foreach ($n in "settings.json", "settings.local.json") {
            $f = Join-Path (Join-Path $d ".claude") $n
            if (Test-Path $f) {
                $r = Set-AutoUpdate $f $false $false
                if ($r -eq "changed") { Ok "also fixed $f (it named the video editor without automatic updates)" }
            }
        }
    }

    # ---- 2. background updates need a GitHub sign-in that git can use without asking
    Say "Step 2 of 4: checking your GitHub sign-in..."
    if (Have gh) {
        if ((Native-Code { gh auth status }) -eq 0) {
            [void](Native-Code { gh auth setup-git })
            Ok "GitHub sign-in is ready for background updates"
        } else { Warn "you are not signed in to GitHub. Type: gh auth login   (choose GitHub.com, HTTPS, web browser), then run this line again." }
    } else { Warn "the GitHub tool (gh) is not installed. Run the install line from the Quick Start once; it installs it." }

    # ---- 3. get the newest version now
    Say "Step 3 of 4: getting the newest video editor version..."
    function Get-Installed {
        $j = Native-Text { claude plugin list --json }
        try { $l = $j | ConvertFrom-Json; return @($l | Where-Object { $_.id -eq $Plugin })[0] } catch { return $null }
    }
    $before = Get-Installed
    if (-not $before) {
        [void](Native-Code { claude plugin install $Plugin })
        $before = Get-Installed
    }
    $m = Native-Text { claude plugin marketplace update $Market }
    $u = Native-Text { claude plugin update $Plugin }
    $after = Get-Installed
    if (-not $after) {
        Write-Host "The video editor is not installed. Tell the seller what you see when you type: claude plugin install $Plugin" -ForegroundColor Yellow
        return
    }
    if ($before -and $before.version -ne $after.version) { Ok "updated from $($before.version) to $($after.version)" }
    else { Ok "already on the newest version ($($after.version))" }
    if ($u -match "(?i)fail|error|denied|authent") { Warn "the update check said: $($u.Trim())" }

    # ---- 4. optional one-time migration of the tester's own edits
    if ($env:VE_MIGRATE) {
        Say "Step 4 of 4: moving your own edits into the protected custom folder..."
        $ws = Join-Path $after.installPath "tools\workspace.py"
        $py = Join-Path $Home2 ".venv\Scripts\python.exe"
        if (-not (Test-Path $py)) { $py = (Get-Command python -ErrorAction SilentlyContinue).Source }
        if (-not (Test-Path $Home2)) { Warn "no workspace folder found at $Home2 (set VIDEOEDITOR_HOME if yours is elsewhere)" }
        elseif (-not $py) { Warn "Python was not found. Open the editor (cd $Home2 ; claude -c) and say: run migrate-custom" }
        else {
            $env:VIDEOEDITOR_HOME = $Home2
            $env:PYTHONIOENCODING = "utf-8"
            & $py $ws migrate-custom
        }
    } else { Say "Step 4 of 4: nothing else to do." }

    Write-Host ""
    Write-Host "Done. Close this window. To open the editor: open PowerShell, type  cd `$HOME\VideoEditor  then  claude -c" -ForegroundColor White
    Write-Host "Version now: $($after.version)." -ForegroundColor White
}
Repair-VideoEditor
