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

    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host "This window is running as administrator. Please close it, open a normal PowerShell (Start menu, type PowerShell, press Enter) and paste the line again." -ForegroundColor Yellow
        return
    }
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
        try { Invoke-RestMethod https://claude.ai/install.ps1 | Invoke-Expression } catch { }
        Refresh-Path
        if (-not (Have "claude")) {
            Stop-Here 2 "Claude Code did not install." @("Close this window and open a new PowerShell.", "Type: irm https://claude.ai/install.ps1 | iex", "Then run the Pugh.ai Video Editor line again.")
            return
        }
        Ok "Claude Code installed"
    }

    # ---- Step 3: GitHub sign-in
    Say "Step 3 of ${Total}: GitHub sign-in..."
    gh auth status *> $null
    if ($LASTEXITCODE -eq 0) { Ok "already signed in to GitHub" }
    else {
        Say "  A browser window will open. Copy the code shown here, paste it on the page, and click Authorize."
        gh auth login -h github.com -p https -w
        gh auth status *> $null
        if ($LASTEXITCODE -ne 0) {
            Stop-Here 3 "GitHub sign-in did not finish." @("Type: gh auth login   and choose GitHub.com, HTTPS, 'Login with a web browser'.")
            return
        }
        Ok "signed in"
    }
    gh auth setup-git | Out-Null

    # ---- Step 4: access to the private kit
    Say "Step 4 of ${Total}: checking you can see the Pugh.ai Video Editor kit..."
    gh repo view $Repo --json name *> $null
    if ($LASTEXITCODE -ne 0) {
        Stop-Here 4 "your GitHub account cannot see the kit yet." @("Accept your GitHub invite email first (search your inbox for an invitation from pughs-editor).", "Make sure you signed in with the same GitHub account the invite was sent to.", "If you cannot find the email, tell the seller your GitHub username.")
        return
    }
    Ok "access confirmed"

    # ---- Step 5: workspace folder and plugin
    Say "Step 5 of ${Total}: installing the Pugh.ai Video Editor plugin..."
    New-Item -ItemType Directory -Force -Path $Home2 | Out-Null
    Set-Location $Home2
    $markets = (claude plugin marketplace list 2>$null) -join "`n"
    if ($markets -match $Market) { Ok "kit source already added" }
    else {
        claude plugin marketplace add $Repo | Out-Host
        if ($LASTEXITCODE -ne 0) {
            Stop-Here 5 "could not add the kit source." @("Type: gh auth status   to check you are signed in.", "If you see an SSH or permission error, type: setx CLAUDE_CODE_PLUGIN_PREFER_HTTPS 1   then open a new PowerShell and run the line again.")
            return
        }
    }
    $installed = (claude plugin list 2>$null) -join "`n"
    if ($installed -match "video-editor@") { Ok "plugin already installed" }
    else {
        claude plugin install $Plugin | Out-Host
        if ($LASTEXITCODE -ne 0) {
            Stop-Here 5 "could not install the plugin." @("Run the line again. If it fails twice, tell the seller exactly what you see.")
            return
        }
    }
    Ok "workspace folder: $Home2"

    # ---- Step 6: start setup
    Say "Step 6 of ${Total}: starting Claude. It will set up the rest, one step at a time."
    if ($env:INSTALL_NO_LAUNCH) { Ok "test mode: not starting Claude"; return }
    Write-Host "  If Claude asks you to sign in, click Authorize in the browser."
    claude "/video-editor:editor-setup"
}

Install-VideoEditor
