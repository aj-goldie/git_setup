# Dual-Identity Development Environment (macOS)

This Mac uses a two-part routing system to keep personal and work development separate:

1. Repository location controls CLI Git identity and SSH key.
2. Cursor launcher controls GUI GitHub account by selecting a data directory.

Cursor profiles exist inside each data directory, but they are a secondary convention layer. They set defaults like clone destination, file dialog root, and preferred profile for new windows. The real isolation boundary for GitHub extension auth is the separate `--user-data-dir`.

## Core Rule

Always get both of these right:

| Concern | Personal | Work |
| :--- | :--- | :--- |
| Repo lives under | `~/Software/` | `~/Software-Work/` |
| Cursor launcher | `Cursor Personal.app` | `Cursor Work.app` |
| GitHub user | `aj-goldie` | `bai-admin` |
| SSH alias | `github-personal` | `github-work` |
| SSH key | `~/.ssh/id_ed25519_personal` | `~/.ssh/id_ed25519_work` |

These two routing systems are independent.

- If you open a work repo in `Cursor Personal.app`, terminal Git will still use the work key and work email because the folder path is correct, but Cursor's Publish / PR / Issues UI will use the personal GitHub login because the app silo is wrong.
- If you put a repo in the wrong root folder, Cursor may be logged into the correct account but CLI Git will use the wrong identity or fail to resolve one at all.

That is the strange custom convention in one sentence: folder chooses Git, launcher chooses GitHub UI.

## Canonical Folder Layout

| Scope | Root | Git identity | GitHub user |
| :--- | :--- | :--- | :--- |
| Personal | `~/Software/` | `101531405+aj-goldie@users.noreply.github.com` | `aj-goldie` |
| Work | `~/Software-Work/` | `alex.goldsmith@benefitsallin.com` | `bai-admin` |
| Anything else | anywhere else | none guaranteed | none guaranteed |

Practical rule: do not create or clone repos on the Desktop, in Downloads, or in random temp folders if you expect this setup to route identity correctly.

## What The Three Cursor App Bundles Actually Are

There is only one real Cursor install:

- `/Applications/Cursor.app`
  This is the actual Electron app bundle.

The other two are wrapper launchers:

- `/Applications/Cursor Personal.app`
  AppleScript applet that runs:
  `open -na '/Applications/Cursor.app' --args --user-data-dir '/Users/alexgoldsmith/Library/Application Support/Cursor' --profile 'Personal Laptop - PERSONAL'`

- `/Applications/Cursor Work.app`
  AppleScript applet that runs:
  `open -na '/Applications/Cursor.app' --args --user-data-dir '/Users/alexgoldsmith/Library/Application Support/Cursor Work' --profile 'Personal Laptop - WORK'`

The source for those wrappers lives here:

- [scripts/macos/CursorPersonal.applescript](/Users/alexgoldsmith/Software/git_setup/scripts/macos/CursorPersonal.applescript:1)
- [scripts/macos/CursorWork.applescript](/Users/alexgoldsmith/Software/git_setup/scripts/macos/CursorWork.applescript:1)

## How Cursor Isolation Works On This Mac

### 1. Separate data directories

The important split is:

- Personal data dir: `~/Library/Application Support/Cursor`
- Work data dir: `~/Library/Application Support/Cursor Work`

Those directories hold the state that matters for account separation: extension storage, cookies, session state, secure storage references, workspace state, and related UI state.

Extension binaries may still be installed in a shared location on disk, but the account/session state that matters for GitHub integration is isolated by the separate data directories.

### 2. Separate profiles inside each data directory

Inside those silos, the launchers also select distinct profiles:

- Personal profile: `Personal Laptop - PERSONAL`
- Work profile: `Personal Laptop - WORK`

Those profiles are mainly there to reinforce the convention:

- Personal profile defaults file dialogs and clone destinations to `~/Software`
- Work profile defaults file dialogs and clone destinations to `~/Software-Work`

That means the profile helps you stay in the right library, but the profile is not the main security boundary. The data dir is.

### 3. Raw `Cursor.app` vs wrapper apps

Launching raw `/Applications/Cursor.app` uses the default Cursor data dir, which on this machine is the personal silo.

So:

- `Cursor Personal.app` is the explicit personal launcher
- `Cursor Work.app` is the explicit work launcher
- raw `Cursor.app` behaves like the base personal install, but is less explicit

Operationally, prefer the wrapper launchers for identity-sensitive work.

## How Git Identity Is Selected

Global Git config uses directory-based includes:

```ini
[includeIf "gitdir:~/Software/"]
    path = .gitconfig-personal

[includeIf "gitdir:~/Software-Work/"]
    path = .gitconfig-work
```

Live files:

- [configs/macos-personal-laptop/.gitconfig](/Users/alexgoldsmith/Software/git_setup/configs/macos-personal-laptop/.gitconfig:1)
- [configs/macos-personal-laptop/.gitconfig-personal](/Users/alexgoldsmith/Software/git_setup/configs/macos-personal-laptop/.gitconfig-personal:1)
- [configs/macos-personal-laptop/.gitconfig-work](/Users/alexgoldsmith/Software/git_setup/configs/macos-personal-laptop/.gitconfig-work:1)

Behavior:

- Repos under `~/Software/` get the personal email and GitHub user.
- Repos under `~/Software-Work/` get the work email and GitHub user.
- Repos outside those roots do not get a scoped `user.email`, so commits are not safely attributable and may fail with "Please tell me who you are."

The personal include adds:

- `user.email = 101531405+aj-goldie@users.noreply.github.com`
- `github.user = aj-goldie`
- HTTPS rewrite to `git@github-personal:`

The work include adds:

- `user.email = alex.goldsmith@benefitsallin.com`
- `github.user = bai-admin`
- HTTPS rewrite to `git@github-work:`

## How SSH Key Selection Works

SSH aliases force GitHub traffic onto the correct key:

```ssh
Host github-personal
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_ed25519_personal

Host github-work
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_ed25519_work
```

Live file:

- [configs/macos-personal-laptop/ssh-config](/Users/alexgoldsmith/Software/git_setup/configs/macos-personal-laptop/ssh-config:1)

Keys are loaded into the agent from:

- [scripts/macos/load-github-keys.sh](/Users/alexgoldsmith/Software/git_setup/scripts/macos/load-github-keys.sh:1)

and sourced from shell startup files so the aliases work without repeated passphrase prompts.

## Day-To-Day Workflows

### Personal repo

1. Create or clone the repo under `~/Software/`.
2. Launch `Cursor Personal.app`.
3. Open that repo there.

Clone example:

```bash
cd ~/Software
git clone git@github-personal:OWNER/repo-name.git
```

### Work repo

1. Create or clone the repo under `~/Software-Work/`.
2. Launch `Cursor Work.app`.
3. Open that repo there.

Clone example:

```bash
cd ~/Software-Work
git clone git@github-work:OWNER/repo-name.git
```

`OWNER` can be either a user or an org, for example `bai-admin` or `benefitsallin`.

### Why clone must use the alias

Before a repo exists locally, Git cannot yet apply the directory-based include logic to an existing `.git` directory. That means initial clone is the one time you must be explicit about the host alias.

After the repo exists:

- remotes may already be stored as `git@github-personal:...` or `git@github-work:...`
- HTTPS remotes can be rewritten by the scoped Git config to the correct SSH alias

### Cursor Publish / PR / Issues

Cursor GUI GitHub features do not care which SSH key terminal Git would use. They care which account is logged into the data dir for the running Cursor instance.

So the rule is simple:

- Personal repo + personal launcher
- Work repo + work launcher

If the launcher is wrong, Publish / PR / Issues will be wrong even if `git push` in the terminal is correct.

## Repo-Managed Live Config

On macOS, the live files are symlinked into this repo. They are not hardlinked.

Current pattern:

- `~/.gitconfig` -> `configs/macos-personal-laptop/.gitconfig`
- `~/.gitconfig-personal` -> `configs/macos-personal-laptop/.gitconfig-personal`
- `~/.gitconfig-work` -> `configs/macos-personal-laptop/.gitconfig-work`
- `~/.ssh/config` -> `configs/macos-personal-laptop/ssh-config`
- `~/.ssh/load-github-keys.sh` -> `scripts/macos/load-github-keys.sh`
- `~/.gitattributes_global` -> `configs/shared/.gitattributes_global`
- `~/.githooks` -> `configs/shared/githooks`
- `~/.local/bin/nbstripout-safe` -> `scripts/shared/nbstripout-safe`

The setup script that manages those symlinks is:

- [scripts/macos/Git-Setup.sh](/Users/alexgoldsmith/Software/git_setup/scripts/macos/Git-Setup.sh:33)

It analyzes the current state, fixes bad symlinks, and creates backups before replacing files.

## What In This Repo Is Authoritative

Authoritative for the macOS setup:

- `configs/macos-personal-laptop/*`
- `configs/shared/*`
- `scripts/macos/load-github-keys.sh`
- `scripts/macos/CursorPersonal.applescript`
- `scripts/macos/CursorWork.applescript`
- the live files in `~/Library/Application Support/Cursor*` when checking actual Cursor behavior

Not authoritative:

- exported `.code-profile` files in the repo

Those exports are snapshots and may lag behind the live profiles inside the Cursor data directories.

## Technical Reference

### Personal launcher

```applescript
do shell script "open -na '/Applications/Cursor.app' --args --user-data-dir '/Users/alexgoldsmith/Library/Application Support/Cursor' --profile 'Personal Laptop - PERSONAL'"
```

### Work launcher

```applescript
do shell script "open -na '/Applications/Cursor.app' --args --user-data-dir '/Users/alexgoldsmith/Library/Application Support/Cursor Work' --profile 'Personal Laptop - WORK'"
```

### Personal profile defaults

The personal silo is configured to nudge work into the personal library, including:

- `files.dialog.defaultPath = /Users/alexgoldsmith/Software`
- `git.defaultCloneDirectory = /Users/alexgoldsmith/Software`
- `window.newWindowProfile = Personal Laptop - PERSONAL`

### Work profile defaults

The work silo is configured to nudge work into the work library, including:

- `files.dialog.defaultPath = /Users/alexgoldsmith/Software-Work`
- `git.defaultCloneDirectory = /Users/alexgoldsmith/Software-Work`
- `window.newWindowProfile = Personal Laptop - WORK`

## SSH Key Records

GitHub account mapping:

- Personal account: `aj-goldie`
- Work account: `bai-admin`

Configured key labels:

- Personal key label: `alex.personal-acct.personal-laptop`
- Work key label: `alex.work-acct.personal-laptop`

Fingerprints recorded when this setup was documented:

- Personal: `SHA256:/cLCNgpLxQQg/W8W5Jo1KHprzXvNYF7/Apfm5UVTXtA`
- Work: `SHA256:+sfbdAvVUcD//5QFl0xBLUI35PiSQ6hL3DfIrTMrOhI`

## Troubleshooting

### "Permission denied (publickey)" on clone

Cause:

- you used `git@github.com:...` instead of the alias
- or the matching public key is not added to the correct GitHub account

Fix:

- personal: `git clone git@github-personal:OWNER/repo.git`
- work: `git clone git@github-work:OWNER/repo.git`

### Commit says "Please tell me who you are"

Cause:

- the repo is outside `~/Software/` and `~/Software-Work/`

Fix:

- move the repo into the correct root, or create it there in the first place

### Cursor is showing the wrong GitHub account

Cause:

- you opened the repo in the wrong launcher
- or that data dir is logged into the wrong GitHub account

Fix:

- personal repo -> `Cursor Personal.app`
- work repo -> `Cursor Work.app`
- if needed, sign out and back in within that specific Cursor silo

### Cursor Work forgot its login

Cause:

- the work data directory was new, cleared, or recreated

Fix:

- launch `Cursor Work.app`
- sign into the GitHub extension again as `bai-admin`

### SSH asks for the passphrase every time

Cause:

- the key is not loaded into the agent with Keychain integration

Fix:

```bash
ssh-add --apple-use-keychain ~/.ssh/id_ed25519_personal
ssh-add --apple-use-keychain ~/.ssh/id_ed25519_work
```

### Wrapper app launches but behavior seems off after a Cursor update

Cause:

- the base `Cursor.app` was updated, while the wrapper applets stayed the same

Fix:

- verify the wrapper still points to `/Applications/Cursor.app`
- verify Cursor still honors `--user-data-dir` and `--profile`
- if needed, rebuild the wrapper applets from the AppleScript sources in this repo
