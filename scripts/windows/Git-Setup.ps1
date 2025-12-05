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
    - .gitattributes_nbstripout, .githooks (shared configs)
#>

$ErrorActionPreference = "Stop"

# === CONFIGURATION ===
$repoRoot = "C:\Users\AlexGoldsmith\Documents\Software-Personal\git_setup"
$repoDir = "$repoRoot\configs\windows-work-laptop"
$sharedDir = "$repoRoot\configs\shared"

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
    @{System = "$env:USERPROFILE\.gitattributes_nbstripout"; Repo = "$sharedDir\.gitattributes_nbstripout"; Type = "File" },
    @{System = "$env:USERPROFILE\.githooks"; Repo = "$sharedDir\githooks"; Type = "Directory" }
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
