# System Architecture: Dual-Identity Development Environment
**User:** Alex Goldsmith
**OS:** Windows 11
**Editor:** Cursor 1.7 (VS Code Fork)

## 1. Executive Summary
This system is designed to seamlessly segregate **Work** (`benefitsallin`) and **Personal** (`aj-goldie`) development workflows on a single machine. It relies on a strict separation of concerns between **File System Location** (for Git identity) and **Editor Instance** (for GitHub API access).

### Key Capabilities
*   **Git Operations (CLI):** SSH authentication automatically switches keys based on which folder you are working in.
*   **GitHub Integration (GUI):** Pull Requests, Issues, and "Publish" features use the correct account based on which Cursor shortcut you launch.

---

## 2. Directory & Identity Standards
The system determines your Git identity (`user.email`) and your SSH Identity Key (`id_ed25519`) based on where the repository resides on the disk.

| Scope | Directory Path | Git Identity | GitHub User | SSH Key |
| :--- | :--- | :--- | :--- | :--- |
| **Work** | `C:\Users\AlexGoldsmith\Documents\Software\` | `alex.goldsmith@benefitsallin.com` | `bai-admin` | `id_ed25519_work` |
| **Personal** | `C:\Users\AlexGoldsmith\Documents\Software-Personal\` | `101531405+aj-goldie@...` | `aj-goldie` | `id_ed25519_personal` |
| **Other** | Any other path | *None (Commit blocked)* | *None* | *None* |

> **Critical Rule:** Always create or clone projects inside one of these two root directories. Do not work from the Desktop or Downloads folder, or Git will not know who you are.

---

## 3. Shell Support

This system works with **both PowerShell and Git Bash**. The same dual-identity configuration applies regardless of which shell you use.

### PowerShell (Primary)
- Configuration: `$PROFILE` (`Microsoft.PowerShell_profile.ps1`)
- SSH Agent: Windows OpenSSH service (`ssh-agent`)
- Keys are loaded automatically on shell startup

### Git Bash (Git for Windows)
- Configuration: `~/.bash_profile` (login) → `~/.bashrc` (all config)
- SSH Agent: Uses Windows OpenSSH via `core.sshCommand` in `.gitconfig`
- Direct `ssh` commands are wrapped to use Windows OpenSSH for consistency

**Shell Startup Modes:**
| Mode | Command | Sources |
|------|---------|---------|
| Interactive non-login | `bash` | `.bashrc` |
| Login shell | `bash -l` | `.bash_profile` → `.bashrc` |
| Login + command | `bash -lc "cmd"` | `.bash_profile` → `.bashrc` → runs cmd |
| Non-interactive | `bash -c "cmd"` | `$BASH_ENV` only (if set) |

The `.bash_profile` is configured to source `.bashrc`, ensuring all shell modes get the same PATH and configuration.

**Key Point:** Both shells share the same Windows ssh-agent service. Keys loaded in PowerShell are available in Git Bash, and vice versa.

---

## 4. The Editor Setup (Cursor 1.7)
Because VS Code/Cursor does not natively support context-aware multi-account switching for extensions, two separate instances are used.

### Instance A: "Cursor (Work)"
*   **Shortcut Location:** `%APPDATA%\Microsoft\Windows\Start Menu\Programs\Cursor.lnk`
*   **Target:**
    ```
    "C:\Users\AlexGoldsmith\AppData\Local\Programs\cursor\Cursor.exe" --user-data-dir "C:\Users\AlexGoldsmith\AppData\Roaming\Cursor" --profile "Work Laptop"
    ```
*   **Start In:** `C:\Users\AlexGoldsmith\AppData\Local\Programs\cursor`
*   **Data Directory:** `%APPDATA%\Cursor`
*   **Profile:** "Work Laptop"
*   **GitHub Auth:** Logged in as **bai-admin**.
*   **Use Case:** All work projects.

### Instance B: "Cursor Personal"
*   **Shortcut Location:** `%APPDATA%\Microsoft\Windows\Start Menu\Programs\Cursor Personal.lnk`
*   **Target:**
    ```
    "C:\Users\AlexGoldsmith\AppData\Local\Programs\cursor\Cursor.exe" --user-data-dir "C:\Users\AlexGoldsmith\AppData\Roaming\Cursor Personal" --profile "Work Laptop"
    ```
*   **Start In:** `C:\Users\AlexGoldsmith\AppData\Local\Programs\cursor`
*   **Data Directory:** `%APPDATA%\Cursor Personal`
*   **Profile:** "Work Laptop" (exported from Instance A, imported into Instance B)
*   **GitHub Auth:** Logged in as **aj-goldie**.
*   **Use Case:** Personal projects, side hustles.

---

## 5. Operational Workflows

### A. Cloning a Repository (The "Alias" Step)
Because a `.git` folder does not exist yet during a clone, automatic detection fails. You must manually specify the **SSH Host Alias** to ensure the correct key is offered to GitHub.

*   **Work Clone:**
    ```powershell
    git clone git@github-work:organization/repo-name.git
    ```
*   **Personal Clone:**
    ```powershell
    git clone git@github-personal:username/repo-name.git
    ```

*(Note: Using standard `git@github.com` will cause a "Permission Denied" error because SSH will ambiguously offer the wrong key.)*

### B. Initializing a New Repo (`git init`)
1.  Navigate to the correct directory (e.g., `Software-Personal`).
2.  Run `git init`.
3.  Make your first commit.
    *   *System Behavior:* Git detects the directory path via `.gitconfig`, loads the specific config, and applies the correct `user.email`.

### C. Pushing / Pulling
Once a repo is established (post-clone or post-init), you can simply run:
```powershell
git push
```
*   *System Behavior:* The local `.git/config` or the global config rewrite rules will automatically map the remote URL to the correct SSH alias (`github-work` or `github-personal`). SSH will use the corresponding key without prompting for a passphrase.

### D. Using Editor Features (Publish / PRs)
1.  Open **Cursor Personal**.
2.  Open a folder in `Software-Personal`.
3.  Click "Publish to GitHub" or use the Pull Request pane.
    *   *System Behavior:* Cursor uses the OAuth token stored in the "Cursor Personal" secure storage (`aj-goldie`), completely bypassing SSH.

---

## 6. Repository Contents

This repository contains **symlinked** configuration files. Changes made here will reflect in the live system files and vice versa.

```
configs/windows-work-laptop/
├── .gitconfig                      → C:\Users\AlexGoldsmith\.gitconfig
├── .gitconfig-personal             → C:\Users\AlexGoldsmith\.gitconfig-personal
├── .gitconfig-work                 → C:\Users\AlexGoldsmith\.gitconfig-work
├── .bash_profile                   → C:\Users\AlexGoldsmith\.bash_profile (Git Bash login)
├── .bashrc                         → C:\Users\AlexGoldsmith\.bashrc (Git Bash config)
├── gitconfig-system                → C:\Program Files\Git\etc\gitconfig
└── Microsoft.PowerShell_profile.ps1 → C:\Users\AlexGoldsmith\Documents\PowerShell\Microsoft.PowerShell_profile.ps1

configs/shared/
├── .gitattributes_global           → C:\Users\AlexGoldsmith\.gitattributes_global
└── githooks/                       → C:\Users\AlexGoldsmith\.githooks\

scripts/shared/
├── nbstripout-safe                 → C:\Users\AlexGoldsmith\.local\bin\nbstripout-safe (bash)
└── nbstripout-safe.cmd             → C:\Users\AlexGoldsmith\.local\bin\nbstripout-safe.cmd (cmd)
```

> **Note:** Symlinks point from system locations TO repo files. The repo is the source of truth. Run `scripts/windows/Git-Setup.ps1` (as Administrator) to create/update all symlinks.

---

## 7. Technical Configuration Reference

### A. SSH Configuration (`~/.ssh/config`)
Defines aliases to force specific keys for specific "hosts".
```ssh
# Personal
Host github-personal
    HostName github.com
    User git
    IdentityFile "C:\Users\AlexGoldsmith\.ssh\id_ed25519_personal"
    IdentitiesOnly yes

# Work
Host github-work
    HostName github.com
    User git
    IdentityFile "C:\Users\AlexGoldsmith\.ssh\id_ed25519_work"
    IdentitiesOnly yes
```

### B. Git Configuration (`~/.gitconfig`)
Handles directory detection and SSH client mapping.
```ini
[core]
    # Forces Git to use Windows Native OpenSSH (Civil War Fix)
    sshCommand = "C:/Windows/System32/OpenSSH/ssh.exe"

# Directory-based switching
[includeIf "gitdir:C:/Users/AlexGoldsmith/Documents/Software/"]
    path = .gitconfig-work

[includeIf "gitdir:C:/Users/AlexGoldsmith/Documents/Software-Personal/"]
    path = .gitconfig-personal
```

### C. PowerShell Profile (`$PROFILE`)
Ensures keys are decrypted and loaded into RAM on shell startup so you aren't prompted for passwords.
*   Checks if `ssh-agent` service is running.
*   Loads `id_ed25519_personal` and `id_ed25519_work` into the agent.



### D. Github.com UI - SSH Authentication Configuration
bai-admin (bai-admin)settings

SSH keys
This is a list of SSH keys associated with your account. Remove any keys that you do not recognize.

Authentication keys
SSH
alex.work-acct.work-laptop
SHA256:keEJQvbegJjDV9tB/MfwPfT7a85zyl3YO/UYuxHgnrc
Added on Nov 19, 2025

---

aj-goldie (aj-goldie)settings

SSH keys
This is a list of SSH keys associated with your account. Remove any keys that you do not recognize.

Authentication keys
SSH
alex.personal-acct.work-laptop
SHA256:cFc3CEA8t72bg4CF4ogBtDNc4HzURrd/2wHl0azt6nw
Added on Nov 16, 2025

---

## 8. Troubleshooting

**Problem:** "Enter passphrase for key..." prompts when running Git commands.
**Cause:** Git is ignoring the Windows SSH Agent and trying to read the encrypted file directly.
**Fix:** Ensure the `sshCommand` fix is applied:
`git config --global core.sshCommand "C:/Windows/System32/OpenSSH/ssh.exe"`

**Problem:** "Permission denied (publickey)" when cloning.
**Cause:** You used `git clone git@github.com...` instead of the alias.
**Fix:** Use `git clone git@github-personal:...` or `git@github-work:...`.

**Problem:** "Please tell me who you are" error on commit.
**Cause:** You are trying to use Git outside of the designated `Software` or `Software-Personal` folders.
**Fix:** Move your project into one of the designated folders.

---

### Git Bash-Specific Issues

**Problem:** Git Bash doesn't seem to use the right SSH key.
**Cause:** Git Bash has its own SSH, but Git operations use Windows OpenSSH via `core.sshCommand`.
**Fix:** This is expected. Direct `ssh` commands in Git Bash are wrapped to use Windows OpenSSH. If you see issues, verify the `.bashrc` is properly symlinked: `ls -la ~/.bashrc`

**Problem:** `nbstripout-safe` not found in Git Bash.
**Cause:** `~/.local/bin` is not in PATH, or the bash script isn't symlinked.
**Fix:** 
1. Ensure `~/.bashrc` is symlinked: `ls -la ~/.bashrc`
2. Source it: `source ~/.bashrc`
3. Verify: `which nbstripout-safe`

**Problem:** SSH keys not loaded in Git Bash.
**Cause:** Keys are managed by Windows ssh-agent service, which must be started via PowerShell.
**Fix:** Open PowerShell and run:
```powershell
Start-Service ssh-agent
ssh-add ~/.ssh/id_ed25519_personal
ssh-add ~/.ssh/id_ed25519_work
```
Then return to Git Bash. The keys persist in the Windows agent.