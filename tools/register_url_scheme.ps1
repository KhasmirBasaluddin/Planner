<#
.SYNOPSIS
  Registers the `planner://` URL scheme with Windows for the current user.

.DESCRIPTION
  Sign-in links — email confirmation, password reset, and the Google/Microsoft
  OAuth callback — redirect to `planner://auth-callback`. Windows only knows
  where to send that if the scheme is registered, so without this the browser
  shows "no app is associated with this link" and sign-in appears to hang.

  Writes to HKCU (per-user), so no administrator rights are needed and nothing
  outside your own profile is touched.

.PARAMETER ExePath
  Path to planner.exe. Defaults to the debug build in this repository.

.PARAMETER Remove
  Unregisters the scheme instead of registering it.

.EXAMPLE
  # Register the local debug build
  .\tools\register_url_scheme.ps1

.EXAMPLE
  # Register an installed release build
  .\tools\register_url_scheme.ps1 -ExePath "C:\Program Files\Planner\planner.exe"

.EXAMPLE
  # Undo
  .\tools\register_url_scheme.ps1 -Remove

.NOTES
  Re-run this after changing where planner.exe lives — the registry stores an
  absolute path. A debug build moved or rebuilt elsewhere will leave a stale
  entry that silently fails.
#>

[CmdletBinding()]
param(
    [string]$ExePath,
    [switch]$Remove
)

$ErrorActionPreference = 'Stop'

$scheme  = 'planner'
$root    = "HKCU:\Software\Classes\$scheme"

if ($Remove) {
    if (Test-Path $root) {
        Remove-Item -Path $root -Recurse -Force
        Write-Host "Unregistered ${scheme}:// " -NoNewline
        Write-Host "(removed $root)" -ForegroundColor DarkGray
    } else {
        Write-Host "${scheme}:// was not registered; nothing to remove." -ForegroundColor DarkGray
    }
    return
}

# Default to the debug build next to this script's repository root.
if (-not $ExePath) {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $ExePath  = Join-Path $repoRoot 'build\windows\x64\runner\Debug\planner.exe'
}

if (-not (Test-Path $ExePath)) {
    Write-Error @"
Could not find planner.exe at:
  $ExePath

Build it first with `flutter build windows` (or `flutter run -d windows`),
or pass the path explicitly:
  .\tools\register_url_scheme.ps1 -ExePath "C:\path\to\planner.exe"
"@
    exit 1
}

$ExePath = (Resolve-Path $ExePath).Path

New-Item -Path $root -Force | Out-Null
Set-ItemProperty -Path $root -Name '(Default)' -Value "URL:$scheme Protocol"
# The presence of this value — not its content — is what marks the key as a
# URL protocol handler.
Set-ItemProperty -Path $root -Name 'URL Protocol' -Value ''

New-Item -Path "$root\DefaultIcon" -Force | Out-Null
Set-ItemProperty -Path "$root\DefaultIcon" -Name '(Default)' -Value "`"$ExePath`",0"

New-Item -Path "$root\shell\open\command" -Force | Out-Null
# %1 receives the full callback URL, which app_links reads on startup.
Set-ItemProperty -Path "$root\shell\open\command" -Name '(Default)' -Value "`"$ExePath`" `"%1`""

Write-Host "Registered " -NoNewline
Write-Host "${scheme}://" -ForegroundColor Green -NoNewline
Write-Host " -> $ExePath"
Write-Host ""
Write-Host "Test it with:" -ForegroundColor DarkGray
Write-Host "  start `"$scheme`://auth-callback`"" -ForegroundColor DarkGray
