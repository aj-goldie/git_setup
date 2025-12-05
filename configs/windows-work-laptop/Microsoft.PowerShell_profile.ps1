
Import-Module posh-git

# Add toggle-default-shell alias
$scriptPath = "$env:USERPROFILE\toggle-shell.ps1"
if (!(Test-Path $scriptPath)) {
    Copy-Item "toggle-shell.ps1" $scriptPath -Force
}
Set-Alias -Name toggle-default-shell -Value $scriptPath

# Optional: Add a function wrapper if you prefer
function Toggle-DefaultShell {
    & $scriptPath
} 
# Import the Chocolatey Profile that contains the necessary code to enable
# tab-completions to function for `choco`.
# Be aware that if you are missing these lines from your profile, tab completion
# for `choco` will not function.
# See https://ch0.co/tab-completion for details.
$ChocolateyProfile = "$env:ChocolateyInstall\helpers\chocolateyProfile.psm1"
if (Test-Path($ChocolateyProfile)) {
  Import-Module "$ChocolateyProfile"
}


function vars { rundll32.exe sysdm.cpl,EditEnvironmentVariables }

function start-server { 
    Set-Location C:\Users\AlexGoldsmith\Documents\Software\tablegpt_agent
    uv run src\tablegpt_agent_bai\start_server.py
}


function clonepart {
    [CmdletBinding()]
    param (
        [string]$GithubUrl,
        [string]$LocalRepoDirName,
        [string[]]$CheckoutDirs
    )

    # Interactive prompts for missing parameters
    if (-not $GithubUrl) {
        $GithubUrl = Read-Host "Enter the GitHub repository URL"
    }
    if (-not $LocalRepoDirName) {
        $LocalRepoDirName = Read-Host "Enter the local directory name for the repo"
    }
    if (-not $CheckoutDirs) {
        $dirs = Read-Host "Enter the directories/files to checkout (comma-separated)"
        $CheckoutDirs = $dirs -split "," | ForEach-Object { $_.Trim() }
    }

    # Find the default branch name using git ls-remote
    $defaultBranch = & git ls-remote --symref $GithubUrl HEAD 2>$null | Select-String 'ref: refs/heads/' | ForEach-Object {
        ($_ -split 'refs/heads/')[1] -replace '\s+HEAD',''
    }

    if (-not $defaultBranch) {
        Write-Error "Could not determine default branch for $GithubUrl"
        return
    }

    $scriptPath = "C:\Users\AlexGoldsmith\personal\ai_utils\tools\pwsh\partial_clone.ps1"

    $scriptParameters = @{
        GithubUrl        = $GithubUrl
        LocalRepoDirName = $LocalRepoDirName
        CheckoutDirs     = $CheckoutDirs
        BranchName       = $defaultBranch
    }

    if (Test-Path $scriptPath) {
        & $scriptPath @scriptParameters
    }
    else {
        Write-Error "The script at '$scriptPath' was not found. Please check the path in the clonepart function."
    }
}



function template {
    param(
        [string]$FileName,
        [ValidateSet('claims','cobra','fmla')]$Type='claims'
    )
    $src  = 'C:\Users\AlexGoldsmith\Documents\Software\sf_api\src\sf_api\clean_and_stage\cleaning_scripts\templates\template.ipynb'
    $base = "C:\Users\AlexGoldsmith\Documents\Software\sf_api\src\sf_api\clean_and_stage\cleaning_scripts\$Type"
    New-Item -ItemType Directory -Path $base -Force | Out-Null
    $dest = "$base\$FileName.ipynb"
    for($i=1; Test-Path $dest; $i++){ $dest = "$base\${FileName}_$i.ipynb" }
    Copy-Item $src $dest -Force
    Start-Process 'cursor' -ArgumentList '-r', $dest -WindowStyle Hidden
}



# Load the Gem script (dot-source it to make functions available)
# IMPORTANT: Replace 'C:\Scripts\Gem.ps1' with the actual full path to YOUR Gem.ps1 script
. "C:\Users\AlexGoldsmith\personal\ai_utils\tools\pwsh\gem\Gem.ps1"

# Set the alias 'sp' to call the 'Gem' function
Set-Alias -Name sp -Value Gem -Description 'Sync project dir (excludes node_modules, docs, root .git/.cursor, most root files) for Gemini' -Force

function cdd {
    <#
    .SYNOPSIS
    Changes to the specified directory and lists its contents.
    
    .DESCRIPTION
    The cdd function combines Set-Location (cd) with Get-ChildItem (dir/ls) to change
    to a directory and immediately show its contents.
    
    .PARAMETER Path
    The path of the directory to navigate to.
    
    .EXAMPLE
    cdd C:\Users\Documents
    Changes to the Documents directory and lists its contents.
    #>
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [string]$Path
    )
    
    Set-Location $Path
    Get-ChildItem
}



# Make sure my GitHub SSH keys are loaded into the ssh-agent

function Ensure-SshAgent {
    $service = Get-Service -Name 'ssh-agent' -ErrorAction SilentlyContinue

    if (-not $service) {
        Write-Warning "ssh-agent service not found. Make sure OpenSSH Client is installed."
        return $false
    }

    if ($service.Status -ne 'Running') {
        Write-Host "Starting ssh-agent service..." -ForegroundColor Yellow
        try {
            Start-Service 'ssh-agent'
            Write-Host "ssh-agent is now running." -ForegroundColor Green
        }
        catch {
            Write-Warning "Failed to start ssh-agent (you may need to run PowerShell as Administrator once to enable it)."
            return $false
        }
    }

    return $true
}

function Ensure-SshKeyLoaded {
    param(
        [Parameter(Mandatory)]
        [string]$KeyPath
    )

    if (-not (Test-Path $KeyPath)) {
        Write-Warning "Key not found: $KeyPath"
        return
    }

    $pubPath = "$KeyPath.pub"
    if (-not (Test-Path $pubPath)) {
        Write-Warning "Public key not found: $pubPath"
        return
    }

    # List existing keys in the agent
    $agentKeys = & ssh-add -L 2>$null
    if ($LASTEXITCODE -ne 0) {
        $agentKeys = ""
    }

    $pub = (Get-Content $pubPath -Raw).Trim()

    if ($agentKeys -and $agentKeys.Contains($pub)) {
        Write-Host "Already loaded: $KeyPath"
    }
    else {
        Write-Host "Loading key: $KeyPath"
        & ssh-add $KeyPath
    }
}

# ----- main -----
if (Ensure-SshAgent) {
    $personalKey = Join-Path $env:USERPROFILE ".ssh\id_ed25519_personal"
    $workKey     = Join-Path $env:USERPROFILE ".ssh\id_ed25519_work"

    Ensure-SshKeyLoaded -KeyPath $personalKey
    Ensure-SshKeyLoaded -KeyPath $workKey

    Write-Host "`nKeys currently in ssh-agent:" -ForegroundColor Cyan
    & ssh-add -l
}



# Clean folder utility (robocopy-based fast cleanup)
function Clean-Folder {
    <#
    .SYNOPSIS
    Fast folder cleanup using robocopy /MIR with an empty source.
    
    .PARAMETER Target
    The folder to clean. Defaults to user Temp folder.
    
    .PARAMETER Aggressive
    Use more threads for maximum throughput.
    
    .PARAMETER Force
    Skip confirmation prompt for non-temp folders.
    
    .PARAMETER NoDefenderExclusion
    Disable the default Defender exclusion (exclusion is ON by default).
    
    .PARAMETER DisableDefenderRealtime
    Temporarily disable Defender real-time monitoring entirely.
    
    .EXAMPLE
    Clean-Folder
    Cleans user temp folder with Defender exclusion (default).
    
    .EXAMPLE
    Clean-Folder -Target "D:\Cache" -Force
    Cleans arbitrary folder without prompting.
    
    .EXAMPLE
    Clean-Folder -NoDefenderExclusion
    Cleans temp folder without adding Defender exclusion.
    #>
    param(
        [string]$Target,
        [switch]$Aggressive,
        [switch]$Force,
        [switch]$NoDefenderExclusion,
        [switch]$DisableDefenderRealtime
    )
    
    $scriptPath = "$env:USERPROFILE\Scripts\Clean-LocalTemp.ps1"
    $params = @{}
    if ($Target) { $params['Target'] = $Target }
    if ($Aggressive) { $params['Aggressive'] = $true }
    if ($Force) { $params['Force'] = $true }
    if ($NoDefenderExclusion) { $params['NoDefenderExclusion'] = $true }
    if ($DisableDefenderRealtime) { $params['DisableDefenderRealtime'] = $true }
    
    & $scriptPath @params
}

# Aliases for Clean-Folder
Set-Alias -Name cleantemp -Value Clean-Folder -Description 'Fast folder cleanup using robocopy'
Set-Alias -Name clt -Value Clean-Folder -Description 'Fast folder cleanup using robocopy'
Set-Alias -Name cleanfolder -Value Clean-Folder -Description 'Fast folder cleanup using robocopy'
Set-Alias -Name cleanf -Value Clean-Folder -Description 'Fast folder cleanup using robocopy'

Write-Host "PowerShell Profile Loaded" -ForegroundColor Cyan

