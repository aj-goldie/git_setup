#!/bin/bash
#
# Git-Setup.sh - macOS
#
# Sets up symlinks from macOS system locations to git repo config files.
#
# IDEMPOTENT & SAFE - can be run multiple times without data loss.
#
# This script:
#   1. Checks if everything is already configured correctly (exits early if so)
#   2. Moves config files from system locations TO the repo (only if not already done)
#   3. Creates symlinks FROM system locations TO repo files
#   4. NEVER deletes files in the repo directory
#
# Config files handled:
#   - .gitconfig, .gitconfig-personal, .gitconfig-work (user home)
#   - ssh-config (~/.ssh/config)
#   - load-github-keys.sh (~/.ssh/)
#   - .gitattributes_global, .githooks (shared configs)
#   - nbstripout-safe (~/.local/bin/) - fault-tolerant notebook filter
#

set -e

# === COLORS ===
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
NC='\033[0m' # No Color

# === CONFIGURATION ===
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
REPO_DIR="$REPO_ROOT/configs/macos-personal-laptop"
SHARED_DIR="$REPO_ROOT/configs/shared"
SCRIPTS_DIR="$REPO_ROOT/scripts/macos"
SHARED_SCRIPTS_DIR="$REPO_ROOT/scripts/shared"
BACKUP_DIR="$HOME/.git-setup-backup-$(date +%Y%m%d-%H%M%S)"

# Files that should be symlinked: System -> Repo
declare -A CONFIG_FILES=(
    ["$HOME/.gitconfig"]="$REPO_DIR/.gitconfig"
    ["$HOME/.gitconfig-personal"]="$REPO_DIR/.gitconfig-personal"
    ["$HOME/.gitconfig-work"]="$REPO_DIR/.gitconfig-work"
    ["$HOME/.ssh/config"]="$REPO_DIR/ssh-config"
    ["$HOME/.ssh/load-github-keys.sh"]="$SCRIPTS_DIR/load-github-keys.sh"
)

# Shared configs: System -> Repo
declare -A SHARED_LINKS=(
    ["$HOME/.gitattributes_global"]="$SHARED_DIR/.gitattributes_global"
    ["$HOME/.githooks"]="$SHARED_DIR/githooks"
)

# Executable scripts: ~/.local/bin -> Repo
declare -A BIN_SCRIPTS=(
    ["$HOME/.local/bin/nbstripout-safe"]="$SHARED_SCRIPTS_DIR/nbstripout-safe"
)

# === HELPER FUNCTIONS ===
is_symlink() {
    [[ -L "$1" ]]
}

get_symlink_target() {
    if is_symlink "$1"; then
        readlink "$1"
    else
        echo ""
    fi
}

resolve_path() {
    cd "$(dirname "$1")" && pwd -P
}

paths_equal() {
    local path1="$1"
    local path2="$2"
    
    # Resolve both paths to absolute
    local resolved1 resolved2
    if [[ -e "$path1" ]]; then
        resolved1="$(cd "$(dirname "$path1")" && pwd -P)/$(basename "$path1")"
    else
        resolved1="$path1"
    fi
    if [[ -e "$path2" ]]; then
        resolved2="$(cd "$(dirname "$path2")" && pwd -P)/$(basename "$path2")"
    else
        resolved2="$path2"
    fi
    
    [[ "$resolved1" == "$resolved2" ]]
}

status_msg() {
    local status="$1"
    local message="$2"
    case "$status" in
        "OK")     echo -e "  [${GREEN}OK${NC}] $message" ;;
        "ACTION") echo -e "  [${YELLOW}ACTION${NC}] $message" ;;
        "ERROR")  echo -e "  [${RED}ERROR${NC}] $message" ;;
        "INFO")   echo -e "  [${CYAN}INFO${NC}] $message" ;;
    esac
}

# === MAIN ===
echo ""
echo -e "${CYAN}=== GIT SETUP - macOS (Safe & Idempotent) ===${NC}"
echo ""

# Check repo directory exists
if [[ ! -d "$REPO_DIR" ]]; then
    echo -e "${RED}ERROR: Repo directory not found: $REPO_DIR${NC}"
    exit 1
fi

# Ensure ~/.ssh exists
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

# Ensure ~/.local/bin exists (for executable scripts)
mkdir -p "$HOME/.local/bin"

# === PHASE 0: PREREQUISITES (uv, Python, nbstripout-fast) ===
echo -e "${YELLOW}[Phase 0] Checking prerequisites...${NC}"
echo ""

LOCAL_BIN="$HOME/.local/bin"
SHELL_PROFILE="$HOME/.zshrc"

# Smart PATH block that ensures first position (handles both "not in PATH" and "in PATH but not first")
PATH_BLOCK='
# Ensure ~/.local/bin is FIRST on PATH (added by Git-Setup)
if [[ -d "$HOME/.local/bin" ]]; then
    case ":$PATH:" in
        *":$HOME/.local/bin:"*)
            # Already in PATH - remove and prepend to ensure first position
            PATH=$(echo ":$PATH:" | sed "s|:$HOME/.local/bin:|:|g" | sed '"'"'s/^://;s/:$//'"'"')
            export PATH="$HOME/.local/bin:$PATH"
            ;;
        *)
            # Not in PATH - prepend
            export PATH="$HOME/.local/bin:$PATH"
            ;;
    esac
fi'

# --- Step 1: Check/install uv ---
if command -v uv &> /dev/null; then
    status_msg "OK" "uv is installed"
else
    echo -e "  ${CYAN}Installing uv...${NC}"
    if curl -LsSf https://astral.sh/uv/install.sh | sh 2>&1; then
        # Source the env file that uv installer creates
        [[ -f "$LOCAL_BIN/env" ]] && source "$LOCAL_BIN/env"
        status_msg "OK" "uv installed"
    else
        status_msg "ERROR" "Failed to install uv"
        exit 1
    fi
fi

# --- Step 2: Check/fix PATH order - ~/.local/bin should be first ---
FIRST_PATH_ENTRY=$(echo "$PATH" | cut -d: -f1)
if [[ "$FIRST_PATH_ENTRY" == "$LOCAL_BIN" ]]; then
    status_msg "OK" "~/.local/bin is first on PATH"
else
    status_msg "ACTION" "~/.local/bin is NOT first on PATH - fixing..."
    
    # Check if our smart PATH block already exists in profile
    if ! grep -q 'Ensure.*\.local/bin.*FIRST on PATH' "$SHELL_PROFILE" 2>/dev/null; then
        echo -e "  ${CYAN}Adding smart PATH block to $SHELL_PROFILE...${NC}"
        # Ensure profile directory exists
        mkdir -p "$(dirname "$SHELL_PROFILE")"
        echo "$PATH_BLOCK" >> "$SHELL_PROFILE"
    fi
    
    # Apply PATH fix NOW for this session (remove from current position if present, then prepend)
    echo -e "  ${CYAN}Applying PATH fix to current session...${NC}"
    PATH=$(echo ":$PATH:" | sed "s|:$LOCAL_BIN:|:|g" | sed 's/^://;s/:$//')
    export PATH="$LOCAL_BIN:$PATH"
    status_msg "OK" "PATH updated - ~/.local/bin is now first"
fi

# --- Step 3: Install Python 3.12 via uv ---
echo -e "  ${CYAN}Ensuring Python 3.12 is installed via uv...${NC}"
if uv python install 3.12 --default --preview 2>&1 | grep -q "already"; then
    status_msg "OK" "Python 3.12 already installed"
else
    status_msg "OK" "Python 3.12 installed"
fi

# --- Step 4: Verify python executables exist (AFTER PATH is correct) ---
if [[ -x "$LOCAL_BIN/python" ]]; then
    status_msg "OK" "~/.local/bin/python exists"
else
    status_msg "INFO" "~/.local/bin/python not found (uv may use different location)"
fi

if [[ -x "$LOCAL_BIN/python3" ]]; then
    status_msg "OK" "~/.local/bin/python3 exists"
else
    status_msg "INFO" "~/.local/bin/python3 not found (uv may use different location)"
fi

# --- Step 5: Check/install nbstripout-fast via uv tool ---
if [[ -x "$LOCAL_BIN/nbstripout-fast" ]]; then
    status_msg "OK" "nbstripout-fast is installed"
else
    echo -e "  ${CYAN}Installing nbstripout-fast via uv...${NC}"
    if uv tool install nbstripout-fast 2>&1; then
        status_msg "OK" "nbstripout-fast installed"
    else
        status_msg "ERROR" "Failed to install nbstripout-fast"
        exit 1
    fi
fi

echo ""

# === PHASE 1: ANALYZE CURRENT STATE ===
echo -e "${YELLOW}[Phase 1] Analyzing current state...${NC}"
echo ""

needs_action=false
declare -a actions=()

for sys_path in "${!CONFIG_FILES[@]}"; do
    repo_path="${CONFIG_FILES[$sys_path]}"
    name="$(basename "$sys_path")"
    
    sys_exists=$([[ -e "$sys_path" || -L "$sys_path" ]] && echo true || echo false)
    repo_exists=$([[ -e "$repo_path" ]] && echo true || echo false)
    sys_is_symlink=$(is_symlink "$sys_path" && echo true || echo false)
    symlink_target="$(get_symlink_target "$sys_path")"
    
    if [[ "$sys_is_symlink" == "true" ]]; then
        # Check if symlink points to the right place
        if paths_equal "$symlink_target" "$repo_path" || [[ "$symlink_target" == "$repo_path" ]]; then
            status_msg "OK" "$name - symlink points to repo"
        else
            # Symlink exists but points to wrong target - auto-fix it
            status_msg "ACTION" "$name - symlink points to WRONG target, will RELINK"
            echo -e "       ${GRAY}Current:  $symlink_target${NC}"
            echo -e "       ${GRAY}Expected: $repo_path${NC}"
            needs_action=true
            actions+=("RELINK:$sys_path:$repo_path")
        fi
    elif [[ "$sys_exists" == "true" && "$sys_is_symlink" == "false" && "$repo_exists" == "true" ]]; then
        # Both exist as real files - need to decide which to keep
        status_msg "ERROR" "$name - EXISTS in BOTH locations (real files)"
        echo -e "       ${GRAY}System: $sys_path${NC}"
        echo -e "       ${GRAY}Repo:   $repo_path${NC}"
        echo ""
        echo -e "${RED}ERROR: Cannot proceed - file exists in both locations.${NC}"
        echo -e "${RED}Please manually delete one copy, then run again.${NC}"
        exit 1
    elif [[ "$sys_exists" == "true" && "$sys_is_symlink" == "false" && "$repo_exists" == "false" ]]; then
        # System file exists, repo doesn't - needs to be moved
        status_msg "ACTION" "$name - needs MOVE to repo + symlink"
        needs_action=true
        actions+=("MOVE:$sys_path:$repo_path")
    elif [[ "$sys_exists" == "false" && "$repo_exists" == "true" ]]; then
        # Repo file exists, system doesn't - just needs symlink
        status_msg "ACTION" "$name - needs SYMLINK (repo file exists)"
        needs_action=true
        actions+=("SYMLINK:$sys_path:$repo_path")
    elif [[ "$sys_exists" == "false" && "$repo_exists" == "false" ]]; then
        # Neither exists - warning but not fatal
        status_msg "INFO" "$name - MISSING from both locations"
    fi
done

# Check shared configs
echo ""
for sys_path in "${!SHARED_LINKS[@]}"; do
    repo_path="${SHARED_LINKS[$sys_path]}"
    name="$(basename "$sys_path")"
    
    sys_exists=$([[ -e "$sys_path" || -L "$sys_path" ]] && echo true || echo false)
    repo_exists=$([[ -e "$repo_path" ]] && echo true || echo false)
    sys_is_symlink=$(is_symlink "$sys_path" && echo true || echo false)
    symlink_target="$(get_symlink_target "$sys_path")"
    
    if [[ "$repo_exists" == "false" ]]; then
        status_msg "ERROR" "$name - MISSING from repo (shared config)"
        echo -e "       ${GRAY}Expected: $repo_path${NC}"
        echo ""
        echo -e "${RED}ERROR: Shared config missing from repo.${NC}"
        exit 1
    elif [[ "$sys_is_symlink" == "true" ]]; then
        if paths_equal "$symlink_target" "$repo_path" || [[ "$symlink_target" == "$repo_path" ]]; then
            status_msg "OK" "$name - symlink points to repo"
        else
            # Symlink exists but points to wrong target - auto-fix it
            status_msg "ACTION" "$name - symlink points to WRONG target, will RELINK"
            echo -e "       ${GRAY}Current:  $symlink_target${NC}"
            echo -e "       ${GRAY}Expected: $repo_path${NC}"
            needs_action=true
            actions+=("RELINK:$sys_path:$repo_path")
        fi
    elif [[ "$sys_exists" == "true" && "$sys_is_symlink" == "false" ]]; then
        status_msg "ACTION" "$name - needs REPLACE with symlink"
        needs_action=true
        actions+=("SHARED:$sys_path:$repo_path")
    elif [[ "$sys_exists" == "false" ]]; then
        status_msg "ACTION" "$name - needs SYMLINK"
        needs_action=true
        actions+=("SHARED:$sys_path:$repo_path")
    fi
done

# Check bin scripts (~/.local/bin)
echo ""
for sys_path in "${!BIN_SCRIPTS[@]}"; do
    repo_path="${BIN_SCRIPTS[$sys_path]}"
    name="$(basename "$sys_path")"
    
    sys_exists=$([[ -e "$sys_path" || -L "$sys_path" ]] && echo true || echo false)
    repo_exists=$([[ -e "$repo_path" ]] && echo true || echo false)
    sys_is_symlink=$(is_symlink "$sys_path" && echo true || echo false)
    symlink_target="$(get_symlink_target "$sys_path")"
    
    if [[ "$repo_exists" == "false" ]]; then
        status_msg "ERROR" "$name - MISSING from repo (bin script)"
        echo -e "       ${GRAY}Expected: $repo_path${NC}"
        echo ""
        echo -e "${RED}ERROR: Bin script missing from repo.${NC}"
        exit 1
    elif [[ "$sys_is_symlink" == "true" ]]; then
        if paths_equal "$symlink_target" "$repo_path" || [[ "$symlink_target" == "$repo_path" ]]; then
            status_msg "OK" "$name - symlink points to repo"
        else
            status_msg "ACTION" "$name - symlink points to WRONG target, will RELINK"
            echo -e "       ${GRAY}Current:  $symlink_target${NC}"
            echo -e "       ${GRAY}Expected: $repo_path${NC}"
            needs_action=true
            actions+=("RELINK:$sys_path:$repo_path")
        fi
    elif [[ "$sys_exists" == "true" && "$sys_is_symlink" == "false" ]]; then
        status_msg "ACTION" "$name - needs REPLACE with symlink"
        needs_action=true
        actions+=("BIN:$sys_path:$repo_path")
    elif [[ "$sys_exists" == "false" ]]; then
        status_msg "ACTION" "$name - needs SYMLINK"
        needs_action=true
        actions+=("BIN:$sys_path:$repo_path")
    fi
done

# === PHASE 2: EXECUTE OR EXIT ===
echo ""

if [[ "$needs_action" == "false" ]]; then
    echo -e "${GREEN}All symlinks are already configured correctly!${NC}"
    echo -e "${GREEN}Nothing to do.${NC}"
    exit 0
fi

echo -e "${YELLOW}[Phase 2] Executing ${#actions[@]} action(s)...${NC}"
echo ""

# Create backup directory
mkdir -p "$BACKUP_DIR"
echo -e "  ${GRAY}Backup directory: $BACKUP_DIR${NC}"
echo ""

for action in "${actions[@]}"; do
    IFS=':' read -r action_type sys_path repo_path <<< "$action"
    name="$(basename "$sys_path")"
    
    case "$action_type" in
        "MOVE")
            echo -e "  ${CYAN}Moving $name to repo...${NC}"
            cp "$sys_path" "$BACKUP_DIR/$name"
            mv "$sys_path" "$repo_path"
            ln -s "$repo_path" "$sys_path"
            echo -e "    ${GREEN}Backed up, moved, symlinked${NC}"
            ;;
        "SYMLINK")
            echo -e "  ${CYAN}Creating symlink for $name...${NC}"
            ln -s "$repo_path" "$sys_path"
            echo -e "    ${GREEN}Symlinked${NC}"
            ;;
        "RELINK")
            echo -e "  ${CYAN}Fixing symlink for $name...${NC}"
            old_target="$(readlink "$sys_path")"
            echo "$sys_path -> $old_target" >> "$BACKUP_DIR/relinked.txt"
            rm "$sys_path"
            ln -s "$repo_path" "$sys_path"
            echo -e "    ${GREEN}Relinked (old target logged)${NC}"
            ;;
        "SHARED")
            echo -e "  ${CYAN}Setting up shared config $name...${NC}"
            if [[ -e "$sys_path" ]]; then
                cp -r "$sys_path" "$BACKUP_DIR/$name"
                rm -rf "$sys_path"
            fi
            ln -s "$repo_path" "$sys_path"
            echo -e "    ${GREEN}Symlinked${NC}"
            ;;
        "BIN")
            echo -e "  ${CYAN}Setting up bin script $name...${NC}"
            if [[ -e "$sys_path" ]]; then
                cp "$sys_path" "$BACKUP_DIR/$name"
                rm -f "$sys_path"
            fi
            ln -s "$repo_path" "$sys_path"
            echo -e "    ${GREEN}Symlinked${NC}"
            ;;
    esac
done

# === PHASE 3: VERIFICATION ===
echo ""
echo -e "${YELLOW}[Phase 3] Verification...${NC}"
echo ""

all_good=true

for sys_path in "${!CONFIG_FILES[@]}"; do
    repo_path="${CONFIG_FILES[$sys_path]}"
    name="$(basename "$sys_path")"
    
    if is_symlink "$sys_path"; then
        target="$(get_symlink_target "$sys_path")"
        if paths_equal "$target" "$repo_path" || [[ "$target" == "$repo_path" ]]; then
            status_msg "OK" "$name -> repo"
        else
            status_msg "ERROR" "$name -> WRONG TARGET"
            all_good=false
        fi
    elif [[ ! -e "$sys_path" && ! -e "$repo_path" ]]; then
        status_msg "INFO" "$name - not configured (missing)"
    else
        status_msg "ERROR" "$name - NOT a symlink"
        all_good=false
    fi
done

for sys_path in "${!SHARED_LINKS[@]}"; do
    repo_path="${SHARED_LINKS[$sys_path]}"
    name="$(basename "$sys_path")"
    
    if is_symlink "$sys_path"; then
        target="$(get_symlink_target "$sys_path")"
        if paths_equal "$target" "$repo_path" || [[ "$target" == "$repo_path" ]]; then
            status_msg "OK" "$name -> repo"
        else
            status_msg "ERROR" "$name -> WRONG TARGET"
            all_good=false
        fi
    else
        status_msg "ERROR" "$name - NOT a symlink"
        all_good=false
    fi
done

for sys_path in "${!BIN_SCRIPTS[@]}"; do
    repo_path="${BIN_SCRIPTS[$sys_path]}"
    name="$(basename "$sys_path")"
    
    if is_symlink "$sys_path"; then
        target="$(get_symlink_target "$sys_path")"
        if paths_equal "$target" "$repo_path" || [[ "$target" == "$repo_path" ]]; then
            status_msg "OK" "$name -> repo"
        else
            status_msg "ERROR" "$name -> WRONG TARGET"
            all_good=false
        fi
    else
        status_msg "ERROR" "$name - NOT a symlink"
        all_good=false
    fi
done

echo ""
if [[ "$all_good" == "true" ]]; then
    echo -e "${GREEN}Setup complete!${NC}"
else
    echo -e "${RED}Setup completed with errors - please review above.${NC}"
fi
echo -e "${GRAY}Backup saved to: $BACKUP_DIR${NC}"

