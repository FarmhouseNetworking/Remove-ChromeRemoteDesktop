<#
.SYNOPSIS
    Removes Chrome Remote Desktop (browser extension + host service) machine-wide. Run as SYSTEM via SuperOps.

.DESCRIPTION
    1. Blocklists the CRD extension (inomeogfingihgjfjlpeplalcfajhgai) by HKLM policy for Edge and Chrome.
       The browser disables it and stops it being reinstalled, for every user profile, the next time
       it reloads policy (browser restart, or automatically within about 3 hours).
    2. Uninstalls the "Chrome Remote Desktop Host" MSI and its service (chromoting) if present.
    3. Lists the extension folders left in user profiles. With -RemoveFolders it deletes them,
       skipping any user whose browser is running.
    Every action is printed with a Pacific timestamp so it can be copied into a ticket or change log.

.PARAMETER RemoveFolders
    Also delete leftover extension folders. Without it the script only reports them.
#>
param(
    [string]$ExtensionId = 'inomeogfingihgjfjlpeplalcfajhgai',
    [switch]$RemoveFolders
)

$ErrorActionPreference = 'Stop'
function Log($m) {
    $pt = [TimeZoneInfo]::ConvertTimeBySystemTimeZoneId((Get-Date), 'Pacific Standard Time')
    Write-Output ("[{0:yyyy-MM-dd HH:mm:ss} PT] {1}" -f $pt, $m)
}

# --- 1. Policy blocklist (Edge + Chrome) --------------------------------------------------
$policyRoots = @{
    'Edge'   = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge\ExtensionInstallBlocklist'
    'Chrome' = 'HKLM:\SOFTWARE\Policies\Google\Chrome\ExtensionInstallBlocklist'
}
foreach ($b in $policyRoots.Keys) {
    $key = $policyRoots[$b]
    if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
    $props = (Get-ItemProperty -Path $key).PSObject.Properties |
             Where-Object { $_.Name -match '^\d+$' }
    if ($props.Value -contains $ExtensionId) {
        Log "$b blocklist already contains $ExtensionId - no change"
        continue
    }
    $next = 1
    if ($props) { $next = ([int[]]$props.Name | Measure-Object -Maximum).Maximum + 1 }
    New-ItemProperty -Path $key -Name "$next" -Value $ExtensionId -PropertyType String -Force | Out-Null
    Log "CHANGE: added $ExtensionId to $b ExtensionInstallBlocklist (value $next) at $key"
}

# --- 2. CRD host (MSI + service) ----------------------------------------------------------
$uninstallKeys = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
$hosts = Get-ItemProperty $uninstallKeys -ErrorAction SilentlyContinue |
         Where-Object { $_.DisplayName -like 'Chrome Remote Desktop*' }
if (-not $hosts) { Log 'Chrome Remote Desktop Host: not installed' }
foreach ($h in $hosts) {
    $guid = $h.PSChildName
    Log "Found host: $($h.DisplayName) $($h.DisplayVersion) [$guid]"
    if ($guid -match '^\{[0-9A-F-]+\}$') {
        $p = Start-Process msiexec.exe -ArgumentList "/x $guid /qn /norestart" -Wait -PassThru
        Log "CHANGE: msiexec /x $guid exit code $($p.ExitCode)"
    } else {
        Log "Uninstall string (run manually): $($h.UninstallString)"
    }
}
$svc = Get-Service -Name 'chromoting' -ErrorAction SilentlyContinue
if ($svc) {
    Stop-Service chromoting -Force -ErrorAction SilentlyContinue
    sc.exe delete chromoting | Out-Null
    Log 'CHANGE: stopped and deleted service chromoting'
} else { Log 'Service chromoting: not present' }

# --- 3. Leftover extension folders in every profile ---------------------------------------
$found = Get-ChildItem 'C:\Users\*\AppData\Local\Microsoft\Edge\User Data\*\Extensions',
                       'C:\Users\*\AppData\Local\Google\Chrome\User Data\*\Extensions' `
                       -Directory -ErrorAction SilentlyContinue |
         ForEach-Object { Join-Path $_.FullName $ExtensionId } |
         Where-Object { Test-Path $_ }
if (-not $found) { Log 'No extension folders found' }
foreach ($f in $found) {
    $user = ($f -split '\\')[2]
    if (-not $RemoveFolders) { Log "Folder present (report only): $f"; continue }
    $running = Get-CimInstance Win32_Process -Filter "Name='msedge.exe' OR Name='chrome.exe'" |
               Where-Object { (Invoke-CimMethod -InputObject $_ -MethodName GetOwner).User -eq $user }
    if ($running) { Log "SKIPPED (browser open for $user): $f"; continue }
    Remove-Item $f -Recurse -Force
    Log "CHANGE: deleted $f"
}
Log 'Done. The blocklist takes effect when the browser next restarts or refreshes policy (edge://policy > Reload policies).'