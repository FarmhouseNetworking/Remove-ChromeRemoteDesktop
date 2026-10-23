# Remove-ChromeRemoteDesktop

Removes Chrome Remote Desktop from a Windows computer and stops it from coming back. Covers the browser extension in Microsoft Edge and Google Chrome for every user profile, plus the Chrome Remote Desktop Host service if it's installed. Built to run under SYSTEM through the SuperOps RMM agent.

An unmanaged remote-access tool is a common foothold in tech-support scams and break-ins. If it isn't sanctioned on the machine, this script removes it.

## Usage

Run it in SuperOps as SYSTEM, or from an elevated PowerShell prompt:

```powershell
# Block the extension, remove the host if present, and report leftover folders
.\Remove-ChromeRemoteDesktop.ps1

# Same, and also delete the leftover extension folders
.\Remove-ChromeRemoteDesktop.ps1 -RemoveFolders
```

| Parameter | Default | Purpose |
|---|---|---|
| `-ExtensionId` | `inomeogfingihgjfjlpeplalcfajhgai` | Chrome Web Store ID of the Chrome Remote Desktop extension |
| `-RemoveFolders` | off | Delete leftover extension folders. Skips any user whose browser is open. |

## How it works

1. **Blocks the extension by policy.** It adds the extension ID to `ExtensionInstallBlocklist` under:
   - `HKLM\SOFTWARE\Policies\Microsoft\Edge`
   - `HKLM\SOFTWARE\Policies\Google\Chrome`

   It uses the next free value number, so existing blocklist entries stay in place. Each browser disables the extension in every profile and won't let anyone reinstall it. This happens the next time the browser loads policy: on restart, after **Reload policies** at `edge://policy` or `chrome://policy`, or on the browser's own refresh within a few hours.
2. **Removes the host.** If a "Chrome Remote Desktop Host" MSI is registered, it runs `msiexec /x {ProductCode} /qn /norestart`. It also stops and deletes the `chromoting` service if it exists.
3. **Cleans up folders.** It finds `...\User Data\<profile>\Extensions\<id>` under every user, for both browsers. By default it only reports these folders. With `-RemoveFolders` it deletes them, unless that user has Edge or Chrome running.

It never runs user-profile code, and it doesn't use `Win32_Product`.

## Example output

```
[2026-10-23 14:45:08 PT] CHANGE: added inomeogfingihgjfjlpeplalcfajhgai to Edge ExtensionInstallBlocklist (value 1) at HKLM:\SOFTWARE\Policies\Microsoft\Edge\ExtensionInstallBlocklist
[2026-10-23 14:45:08 PT] CHANGE: added inomeogfingihgjfjlpeplalcfajhgai to Chrome ExtensionInstallBlocklist (value 1) at HKLM:\SOFTWARE\Policies\Google\Chrome\ExtensionInstallBlocklist
[2026-10-23 14:45:08 PT] Chrome Remote Desktop Host: not installed
[2026-10-23 14:45:08 PT] Service chromoting: not present
[2026-10-23 14:45:08 PT] Folder present (report only): C:\Users\<user>\AppData\Local\Microsoft\Edge\User Data\Default\Extensions\inomeogfingihgjfjlpeplalcfajhgai
[2026-10-23 14:45:08 PT] Done. The blocklist takes effect when the browser next restarts or refreshes policy (edge://policy > Reload policies).
```

Every line that changes something starts with `CHANGE:`, so you can paste the output straight into a ticket or change log. Running the script again is safe and reports "no change".

## Notes

- If the browser's `ExtensionSettings` policy has a matching entry for this ID, that entry overrides the blocklist. A wildcard (`*`) entry with an install mode set does too. Check `edge://policy` after running.
- To allow Chrome Remote Desktop again, delete the blocklist value the script added.
- Timestamps are Pacific time.