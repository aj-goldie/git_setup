# ===========================================
# Git Bash Configuration for Windows
# ===========================================
# This file configures Git Bash to work with the same dual-identity
# setup as PowerShell (Windows ssh-agent, same keys, same tools).
#
# Symlink: ~/.bashrc -> repo/.bashrc
#
# Shell startup behavior:
#   - Interactive non-login: sources .bashrc directly
#   - Login shell (-l): sources .bash_profile, which sources this file
#   - Non-interactive (-c): sources $BASH_ENV if set
# ===========================================

# === PATH Configuration (runs for ALL shell types) ===
# This section is safe for non-interactive shells and must run first
# to ensure tools like nbstripout-safe are available for git filters.
LOCAL_BIN="$HOME/.local/bin"
if [[ -d "$LOCAL_BIN" ]] && [[ ":$PATH:" != *":$LOCAL_BIN:"* ]]; then
    export PATH="$LOCAL_BIN:$PATH"
fi

# Also add uv's bin directory if it exists (for python, etc.)
UV_BIN="$HOME/.local/share/uv/bin"
if [[ -d "$UV_BIN" ]] && [[ ":$PATH:" != *":$UV_BIN:"* ]]; then
    export PATH="$UV_BIN:$PATH"
fi

# === SSH Agent Integration (Windows OpenSSH) ===
# Git operations already use Windows OpenSSH via core.sshCommand in .gitconfig
# This section enables direct `ssh` commands to also use Windows ssh-agent

ssh_agent_env_setup() {
    # Check if Windows ssh-agent service is running
    if command -v powershell.exe &>/dev/null; then
        local agent_status
        agent_status=$(powershell.exe -NoProfile -Command "(Get-Service ssh-agent -ErrorAction SilentlyContinue).Status" 2>/dev/null | tr -d '\r')
        
        if [[ "$agent_status" == "Running" ]]; then
            # Point to Windows OpenSSH for direct ssh commands
            # This ensures `ssh git@github.com` uses the same agent as git
            export GIT_SSH_COMMAND="/c/Windows/System32/OpenSSH/ssh.exe"
            
            # For direct ssh usage, we need to use Windows ssh.exe
            # Create a function that wraps Windows SSH
            ssh() {
                /c/Windows/System32/OpenSSH/ssh.exe "$@"
            }
            export -f ssh 2>/dev/null || true
            
            return 0
        fi
    fi
    return 1
}

# === Initialize on shell startup ===
ssh_agent_env_setup

# === Key Loading Helper ===
# Function to ensure keys are loaded into Windows ssh-agent
# (Normally handled by PowerShell profile, but useful for verification)
ensure_ssh_keys() {
    echo "Checking Windows ssh-agent status..."
    
    if ! command -v powershell.exe &>/dev/null; then
        echo "Error: PowerShell not found"
        return 1
    fi
    
    # Check agent status
    local status
    status=$(powershell.exe -NoProfile -Command "(Get-Service ssh-agent).Status" 2>/dev/null | tr -d '\r')
    
    if [[ "$status" != "Running" ]]; then
        echo "Warning: Windows ssh-agent is not running"
        echo "Run PowerShell as Admin: Start-Service ssh-agent"
        return 1
    fi
    
    echo "ssh-agent: Running"
    echo ""
    echo "Loaded keys:"
    /c/Windows/System32/OpenSSH/ssh-add.exe -l 2>/dev/null || echo "  (no keys loaded)"
    echo ""
    echo "To load keys, open PowerShell and run:"
    echo "  ssh-add ~/.ssh/id_ed25519_personal"
    echo "  ssh-add ~/.ssh/id_ed25519_work"
}

# === Aliases ===
alias sshkeys='ensure_ssh_keys'
alias sshinfo='ensure_ssh_keys'

# === Prompt (Optional - minimal for integrated terminals) ===
if [[ "$TERM_PROGRAM" == "vscode" ]] || [[ "$TERM_PROGRAM" == "cursor" ]]; then
    PS1='$ '
fi

# === Git Identity Status ===
# Shows which git identity will be used in current directory
git_identity() {
    local email
    email=$(git config user.email 2>/dev/null)
    if [[ -n "$email" ]]; then
        echo "Git identity: $email"
    else
        echo "Git identity: Not configured (outside Software or Software-Personal folders)"
    fi
}
alias gitid='git_identity'


