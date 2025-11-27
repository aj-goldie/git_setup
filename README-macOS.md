# System Architecture: Dual-Identity Development Environment
**User:** Alex Goldsmith
**OS:** macOS (Sequoia 15.x)
**Editor:** Cursor 2.0

## 1. Executive Summary
This system is designed to seamlessly segregate **Personal** (`aj-goldie`) and **Work** (`bai-admin`) development workflows on a single machine. It relies on a strict separation of concerns between **File System Location** (for Git identity) and **Editor Instance** (for GitHub API access).

### Key Capabilities
*   **Git Operations (CLI):** SSH authentication automatically switches keys based on which folder you are working in.
*   **GitHub Integration (GUI):** Pull Requests, Issues, and "Publish" features use the correct account based on which Cursor app you launch.

---

## 2. Directory & Identity Standards
The system determines your Git identity (`user.email`) and your SSH Identity Key (`id_ed25519`) based on where the repository resides on the disk.

| Scope | Directory Path | Git Identity | GitHub User | SSH Key |
| :--- | :--- | :--- | :--- | :--- |
| **Personal** | `~/Software/` | `101531405+aj-goldie@...` | `aj-goldie` | `id_ed25519_personal` |
| **Work** | `~/Software-Work/` | `alex.goldsmith@benefitsallin.com` | `bai-admin` | `id_ed25519_work` |
| **Other** | Any other path | *None (Commit blocked)* | *None* | *None* |

> **Critical Rule:** Always create or clone projects inside one of these two root directories. Do not work from the Desktop or Downloads folder, or Git will not know who you are.

---

## 3. The Editor Setup (Cursor 2.0)
Because VS Code/Cursor does not natively support context-aware multi-account switching for extensions, two separate instances are used.

### Instance A: "Cursor" (Personal - Default)
*   **Launch:** `/Applications/Cursor.app` or Spotlight "Cursor"
*   **Data Directory:** `~/Library/Application Support/Cursor`
*   **GitHub Auth:** Logged in as **aj-goldie**
*   **Use Case:** All personal projects in `~/Software/`

### Instance B: "Cursor Work"
*   **Launch:** `/Applications/Cursor Work.app` or Spotlight "Cursor Work"
*   **Data Directory:** `~/Library/Application Support/Cursor Work`
*   **GitHub Auth:** Logged in as **bai-admin**
*   **Use Case:** All work projects in `~/Software-Work/`

---

## 4. Operational Workflows

### A. Cloning a Repository (The "Alias" Step)
Because a `.git` folder does not exist yet during a clone, automatic detection fails. You must manually specify the **SSH Host Alias** to ensure the correct key is offered to GitHub.

*   **Personal Clone:**
    ```bash
    cd ~/Software
    git clone git@github-personal:aj-goldie/repo-name.git
    ```
*   **Work Clone:**
    ```bash
    cd ~/Software-Work
    git clone git@github-work:benefitsallin/repo-name.git
    ```

*(Note: Using standard `git@github.com` will cause a "Permission Denied" error because SSH will ambiguously offer the wrong key.)*

### B. Initializing a New Repo (`git init`)
1.  Navigate to the correct directory (e.g., `~/Software` for personal).
2.  Run `git init`.
3.  Make your first commit.
    *   *System Behavior:* Git detects the directory path via `.gitconfig`, loads the specific config, and applies the correct `user.email`.

### C. Pushing / Pulling
Once a repo is established (post-clone or post-init), you can simply run:
```bash
git push
```
*   *System Behavior:* The local `.git/config` or the global config rewrite rules will automatically map the remote URL to the correct SSH alias (`github-personal` or `github-work`). SSH will use the corresponding key.

### D. Using Editor Features (Publish / PRs)
1.  Open **Cursor Work** (for work projects).
2.  Open a folder in `~/Software-Work`.
3.  Click "Publish to GitHub" or use the Pull Request pane.
    *   *System Behavior:* Cursor uses the OAuth token stored in the "Cursor Work" secure storage (`bai-admin`), completely bypassing SSH.

---

## 5. Repository Contents

This repository contains **hardlinked** copies of the actual configuration files. Changes made here will reflect in the live system files and vice versa.

```
configs/
├── macos-personal-laptop/
│   ├── .gitconfig                  → ~/.gitconfig
│   ├── .gitconfig-personal         → ~/.gitconfig-personal
│   ├── .gitconfig-work             → ~/.gitconfig-work
│   ├── ssh-config                  → ~/.ssh/config
│   └── load-github-keys.sh         → ~/.ssh/load-github-keys.sh
│
└── windows-work-laptop/
    ├── .gitconfig                  → C:\Users\AlexGoldsmith\.gitconfig
    ├── .gitconfig-personal         → C:\Users\AlexGoldsmith\.gitconfig-personal
    ├── .gitconfig-work             → C:\Users\AlexGoldsmith\.gitconfig-work
    ├── gitconfig-system            → C:\Program Files\Git\etc\gitconfig
    └── Microsoft.PowerShell_profile.ps1 → $PROFILE

scripts/
└── CursorWork.applescript          → Source for /Applications/Cursor Work.app
```

> **Note:** Hardlinks are filesystem-level duplicates. The files in `configs/macos-personal-laptop/` ARE the same files on disk as the originals—not copies. Editing either location edits the same underlying data.

---

## 6. Technical Configuration Reference

### A. SSH Configuration (`~/.ssh/config`)
Defines aliases to force specific keys for specific "hosts", with macOS Keychain integration.
```ssh
Host *
    AddKeysToAgent yes
    UseKeychain yes
    IdentitiesOnly yes

Host github-personal
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_ed25519_personal

Host github-work
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_ed25519_work
```

### B. Git Configuration (`~/.gitconfig`)
Handles directory detection and identity switching.
```ini
[user]
    name = Alex Goldsmith

# Personal repos: ~/Software/
[includeIf "gitdir:~/Software/"]
    path = .gitconfig-personal

# Work repos: ~/Software-Work/
[includeIf "gitdir:~/Software-Work/"]
    path = .gitconfig-work
```

### C. Zsh Profile (`~/.zshrc`)
Ensures keys are loaded into the SSH agent on shell startup with Keychain integration.
```bash
# Start SSH agent if not running
if [ -z "$SSH_AUTH_SOCK" ]; then
  eval "$(ssh-agent -s)" > /dev/null
fi

# Load GitHub keys into agent
if [[ -f "$HOME/.ssh/load-github-keys.sh" ]]; then
    source "$HOME/.ssh/load-github-keys.sh"
fi
```

### D. GitHub.com UI - SSH Authentication Configuration

**aj-goldie** (Personal Account)
```
SSH keys → Authentication keys
alex.personal-acct.personal-laptop
SHA256:/cLCNgpLxQQg/W8W5Jo1KHprzXvNYF7/Apfm5UVTXtA
```

**bai-admin** (Work Account)
```
SSH keys → Authentication keys
alex.work-acct.personal-laptop
SHA256:+sfbdAvVUcD//5QFl0xBLUI35PiSQ6hL3DfIrTMrOhI
```

---

## 7. SSH Public Keys (Add to GitHub)

### Personal Account (aj-goldie)
```
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGcu8JyHmAOoYQnM7RhlYKw+Yn8e7YfPVqW3DwhIZMLk alex.personal-acct.personal-laptop
```

### Work Account (bai-admin)
```
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN6xbC52lUNlmAvi1IYs2kWRXJ32dEymUiVn3fgBpmfo alex.work-acct.personal-laptop
```

---

## 8. Troubleshooting

**Problem:** "Enter passphrase for key..." prompts every time.
**Cause:** Key not stored in macOS Keychain.
**Fix:** Run `ssh-add --apple-use-keychain ~/.ssh/id_ed25519_personal` (or `_work`) once.

**Problem:** "Permission denied (publickey)" when cloning.
**Cause:** You used `git clone git@github.com...` instead of the alias, OR the public key hasn't been added to GitHub.
**Fix:** Use `git clone git@github-personal:...` or `git@github-work:...`. Verify key is on GitHub.

**Problem:** "Please tell me who you are" error on commit.
**Cause:** You are trying to use Git outside of the designated `Software` or `Software-Work` folders.
**Fix:** Move your project into one of the designated folders.

**Problem:** Cursor Work app doesn't remember GitHub login.
**Cause:** First-time launch creates empty data directory.
**Fix:** Log in to GitHub via the GitHub extension in Cursor Work using your `bai-admin` account.


