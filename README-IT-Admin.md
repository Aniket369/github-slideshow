# IT Utility Tools – Admin Setup Guide

This guide explains how to deploy the tool to your organisation so that
employees can click buttons on the website and have scripts run on their
own PCs automatically.

---

## How It Works (Plain English)

```
User opens website → clicks "Clear Teams Cache"
    → browser opens a special link:  ittools://clear-teams-cache
    → Windows recognises "ittools://" (because we registered it via SCCM)
    → Windows runs the PowerShell script on that user's own PC
    → A PowerShell window opens and clears the cache
```

The key idea: **SCCM deploys a small "listener" to every PC once**.
After that, the website can trigger scripts on any PC without needing
any server-side access to that machine.

---

## Files Overview

```
setup/
  ├── Setup-ITTools.ps1      ← SCCM install script  (run this via SCCM)
  ├── Uninstall-ITTools.ps1  ← SCCM uninstall script
  ├── handler.ps1            ← Receives the button click, calls correct script
  ├── Clear-TeamsCache.ps1   ← Clears Teams cache and restarts Teams
  └── Restart-PC.ps1         ← Restarts the PC with a 60-second countdown

tools.html                   ← The website users open in their browser
```

---

## Step-by-Step: Deploy via SCCM

### Step 1 – Copy files to your SCCM Content Share

Copy the entire `setup/` folder to your SCCM content library / package source
(e.g. `\\YourSCCMServer\Sources\IT-Tools\`).

All 5 files must be in the **same folder**:
- `Setup-ITTools.ps1`
- `Uninstall-ITTools.ps1`
- `handler.ps1`
- `Clear-TeamsCache.ps1`
- `Restart-PC.ps1`

---

### Step 2 – Create an Application in SCCM

1. Open the **Configuration Manager Console**
2. Go to **Software Library → Application Management → Applications**
3. Click **Create Application** → choose **Manually specify the application information**
4. Fill in the details:

| Field | Value |
|---|---|
| Name | IT Utility Tools |
| Version | 1.0 |
| Publisher | Your IT Team |

5. Click **Next** until you reach **Deployment Types**
6. Click **Add** to create a deployment type
7. Choose **Script Installer**

---

### Step 3 – Configure the Deployment Type

On the **Content** tab:
- **Content location**: `\\YourSCCMServer\Sources\IT-Tools\`

On the **Programs** tab:
- **Install program**:
  ```
  powershell.exe -ExecutionPolicy Bypass -NonInteractive -File Setup-ITTools.ps1
  ```
- **Uninstall program**:
  ```
  powershell.exe -ExecutionPolicy Bypass -NonInteractive -File Uninstall-ITTools.ps1
  ```
- **Run mode**: Run with administrative rights
- **Run**: Whether or not a user is logged on

On the **Detection Method** tab:
- Click **Add Clause**
- **Setting type**: File System
- **Type**: File
- **Path**: `C:\IT-Tools`
- **File or folder name**: `handler.ps1`
- **This file or folder is associated with a 32-bit application**: No
- Tick **The file system setting must exist on the target system**

---

### Step 4 – Deploy to All PCs

1. Right-click your new application → **Deploy**
2. **Collection**: Choose your All Workstations (or a test group first)
3. **Purpose**: Required
4. Click through and complete the wizard

SCCM will push the setup to every machine in the collection.
This installs 5 files to `C:\IT-Tools\` and registers the `ittools://`
URL protocol in Windows.

---

### Step 5 – Host the Website

The `tools.html` file is the webpage users visit.
You have two options:

**Option A – Simple (no web server needed)**
Put `tools.html` on a network share (e.g. `\\server\IT-Tools\tools.html`).
Users open it by pasting that path into their browser's address bar,
or you can create a shortcut on the desktop.

**Option B – Proper Intranet (recommended)**
Put `tools.html` on your IIS intranet web server so users can access it
via a friendly URL like `http://intranet/it-tools`.

> **Tip**: You can also pin the URL as a shortcut in the Windows Taskbar
> or push it as a browser bookmark via Group Policy.

---

## Testing

Before deploying to everyone:

1. Deploy to a **test collection** (1–2 machines)
2. Wait for SCCM to install (or force sync with **Machine Policy Retrieval**)
3. On the test machine, open `tools.html` in Edge/Chrome
4. Click **Clear Teams Cache**
5. Browser will ask *"Allow this page to open IT Tools?"* → click **Open**
6. A PowerShell window should appear and run the script

If nothing happens → check that `C:\IT-Tools\handler.ps1` exists on the machine
and that the registry key `HKLM:\SOFTWARE\Classes\ittools` was created.

---

## Troubleshooting

| Problem | Fix |
|---|---|
| Nothing happens when button is clicked | SCCM hasn't deployed yet, or installation failed. Check `C:\IT-Tools\` exists. |
| Browser shows "this site is trying to open..." but then nothing | User clicked Block instead of Open. Tell them to click Allow/Open. |
| PowerShell window opens but shows an error | Check script is not blocked. Run `Unblock-File -Path C:\IT-Tools\*.ps1` on the machine. |
| Teams doesn't restart after cache clear | Teams path may differ. Edit `Clear-TeamsCache.ps1` and adjust the path at the bottom. |

---

## Updating Scripts Later

If you need to change what a script does (e.g. update the Teams restart path):

1. Edit the relevant `.ps1` file in your SCCM package source
2. In SCCM, update the package content and increment the version
3. SCCM will push the updated files to all PCs

---

## Security Notes

- The scripts run as the **logged-on user** (not SYSTEM), so they have the
  same rights as the person clicking the button.
- The `ittools://` protocol is only registered on managed corporate PCs via
  SCCM, so external/personal machines cannot use it.
- Restart PC requires no extra privileges (any user can restart their own PC).
- Clearing Teams cache only touches the current user's `%APPDATA%` folder.
