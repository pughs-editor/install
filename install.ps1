# Pugh.ai Video Editor one-line installer for Windows. Run it in a normal PowerShell window (not "as administrator"):
#   irm https://raw.githubusercontent.com/pughs-editor/install/main/install.ps1 | iex
# Safe to run again: it skips anything that is already done. It contains no editor code.

function Install-VideoEditor {
    $Repo = "pughs-editor/video-editor"
    $Market = "video-editor-kit"
    $Plugin = "video-editor@video-editor-kit"
    $Total = 6
    $Home2 = if ($env:VIDEOEDITOR_HOME) { $env:VIDEOEDITOR_HOME } else { Join-Path $HOME "VideoEditor" }

    function Say($m) { Write-Host $m -ForegroundColor Cyan }
    function Ok($m) { Write-Host "  OK: $m" -ForegroundColor Green }
    function Stop-Here($step, $problem, $todo) {
        Write-Host ""
        Write-Host "Step $step stopped: $problem" -ForegroundColor Yellow
        Write-Host "What to do:" -ForegroundColor Yellow
        foreach ($t in $todo) { Write-Host "  - $t" }
        Write-Host "Then run the same one-line command again. It picks up where it stopped."
    }
    function Refresh-Path {
        $machine = [Environment]::GetEnvironmentVariable("Path", "Machine")
        $user = [Environment]::GetEnvironmentVariable("Path", "User")
        $extra = @("$HOME\.local\bin", "C:\Program Files\Git\cmd", "C:\Program Files\GitHub CLI")
        $env:Path = (@($machine, $user) + $extra | Where-Object { $_ }) -join ";"
    }
    function Have($name) { return [bool](Get-Command $name -ErrorAction SilentlyContinue) }
    # Native commands (gh, claude) can write to stderr. Under $ErrorActionPreference = 'Stop' that becomes a
    # terminating error and kills the installer. These two helpers use the exit code only and never throw.
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
    $ErrorActionPreference = 'Continue'   # the official Claude Code installer used to leave this as Stop
    # Turn on automatic plugin updates for the kit. Claude Code's documented key is "autoUpdate" on the marketplace's
    # entry under "extraKnownMarketplaces" in a settings file. Merges into the user's settings.json, keeps a backup,
    # touches nothing else, and returns $false (changing nothing) if the file cannot be parsed.
    function Enable-AutoUpdate {
        try {
            $dir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME ".claude" }
            $file = Join-Path $dir "settings.json"
            New-Item -ItemType Directory -Force -Path $dir | Out-Null
            $obj = [pscustomobject]@{}
            if (Test-Path $file) {
                $raw = [IO.File]::ReadAllText($file)
                if ($raw.Trim()) { $obj = $raw | ConvertFrom-Json -ErrorAction Stop }
                if (-not (Test-Path "$file.bak-videoeditor")) { Copy-Item $file "$file.bak-videoeditor" }
            }
            if (-not $obj.PSObject.Properties["extraKnownMarketplaces"]) { $obj | Add-Member -NotePropertyName extraKnownMarketplaces -NotePropertyValue ([pscustomobject]@{}) }
            $mk = $obj.extraKnownMarketplaces
            if (-not $mk.PSObject.Properties[$Market]) {
                $mk | Add-Member -NotePropertyName $Market -NotePropertyValue ([pscustomobject]@{ source = [pscustomobject]@{ source = "github"; repo = $Repo } })
            }
            $entry = $mk.PSObject.Properties[$Market].Value
            $entry | Add-Member -NotePropertyName autoUpdate -NotePropertyValue $true -Force
            $json = $obj | ConvertTo-Json -Depth 30
            [IO.File]::WriteAllText($file, $json, (New-Object Text.UTF8Encoding($false)))   # UTF-8 without BOM
            return $true
        } catch { return $false }
    }

    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host "This window is running as administrator. Please close it, open a normal PowerShell (Start menu, type PowerShell, press Enter) and paste the line again." -ForegroundColor Yellow
        return
    }
    # ---- Check this computer BEFORE installing anything (nothing below runs if it fails)
    $os = Get-CimInstance Win32_OperatingSystem
    $cs = Get-CimInstance Win32_ComputerSystem
    $ramGb = [math]::Round($cs.TotalPhysicalMemory / 1GB)
    $checkRoot = if ($env:VIDEOEDITOR_HOME) { $env:VIDEOEDITOR_HOME } else { $HOME }
    $drv = (Split-Path -Qualifier $checkRoot).TrimEnd(':')
    $freeGb = [math]::Round((Get-PSDrive $drv).Free / 1GB, 1)
    $buildNo = [int]$os.BuildNumber
    $problem = $null
    if (-not [Environment]::Is64BitOperatingSystem) { $problem = "This is 32-bit Windows. The Pugh.ai Video Editor needs 64-bit Windows 10 or 11." }
    elseif ([Environment]::OSVersion.Version.Major -lt 10 -or $buildNo -lt 10240) { $problem = "This Windows is too old. The Pugh.ai Video Editor needs Windows 10 or Windows 11 (64-bit)." }
    elseif ($ramGb -lt 8) { $problem = "This computer has $ramGb GB of memory. The Pugh.ai Video Editor needs at least 8 GB." }
    elseif ($freeGb -lt 15) { $problem = "Only $freeGb GB of free disk space on drive ${drv}:. The Pugh.ai Video Editor needs about 15 GB free. Free some space, then run the line again." }
    if ($problem) {
        Write-Host ""
        Write-Host "Cannot install on this computer: $problem" -ForegroundColor Yellow
        Write-Host "Nothing was installed or changed." -ForegroundColor Yellow
        return
    }
    Write-Host "Computer check passed: $ramGb GB memory, $freeGb GB free disk, 64-bit Windows." -ForegroundColor Green
    Write-Host "Tip: plug in your laptop and leave this window open. Setup can take up to 30 minutes. This installer keeps the PC awake while it runs." -ForegroundColor White

    if (-not (Have "winget")) {
        Write-Host "Windows Package Manager (winget) was not found. Open the Microsoft Store, search for 'App Installer', click Update or Get, then run the line again." -ForegroundColor Yellow
        return
    }
    Refresh-Path
    Write-Host ""
    Write-Host "Pugh.ai Video Editor installer. $Total short steps. You can stop any time with Ctrl+C." -ForegroundColor White

    # ---- Step 1: Git and GitHub CLI
    Say "Step 1 of ${Total}: checking Git and the GitHub tool..."
    foreach ($app in @(@{ cmd = "git"; id = "Git.Git"; name = "Git" }, @{ cmd = "gh"; id = "GitHub.cli"; name = "GitHub CLI" })) {
        if (Have $app.cmd) { Ok "$($app.name) is already installed"; continue }
        Say "  Installing $($app.name). If Windows asks for permission, read it and click Yes."
        winget install --id $app.id -e --accept-source-agreements --accept-package-agreements | Out-Host
        Refresh-Path
        if (-not (Have $app.cmd)) {
            Stop-Here 1 "$($app.name) did not install." @("Close this window, open a new PowerShell, and run the line again.", "If it still fails, type: winget install --id $($app.id) -e   and tell the seller what you see.")
            return
        }
        Ok "$($app.name) installed"
    }

    # ---- Step 2: Claude Code
    Say "Step 2 of ${Total}: checking Claude Code..."
    if (Have "claude") { Ok "Claude Code is already installed" }
    else {
        Say "  Installing Claude Code (official installer)..."
        # Run it in its own PowerShell process so it cannot change this session's settings (it sets ErrorActionPreference to Stop).
        try { powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://claude.ai/install.ps1 | iex" | Out-Host } catch { }
        $ErrorActionPreference = 'Continue'
        Refresh-Path
        if (-not (Have "claude")) {
            Stop-Here 2 "Claude Code did not install." @("Close this window and open a new PowerShell.", "Type: irm https://claude.ai/install.ps1 | iex", "Then run the Pugh.ai Video Editor line again.")
            return
        }
        Ok "Claude Code installed"
    }

    # Make sure a NEW PowerShell can find claude (the official installer normally does this; this is a safety net).
    $lb = "$HOME\.local\bin"
    if ((Test-Path "$lb\claude.exe") -and (([Environment]::GetEnvironmentVariable("Path", "User") -split ";") -notcontains $lb)) {
        [Environment]::SetEnvironmentVariable("Path", (([Environment]::GetEnvironmentVariable("Path", "User"), $lb) | Where-Object { $_ }) -join ";", "User")
        Ok "added $lb to your PATH"
    }

    # ---- Step 3: GitHub sign-in
    Say "Step 3 of ${Total}: GitHub sign-in..."
    if ((Native-Code { gh auth status }) -eq 0) { Ok "already signed in to GitHub" }
    else {
        Say "  A browser window will open. Copy the code shown here, paste it on the page, and click Authorize."
        try { gh auth login -h github.com -p https -w } catch { }
        if ((Native-Code { gh auth status }) -ne 0) {
            Stop-Here 3 "GitHub sign-in did not finish." @("Type: gh auth login   and choose GitHub.com, HTTPS, 'Login with a web browser'.")
            return
        }
        Ok "signed in"
    }
    [void](Native-Code { gh auth setup-git })

    # ---- Step 4: access to the private kit
    Say "Step 4 of ${Total}: checking you can see the Pugh.ai Video Editor kit..."
    if ((Native-Code { gh repo view $Repo --json name }) -ne 0) {
        Stop-Here 4 "your GitHub account cannot see the kit yet." @("Accept your GitHub invite email first (search your inbox for an invitation from pughs-editor).", "Make sure you signed in with the same GitHub account the invite was sent to.", "If you cannot find the email, tell the seller your GitHub username.")
        return
    }
    Ok "access confirmed"

    # ---- Step 5: workspace folder and plugin
    # Tested with a brand-new Claude config that was never signed in: "plugin marketplace add" and
    # "plugin install" both work without a Claude sign-in. Sign-in happens when Claude starts in Step 6.
    Say "Step 5 of ${Total}: installing the Pugh.ai Video Editor plugin..."
    New-Item -ItemType Directory -Force -Path $Home2 | Out-Null
    Set-Location $Home2
    $markets = Native-Text { claude plugin marketplace list }
    if ($markets -match $Market) { Ok "kit source already added" }
    else {
        $code = Native-Code { claude plugin marketplace add $Repo | Out-Host }
        if ($code -ne 0) {
            Stop-Here 5 "could not add the kit source." @("Type: gh auth status   to check you are signed in.", "If you see an SSH or permission error, type: setx CLAUDE_CODE_PLUGIN_PREFER_HTTPS 1   then open a new PowerShell and run the line again.")
            return
        }
    }
    $installed = Native-Text { claude plugin list }
    if ($installed -match "video-editor@") { Ok "plugin already installed" }
    else {
        $code = Native-Code { claude plugin install $Plugin | Out-Host }
        if ($code -ne 0) {
            Stop-Here 5 "could not install the plugin." @("Run the line again. If it fails twice, tell the seller exactly what you see.")
            return
        }
    }
    if (Enable-AutoUpdate) { Ok "Updates install automatically." }
    else { Write-Host "  Note: could not turn on automatic updates. Later, in Claude Code, type /plugin, open Marketplaces, choose video-editor-kit, then Enable auto-update. Until then, /video-editor:editor-update gets new versions." -ForegroundColor Yellow }
    Ok "workspace folder: $Home2"

    # ---- Step 6: start setup
    Say "Step 6 of ${Total}: starting Claude. It will set up the rest, one step at a time."
    Write-Host ""
    Write-Host "Next time, to open the editor:" -ForegroundColor White
    Write-Host "  cd `$HOME\VideoEditor"
    Write-Host "  claude -c"
    Write-Host ""
    if ($env:INSTALL_NO_LAUNCH) { Ok "test mode: not starting Claude"; return }
    Write-Host "  If Claude asks you to sign in, click Authorize in the browser."
    claude "/video-editor:editor-setup"
}

# Keep Windows awake while the installer (and the Claude setup it starts) runs. No admin, changes no setting;
# the request is cleared when this finishes.
try {
    Add-Type -Namespace Win32 -Name Power -MemberDefinition '[DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint f);' -ErrorAction Stop
    [void][Win32.Power]::SetThreadExecutionState([uint32]2147483649)   # ES_CONTINUOUS | ES_SYSTEM_REQUIRED
} catch { }
try { Install-VideoEditor }
finally { try { [void][Win32.Power]::SetThreadExecutionState([uint32]2147483648) } catch { } }
