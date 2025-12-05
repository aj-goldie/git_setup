#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Migrates Windows config files to git repo and creates symlinks back to original locations.
.DESCRIPTION
    1. Backs up all files to temp folder
    2. Deletes existing repo files
    3. Moves system config files to repo
    4. Creates symlinks from original locations to repo
#>

$ErrorActionPreference = "Stop"

$repoDir = "C:\Users\AlexGoldsmith\Documents\Software-Personal\git_setup\configs\windows-work-laptop"
$backup = "$env:TEMP\gitconfig-backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

$moves = @(
    @{From = "C:\Program Files\Git\etc\gitconfig"; To = "$repoDir\gitconfig-system" },
    @{From = "C:\Users\AlexGoldsmith\.gitconfig"; To = "$repoDir\.gitconfig" },
    @{From = "C:\Users\AlexGoldsmith\.gitconfig-personal"; To = "$repoDir\.gitconfig-personal" },
    @{From = "C:\Users\AlexGoldsmith\.gitconfig-work"; To = "$repoDir\.gitconfig-work" },
    @{From = "C:\Users\AlexGoldsmith\Documents\PowerShell\Microsoft.PowerShell_profile.ps1"; To = "$repoDir\Microsoft.PowerShell_profile.ps1" }
)

Write-Host "=== SETUP WINDOWS SYMLINKS ===" -ForegroundColor Cyan
Write-Host ""

# Step 1: Backup
Write-Host "[1/4] Creating backup at $backup" -ForegroundColor Yellow
New-Item -ItemType Directory -Path $backup -Force | Out-Null
New-Item -ItemType Directory -Path "$backup\repo-originals" -Force | Out-Null

foreach ($m in $moves) {
    if (Test-Path $m.From) {
        Copy-Item $m.From "$backup\$(Split-Path $m.From -Leaf)" -Force
        Write-Host "  Backed up: $(Split-Path $m.From -Leaf)" -ForegroundColor DarkGray
    }
}
Get-ChildItem $repoDir -File | Copy-Item -Destination "$backup\repo-originals\" -Force
Write-Host "  Backed up repo originals" -ForegroundColor DarkGray

# Step 2: Delete repo files
Write-Host "[2/4] Deleting repo files..." -ForegroundColor Yellow
Get-ChildItem $repoDir -File | ForEach-Object {
    Remove-Item $_.FullName -Force
    Write-Host "  Deleted: $($_.Name)" -ForegroundColor DarkGray
}

# Step 3: Move system files to repo
Write-Host "[3/4] Moving system files to repo..." -ForegroundColor Yellow
foreach ($m in $moves) {
    Move-Item $m.From $m.To -Force
    Write-Host "  Moved: $(Split-Path $m.From -Leaf)" -ForegroundColor Green
}

# Step 4: Create symlinks
Write-Host "[4/4] Creating symlinks..." -ForegroundColor Yellow
foreach ($m in $moves) {
    New-Item -ItemType SymbolicLink -Path $m.From -Target $m.To -Force | Out-Null
    Write-Host "  Symlink: $(Split-Path $m.From -Leaf)" -ForegroundColor Magenta
}

# Verification
Write-Host ""
Write-Host "=== VERIFICATION ===" -ForegroundColor Cyan
foreach ($m in $moves) {
    $item = Get-Item $m.From
    $isLink = ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
    $target = if ($isLink) { $item.Target } else { "NOT A LINK!" }
    $color = if ($isLink) { "Green" } else { "Red" }
    Write-Host "  $($m.From)" -ForegroundColor $color
    Write-Host "    -> $target" -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "Backup saved to: $backup" -ForegroundColor Green
Write-Host ""
Write-Host "Press any key to exit..." -ForegroundColor DarkYellow
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

