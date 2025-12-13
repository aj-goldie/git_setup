#!/bin/zsh
# ===========================================
# GitHub SSH Key Loader for macOS
# ===========================================
# Loads GitHub SSH keys into agent with macOS Keychain integration.
# Keys will only prompt for passphrase once, then stored in Keychain.

load_key_to_keychain() {
    local key_path="$1"
    local key_name="$(basename "$key_path")"
    
    if [[ ! -f "$key_path" ]]; then
        return 1
    fi
    
    # Check if key is already in agent
    local pub_content
    if [[ -f "${key_path}.pub" ]]; then
        pub_content=$(cat "${key_path}.pub" | awk '{print $2}')
        if ssh-add -L 2>/dev/null | grep -q "$pub_content"; then
            return 0
        fi
    fi
    
    # Add to agent with Keychain storage (--apple-use-keychain for macOS 12+)
    ssh-add --apple-use-keychain "$key_path" 2>/dev/null || ssh-add -K "$key_path" 2>/dev/null
}

# Load both GitHub keys
load_key_to_keychain "$HOME/.ssh/id_ed25519_personal"
load_key_to_keychain "$HOME/.ssh/id_ed25519_work"

