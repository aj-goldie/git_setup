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

## 3. The Editor Setup (Cursor 1.7)
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

## 4. Operational Workflows

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

## 5. Repository Contents

This repository contains **hardlinked** copies of the actual configuration files. Changes made here will reflect in the live system files and vice versa.

```
configs/
├── .gitconfig                      → C:\Users\AlexGoldsmith\.gitconfig
├── .gitconfig-personal             → C:\Users\AlexGoldsmith\.gitconfig-personal
├── .gitconfig-work                 → C:\Users\AlexGoldsmith\.gitconfig-work
├── gitconfig-system                → C:\Program Files\Git\etc\gitconfig
└── Microsoft.PowerShell_profile.ps1 → C:\Users\AlexGoldsmith\Documents\PowerShell\Microsoft.PowerShell_profile.ps1
```

> **Note:** Hardlinks are filesystem-level duplicates. The files in `configs/` ARE the same files on disk as the originals—not copies. Editing either location edits the same underlying data.

---

## 6. Technical Configuration Reference

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

## 7. Troubleshooting

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