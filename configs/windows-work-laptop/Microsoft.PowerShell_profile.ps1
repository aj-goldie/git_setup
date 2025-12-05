
if ($env:TERM_PROGRAM -eq 'vscode' -or $env:TERM_PROGRAM -eq 'cursor') {
    function Prompt { "PS> " }

    # Make console and pipeline UTF-8 inside Cursor
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding           = [System.Text.Encoding]::UTF8

    Set-PSReadLineOption -PredictionSource None
    Set-PSReadLineOption -BellStyle None
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
        try {
            Start-Service 'ssh-agent'
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
        [string]$KeyPath,
        [switch]$Silent
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
        if (-not $Silent) { Write-Host "Already loaded: $KeyPath" }
    }
    else {
        if (-not $Silent) { Write-Host "Loading key: $KeyPath" }
        & ssh-add $KeyPath 2>$null
    }
}

function Show-SshStatus {
    <#
    .SYNOPSIS
    Shows SSH agent status and loaded keys.
    #>
    $service = Get-Service -Name 'ssh-agent' -ErrorAction SilentlyContinue
    if ($service -and $service.Status -eq 'Running') {
        Write-Host "ssh-agent: " -NoNewline
        Write-Host "Running" -ForegroundColor Green
    } else {
        Write-Host "ssh-agent: " -NoNewline
        Write-Host "Not Running" -ForegroundColor Red
        return
    }
    
    Write-Host "`nKeys loaded:" -ForegroundColor Cyan
    & ssh-add -l
}

Set-Alias -Name sshkeys -Value Show-SshStatus
Set-Alias -Name sshinfo -Value Show-SshStatus

# ----- main -----
if (Ensure-SshAgent) {
    $personalKey = Join-Path $env:USERPROFILE ".ssh\id_ed25519_personal"
    $workKey     = Join-Path $env:USERPROFILE ".ssh\id_ed25519_work"

    Ensure-SshKeyLoaded -KeyPath $personalKey -Silent
    Ensure-SshKeyLoaded -KeyPath $workKey -Silent
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

# Write-Host "PowerShell Profile Loaded" -ForegroundColor Cyan

