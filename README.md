# Claude Account Switcher

A small Windows tool for switching the **Claude desktop app** between several Claude accounts (for example a work account and client accounts) in one click, without logging out and back in.

Each account keeps its own sign-in, settings, chats and Claude Code sessions. Switching takes a few seconds.

![dark mode window](https://img.shields.io/badge/UI-dark%20mode-1e1e22) ![Windows](https://img.shields.io/badge/platform-Windows%2010%20%7C%2011-0078d4) ![No install](https://img.shields.io/badge/install-none%20needed-4ade80)

> **Not an official Anthropic tool.** This is an independent community project. It is not made, endorsed or supported by Anthropic. "Claude" is a trademark of Anthropic, PBC and is used here only to describe what the tool works with. Use it at your own risk.

---

## Why

The Claude desktop app signs in to one account at a time. If your accounts use different email addresses, the only built-in way to change accounts is to sign out and sign back in, and your chats and Code sessions change with each sign-in.

This tool keeps a separate profile for each account on your PC and swaps between them for you.

## Features

- **One-click switching** between any number of accounts
- **Every account stays signed in**: you sign in to each account only once
- **Dark mode window** that is easy to understand
- **Add, rename and delete** accounts. Deleted accounts go to the Recycle Bin, so you can restore them.
- **Desktop shortcuts per account** (for example "Claude - Work") that switch in one double-click
- **Start menu entry and taskbar pin** with its own icon
- **No install, no admin rights, no internet access**: plain PowerShell that comes with Windows

## Requirements

- Windows 10 or 11
- The **Claude desktop app** from [claude.com/download](https://claude.com/download) (the standard installer, which installs the packaged `Claude_pzs8sxrjxfjjc` app), opened at least once
- Windows PowerShell 5.1 (already part of Windows)

## Install

1. **Download** this repository: click **Code > Download ZIP** on GitHub and extract it, or clone it:
   ```
   git clone https://github.com/<your-user>/claude-account-switcher.git
   ```
2. **Put the folder somewhere permanent**, for example `Documents\Tools\Claude Account Switcher`.
   Do **not** put it inside `%LOCALAPPDATA%\Claude-Data` (the tool refuses to run from there).
3. Double-click **`Claude Account Switcher.cmd`**. The window opens.
4. Optional: click **"Add this app to Start menu, desktop and taskbar"** at the bottom of the window. Then open **Start**, type **Claude Account Switcher**, right-click it and choose **Pin to taskbar**. (Windows only lets you do the pinning yourself.)

> Windows may warn about files downloaded from the internet. If the window does not open, right-click each `.ps1` and `.cmd` file > **Properties** > tick **Unblock** > **OK**.

## How to use

### First time: name your current account
When the window opens for the first time, it asks you to name the account Claude is signed in to right now, for example `Work`.

### Add another account
1. Click **+ Add a new account** and type a name, for example `Client A`.
2. Confirm. Claude closes and reopens **signed out**.
3. Sign in with that account. You only do this once.

### Switch accounts
Click **Switch** next to the account you want, then confirm. Claude closes and reopens already signed in to that account.

> Switching closes Claude. Finish your work first, because anything running in Claude (a chat reply, a Claude Code task) stops.
> After signing in to a brand-new account, wait about 30 seconds before switching away, so Claude has time to save the sign-in.

### Other buttons
| Button | What it does |
|---|---|
| **Rename** | Changes the name of the account you are signed in to right now |
| **Shortcut** | Puts a "Claude - *name*" icon on your desktop that switches to that account in one double-click |
| **Delete** | Removes a saved account **from this PC only** and moves it to the Recycle Bin. It does **not** delete the Claude account itself. The account you are using right now cannot be deleted; switch away from it first. |

## How it works

The Claude desktop app keeps everything for the signed-in account in one folder:

```
%LOCALAPPDATA%\Claude-Data\claude_pzs8sxrjxfjjc
```

When you switch, the tool:

1. Closes Claude (asks it to close, then ends it if it is still running in the system tray).
2. Renames the current folder to `claude_pzs8sxrjxfjjc~<current name>`.
3. Renames `claude_pzs8sxrjxfjjc~<target name>` back to `claude_pzs8sxrjxfjjc`.
4. Opens Claude again.

Folders are only **renamed in place**. Nothing is copied, uploaded or sent anywhere, and the tool never reads or touches your sign-in data. If any step fails (for example a file is still in use), it puts everything back and tells you that nothing was changed.

A small `.switcher-profile-name` file inside each profile folder records the account's name.

## Files

| File | Purpose |
|---|---|
| `Claude Account Switcher.cmd` | Double-click this to open the window |
| `ClaudeSwitcherUI.ps1` | The dark mode window |
| `ClaudeSwitcher.ps1` | The switching engine (also works on its own in a terminal) |
| `ClaudeSwitcher.ico` | App icon |

## Command line (optional)

The engine can be used without the window:

```powershell
.\ClaudeSwitcher.ps1                    # text menu
.\ClaudeSwitcher.ps1 -Status            # show active and saved accounts
.\ClaudeSwitcher.ps1 -SwitchTo Work     # switch to an account
.\ClaudeSwitcher.ps1 -Delete "Client A" # move a saved account to the Recycle Bin
.\ClaudeSwitcher.ps1 -Status -DryRun    # show what would happen, change nothing
```

## Limitations

- **One account at a time.** Switching restarts Claude; two accounts cannot be open side by side.
- **Some settings are shared.** Claude Code settings in your user folder (`%USERPROFILE%\.claude`) are the same for all accounts.
- **Claude updates.** A future version of the Claude app could change how it stores its data. If the folder layout changes, the tool stops with a message instead of doing anything risky.
- Windows only.

## Troubleshooting

| Problem | Fix |
|---|---|
| "Could not close Claude" | Right-click the Claude icon in the system tray (near the clock) > **Quit**, then try again. |
| "Some file is still in use. Nothing was changed." | Wait a minute and try again, or restart Windows. |
| "This tool is inside Claude's own data folder" | Move the tool's folder somewhere else, for example `Documents`. |
| Shortcuts or the taskbar pin stopped working after moving the folder | Open the app and click **"Add this app to Start menu, desktop and taskbar"** again. |
| The window does not open | Unblock the downloaded files (see Install), or run `Claude Account Switcher.cmd` from a terminal to see the error. |

**Never rename or delete folders in `%LOCALAPPDATA%\Claude-Data` yourself.** They hold each account's sign-in; let the tool manage them.

## Disclaimer

This project is not affiliated with, endorsed by, or supported by Anthropic. It changes only local folders on your own PC and does not interact with Anthropic's servers. Provided as is, without warranty of any kind.
