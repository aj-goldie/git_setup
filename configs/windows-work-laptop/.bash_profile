# ===========================================
# Git Bash Login Shell Configuration
# ===========================================
# This file is sourced for LOGIN shells (bash -l, bash --login, bash -lc).
# Interactive non-login shells source ~/.bashrc directly.
#
# Standard practice: source .bashrc from .bash_profile so all
# configuration is centralized in one place.
# ===========================================

# Source .bashrc if it exists (centralizes all configuration)
if [ -f "$HOME/.bashrc" ]; then
    . "$HOME/.bashrc"
fi

