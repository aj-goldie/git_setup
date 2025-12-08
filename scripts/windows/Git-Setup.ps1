#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Sets up symlinks from Windows system locations to git repo config files.
.DESCRIPTION
    IDEMPOTENT & SAFE - can be run multiple times without data loss.
    
    This script:
    1. Checks if everything is already configured correctly (exits early if so)
    2. Moves config files from system locations TO the repo (only if not already done)
    3. Creates symlinks FROM system locations TO repo files
    4. NEVER deletes files in the repo directory
    
    Config files handled:
    - .gitconfig, .gitconfig-personal, .gitconfig-work (user home)
    - gitconfig-system (Program Files\Git\etc)
    - Microsoft.PowerShell_profile.ps1 (Documents\PowerShell)
    - .gitattributes_global, .githooks (shared configs)
    - nbstripout-safe.cmd (~\.local\bin) - fault-tolerant notebook filter
#>

$ErrorActionPreference = "Stop"

# === CONFIGURATION ===
$repoRoot = "C:\Users\AlexGoldsmith\Documents\Software-Personal\git_setup"
$repoDir = "$repoRoot\configs\windows-work-laptop"
$sharedDir = "$repoRoot\configs\shared"
$sharedScriptsDir = "$repoRoot\scripts\shared"

# Files that should be MOVED to repo, then symlinked back
$configFiles = @(
    @{System = "C:\Program Files\Git\etc\gitconfig"; Repo = "$repoDir\gitconfig-system" },
    @{System = "$env:USERPROFILE\.gitconfig"; Repo = "$repoDir\.gitconfig" },
    @{System = "$env:USERPROFILE\.gitconfig-personal"; Repo = "$repoDir\.gitconfig-personal" },
    @{System = "$env:USERPROFILE\.gitconfig-work"; Repo = "$repoDir\.gitconfig-work" },
    @{System = "$env:USERPROFILE\Documents\PowerShell\Microsoft.PowerShell_profile.ps1"; Repo = "$repoDir\Microsoft.PowerShell_profile.ps1" }
)

# Shared configs: symlink only (files already exist in repo)
$sharedLinks = @(
    @{System = "$env:USERPROFILE\.gitattributes_global"; Repo = "$sharedDir\.gitattributes_global"; Type = "File" },
    @{System = "$env:USERPROFILE\.githooks"; Repo = "$sharedDir\githooks"; Type = "Directory" }
)

# Executable scripts: ~/.local/bin -> Repo (these go in PATH)
$binScripts = @(
    @{System = "$env:USERPROFILE\.local\bin\nbstripout-safe.cmd"; Repo = "$sharedScriptsDir\nbstripout-safe.cmd" }
)

# === HELPER FUNCTIONS ===
function Test-IsSymlink($path) {
    if (-not (Test-Path $path)) { return $false }
    $item = Get-Item $path -Force
    return ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
}

function Get-SymlinkTarget($path) {
    if (-not (Test-IsSymlink $path)) { return $null }
    return (Get-Item $path -Force).Target
}

function Write-Status($message, $status) {
    $color = switch ($status) {
        "OK" { "Green" }
        "ACTION" { "Yellow" }
        "ERROR" { "Red" }
        "INFO" { "Cyan" }
        default { "White" }
    }
    Write-Host "  [$status] " -ForegroundColor $color -NoNewline
    Write-Host $message
}

# === PRE-FLIGHT CHECKS ===
Write-Host "`n=== SETUP WINDOWS SYMLINKS (Safe & Idempotent) ===" -ForegroundColor Cyan
Write-Host ""

# Check repo directory exists
if (-not (Test-Path $repoDir)) {
    Write-Host "ERROR: Repo directory not found: $repoDir" -ForegroundColor Red
    Write-Host "Press any key to exit..." -ForegroundColor DarkYellow
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 1
}

# Ensure ~/.local/bin exists (for executable scripts)
$localBinDir = "$env:USERPROFILE\.local\bin"
if (-not (Test-Path $localBinDir)) {
    New-Item -ItemType Directory -Path $localBinDir -Force | Out-Null
}

# === PHASE 0: PREREQUISITES (uv, Python, nbstripout-fast) ===
Write-Host "[Phase 0] Checking prerequisites..." -ForegroundColor Yellow
Write-Host ""

$profilePath = "$env:USERPROFILE\Documents\PowerShell\Microsoft.PowerShell_profile.ps1"
$pathLine = @'

# Ensure ~/.local/bin is first on PATH (added by Git-Setup)
$localBin = "$env:USERPROFILE\.local\bin"
if (Test-Path $localBin) {
    if ($env:PATH -notlike "*$localBin*") {
        $env:PATH = "$localBin;$env:PATH"
    } elseif (-not $env:PATH.StartsWith($localBin)) {
        # Remove from current position and prepend
        $env:PATH = "$localBin;" + ($env:PATH -replace [regex]::Escape("$localBin;"), "" -replace [regex]::Escape(";$localBin"), "")
    }
}
'@

# --- Step 1: Check/install uv ---
$uvCmd = Get-Command uv -ErrorAction SilentlyContinue
if ($uvCmd) {
    Write-Status "uv is installed" "OK"
} else {
    Write-Host "  Installing uv..." -ForegroundColor Cyan
    try {
        Invoke-RestMethod https://astral.sh/uv/install.ps1 | Invoke-Expression
        # Refresh PATH to pick up uv
        $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "User") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "Machine")
        Write-Status "uv installed" "OK"
    } catch {
        Write-Status "Failed to install uv" "ERROR"
        Write-Host "Press any key to exit..." -ForegroundColor DarkYellow
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        exit 1
    }
}

# --- Step 2: Check/fix PATH order - ~/.local/bin should be first ---
$pathEntries = $env:PATH -split ';'
$firstPathEntry = $pathEntries[0]
if ($firstPathEntry -eq $localBinDir) {
    Write-Status "~\.local\bin is first on PATH" "OK"
} else {
    Write-Status "~\.local\bin is NOT first on PATH - fixing..." "ACTION"
    
    # Check if PATH fix already exists in profile
    $profileContent = ""
    if (Test-Path $profilePath) {
        $profileContent = Get-Content $profilePath -Raw -ErrorAction SilentlyContinue
    }
    
    if ($profileContent -notmatch '\.local\\bin.*first on PATH') {
        Write-Host "  Adding PATH fix to PowerShell profile..." -ForegroundColor Cyan
        # Ensure profile directory exists
        $profileDir = Split-Path $profilePath -Parent
        if (-not (Test-Path $profileDir)) {
            New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
        }
        Add-Content -Path $profilePath -Value $pathLine
    }
    
    # Apply PATH fix NOW for this session
    Write-Host "  Applying PATH fix to current session..." -ForegroundColor Cyan
    $env:PATH = "$localBinDir;$env:PATH"
    Write-Status "PATH updated - ~\.local\bin is now first" "OK"
}

# --- Step 3: Install Python 3.12 via uv ---
Write-Host "  Ensuring Python 3.12 is installed via uv..." -ForegroundColor Cyan
$uvOutput = & uv python install 3.12 --default --preview 2>&1 | Out-String
if ($uvOutput -match "already") {
    Write-Status "Python 3.12 already installed" "OK"
} else {
    Write-Status "Python 3.12 installed" "OK"
}

# --- Step 4: Check python executables exist (AFTER PATH is correct) ---
$pythonPath = "$localBinDir\python.exe"
$python3Path = "$localBinDir\python3.exe"

if (Test-Path $pythonPath) {
    Write-Status "~\.local\bin\python.exe exists" "OK"
} else {
    Write-Status "~\.local\bin\python.exe not found (uv may use different location)" "INFO"
}

if (Test-Path $python3Path) {
    Write-Status "~\.local\bin\python3.exe exists" "OK"
} else {
    Write-Status "~\.local\bin\python3.exe not found (uv may use different location)" "INFO"
}

# --- Step 5: Check/install nbstripout-fast via uv tool ---
$nbstripoutPath = "$localBinDir\nbstripout-fast.exe"
if (Test-Path $nbstripoutPath) {
    Write-Status "nbstripout-fast is installed" "OK"
} else {
    Write-Host "  Installing nbstripout-fast via uv..." -ForegroundColor Cyan
    try {
        & uv tool install nbstripout-fast 2>&1 | Out-Null
        Write-Status "nbstripout-fast installed" "OK"
    } catch {
        Write-Status "Failed to install nbstripout-fast" "ERROR"
        Write-Host "Press any key to exit..." -ForegroundColor DarkYellow
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        exit 1
    }
}

Write-Host ""

# === PHASE 1: ANALYZE CURRENT STATE ===
Write-Host "[Phase 1] Analyzing current state..." -ForegroundColor Yellow
Write-Host ""

$needsAction = $false
$actions = @()

foreach ($f in $configFiles) {
    $sysExists = Test-Path $f.System
    $repoExists = Test-Path $f.Repo
    $sysIsSymlink = Test-IsSymlink $f.System
    $symlinkTarget = Get-SymlinkTarget $f.System
    $name = Split-Path $f.System -Leaf
    
    if ($sysIsSymlink -and $symlinkTarget -eq $f.Repo) {
        # Perfect - already set up correctly
        Write-Status "$name - symlink points to repo" "OK"
    }
    elseif ($sysIsSymlink -and $symlinkTarget -ne $f.Repo) {
        # Symlink exists but points somewhere else - ERROR
        Write-Status "$name - symlink points to WRONG target: $symlinkTarget" "ERROR"
        Write-Host "       Expected: $($f.Repo)" -ForegroundColor DarkGray
        Write-Host "`nERROR: Cannot proceed - symlink points to unexpected location." -ForegroundColor Red
        Write-Host "Please manually verify and fix this before running again." -ForegroundColor Red
        Write-Host "Press any key to exit..." -ForegroundColor DarkYellow
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        exit 1
    }
    elseif ($sysExists -and -not $sysIsSymlink -and $repoExists) {
        # Both exist as real files - need to decide which to keep
        Write-Status "$name - EXISTS in BOTH locations (real files)" "ERROR"
        Write-Host "       System: $($f.System)" -ForegroundColor DarkGray
        Write-Host "       Repo:   $($f.Repo)" -ForegroundColor DarkGray
        Write-Host "`nERROR: Cannot proceed - file exists in both locations." -ForegroundColor Red
        Write-Host "Please manually delete one copy, then run again." -ForegroundColor Red
        Write-Host "Press any key to exit..." -ForegroundColor DarkYellow
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        exit 1
    }
    elseif ($sysExists -and -not $sysIsSymlink -and -not $repoExists) {
        # System file exists, repo doesn't - needs to be moved
        Write-Status "$name - needs MOVE to repo + symlink" "ACTION"
        $needsAction = $true
        $actions += @{Type = "MOVE"; Config = $f }
    }
    elseif (-not $sysExists -and $repoExists) {
        # Repo file exists, system doesn't - just needs symlink
        Write-Status "$name - needs SYMLINK (repo file exists)" "ACTION"
        $needsAction = $true
        $actions += @{Type = "SYMLINK"; Config = $f }
    }
    elseif (-not $sysExists -and -not $repoExists) {
        # Neither exists - warning but not fatal
        Write-Status "$name - MISSING from both locations" "INFO"
    }
}

# Check shared configs
Write-Host ""
foreach ($s in $sharedLinks) {
    $sysExists = Test-Path $s.System
    $repoExists = Test-Path $s.Repo
    $sysIsSymlink = Test-IsSymlink $s.System
    $symlinkTarget = Get-SymlinkTarget $s.System
    $name = Split-Path $s.System -Leaf
    
    if (-not $repoExists) {
        Write-Status "$name - MISSING from repo (shared config)" "ERROR"
        Write-Host "       Expected: $($s.Repo)" -ForegroundColor DarkGray
        Write-Host "`nERROR: Shared config missing from repo." -ForegroundColor Red
        Write-Host "Press any key to exit..." -ForegroundColor DarkYellow
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        exit 1
    }
    elseif ($sysIsSymlink -and ($symlinkTarget -eq $s.Repo)) {
        Write-Status "$name - symlink points to repo" "OK"
    }
    elseif ($sysIsSymlink -and ($symlinkTarget -ne $s.Repo)) {
        Write-Status "$name - symlink points to WRONG target" "ERROR"
        Write-Host "       Current:  $symlinkTarget" -ForegroundColor DarkGray
        Write-Host "       Expected: $($s.Repo)" -ForegroundColor DarkGray
        Write-Host "`nERROR: Shared config symlink points to wrong location." -ForegroundColor Red
        Write-Host "Press any key to exit..." -ForegroundColor DarkYellow
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        exit 1
    }
    elseif ($sysExists -and -not $sysIsSymlink) {
        Write-Status "$name - needs REPLACE with symlink" "ACTION"
        $needsAction = $true
        $actions += @{Type = "SHARED"; Config = $s }
    }
    elseif (-not $sysExists) {
        Write-Status "$name - needs SYMLINK" "ACTION"
        $needsAction = $true
        $actions += @{Type = "SHARED"; Config = $s }
    }
}

# Check bin scripts (~/.local/bin)
Write-Host ""
foreach ($b in $binScripts) {
    $sysExists = Test-Path $b.System
    $repoExists = Test-Path $b.Repo
    $sysIsSymlink = Test-IsSymlink $b.System
    $symlinkTarget = Get-SymlinkTarget $b.System
    $name = Split-Path $b.System -Leaf
    
    if (-not $repoExists) {
        Write-Status "$name - MISSING from repo (bin script)" "ERROR"
        Write-Host "       Expected: $($b.Repo)" -ForegroundColor DarkGray
        Write-Host "`nERROR: Bin script missing from repo." -ForegroundColor Red
        Write-Host "Press any key to exit..." -ForegroundColor DarkYellow
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        exit 1
    }
    elseif ($sysIsSymlink -and ($symlinkTarget -eq $b.Repo)) {
        Write-Status "$name - symlink points to repo" "OK"
    }
    elseif ($sysIsSymlink -and ($symlinkTarget -ne $b.Repo)) {
        Write-Status "$name - symlink points to WRONG target, will RELINK" "ACTION"
        Write-Host "       Current:  $symlinkTarget" -ForegroundColor DarkGray
        Write-Host "       Expected: $($b.Repo)" -ForegroundColor DarkGray
        $needsAction = $true
        $actions += @{Type = "RELINK_BIN"; Config = $b }
    }
    elseif ($sysExists -and -not $sysIsSymlink) {
        Write-Status "$name - needs REPLACE with symlink" "ACTION"
        $needsAction = $true
        $actions += @{Type = "BIN"; Config = $b }
    }
    elseif (-not $sysExists) {
        Write-Status "$name - needs SYMLINK" "ACTION"
        $needsAction = $true
        $actions += @{Type = "BIN"; Config = $b }
    }
}

# === PHASE 2: EXECUTE OR EXIT ===
Write-Host ""

if (-not $needsAction) {
    Write-Host "All symlinks are already configured correctly!" -ForegroundColor Green
    Write-Host "Nothing to do." -ForegroundColor Green
    Write-Host "`nPress any key to exit..." -ForegroundColor DarkYellow
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 0
}

Write-Host "[Phase 2] Executing $($actions.Count) action(s)..." -ForegroundColor Yellow
Write-Host ""

# Create backup directory
$backup = "$env:TEMP\gitconfig-backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
New-Item -ItemType Directory -Path $backup -Force | Out-Null
Write-Host "  Backup directory: $backup" -ForegroundColor DarkGray
Write-Host ""

foreach ($action in $actions) {
    $name = Split-Path $action.Config.System -Leaf
    
    switch ($action.Type) {
        "MOVE" {
            # Backup, move to repo, create symlink
            Write-Host "  Moving $name to repo..." -ForegroundColor Cyan
            Copy-Item $action.Config.System "$backup\$name" -Force
            Move-Item $action.Config.System $action.Config.Repo -Force
            New-Item -ItemType SymbolicLink -Path $action.Config.System -Target $action.Config.Repo -Force | Out-Null
            Write-Host "    Backed up, moved, symlinked" -ForegroundColor Green
        }
        "SYMLINK" {
            # Just create symlink
            Write-Host "  Creating symlink for $name..." -ForegroundColor Cyan
            New-Item -ItemType SymbolicLink -Path $action.Config.System -Target $action.Config.Repo -Force | Out-Null
            Write-Host "    Symlinked" -ForegroundColor Green
        }
        "SHARED" {
            # Backup if exists, remove, create symlink/junction
            Write-Host "  Setting up shared config $name..." -ForegroundColor Cyan
            if (Test-Path $action.Config.System) {
                Copy-Item $action.Config.System "$backup\$name" -Force -Recurse
                Remove-Item $action.Config.System -Force -Recurse
            }
            if ($action.Config.Type -eq "Directory") {
                cmd /c mklink /J "$($action.Config.System)" "$($action.Config.Repo)" | Out-Null
            }
            else {
                New-Item -ItemType SymbolicLink -Path $action.Config.System -Target $action.Config.Repo -Force | Out-Null
            }
            Write-Host "    Symlinked" -ForegroundColor Green
        }
        "BIN" {
            # Backup if exists, remove, create symlink
            Write-Host "  Setting up bin script $name..." -ForegroundColor Cyan
            if (Test-Path $action.Config.System) {
                Copy-Item $action.Config.System "$backup\$name" -Force
                Remove-Item $action.Config.System -Force
            }
            New-Item -ItemType SymbolicLink -Path $action.Config.System -Target $action.Config.Repo -Force | Out-Null
            Write-Host "    Symlinked" -ForegroundColor Green
        }
        "RELINK_BIN" {
            # Remove old symlink, create new one
            Write-Host "  Fixing symlink for $name..." -ForegroundColor Cyan
            $oldTarget = Get-SymlinkTarget $action.Config.System
            Add-Content "$backup\relinked.txt" "$($action.Config.System) -> $oldTarget"
            Remove-Item $action.Config.System -Force
            New-Item -ItemType SymbolicLink -Path $action.Config.System -Target $action.Config.Repo -Force | Out-Null
            Write-Host "    Relinked (old target logged)" -ForegroundColor Green
        }
    }
}

# === PHASE 3: VERIFICATION ===
Write-Host ""
Write-Host "[Phase 3] Verification..." -ForegroundColor Yellow
Write-Host ""

$allGood = $true

foreach ($f in $configFiles) {
    $name = Split-Path $f.System -Leaf
    if (Test-IsSymlink $f.System) {
        $target = Get-SymlinkTarget $f.System
        if ($target -eq $f.Repo) {
            Write-Status "$name -> repo" "OK"
        }
        else {
            Write-Status "$name -> WRONG TARGET" "ERROR"
            $allGood = $false
        }
    }
    elseif (-not (Test-Path $f.System) -and -not (Test-Path $f.Repo)) {
        Write-Status "$name - not configured (missing)" "INFO"
    }
    else {
        Write-Status "$name - NOT a symlink" "ERROR"
        $allGood = $false
    }
}

foreach ($s in $sharedLinks) {
    $name = Split-Path $s.System -Leaf
    if (Test-IsSymlink $s.System) {
        $target = Get-SymlinkTarget $s.System
        if ($target -eq $s.Repo) {
            Write-Status "$name -> repo" "OK"
        }
        else {
            Write-Status "$name -> WRONG TARGET" "ERROR"
            $allGood = $false
        }
    }
    else {
        Write-Status "$name - NOT a symlink" "ERROR"
        $allGood = $false
    }
}

foreach ($b in $binScripts) {
    $name = Split-Path $b.System -Leaf
    if (Test-IsSymlink $b.System) {
        $target = Get-SymlinkTarget $b.System
        if ($target -eq $b.Repo) {
            Write-Status "$name -> repo" "OK"
        }
        else {
            Write-Status "$name -> WRONG TARGET" "ERROR"
            $allGood = $false
        }
    }
    else {
        Write-Status "$name - NOT a symlink" "ERROR"
        $allGood = $false
    }
}

Write-Host ""
if ($allGood) {
    Write-Host "Setup complete!" -ForegroundColor Green
}
else {
    Write-Host "Setup completed with errors - please review above." -ForegroundColor Red
}
Write-Host "Backup saved to: $backup" -ForegroundColor DarkGray
Write-Host "`nPress any key to exit..." -ForegroundColor DarkYellow
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
