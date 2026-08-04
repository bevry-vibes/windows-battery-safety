#Requires -Version 7.6
<#
.SYNOPSIS
    windows-battery-safety - configure Windows battery thresholds so the
    low-battery warning leaves you enough time to plug in before hibernate.

.DESCRIPTION
    Non-interactive CLI. Applies a preset (standard | safe) or a custom triple
    of battery thresholds to the currently active power scheme via powercfg,
    using the documented setting GUIDs, then verifies the applied values.

    Thresholds (percent of battery capacity, in drain order):
      Low      - the low battery warning appears               (Windows default 10)
      Reserve  - the reserve ("plug in now") warning appears   (Windows default 7)
      Critical - the critical battery action (hibernate) runs  (Windows default 5)

    Must satisfy: low > reserve > critical, each within 0-100.

    Exit codes: 0 = success, 1 = powercfg/verification failure, 2 = usage error.

.EXAMPLE
    pwsh -File .\windows-battery-safety.ps1 safe

.EXAMPLE
    pwsh -File .\windows-battery-safety.ps1 custom 25 18 12
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)] [string]$Mode,
    [Parameter(Position = 1)] [int]$Low,
    [Parameter(Position = 2)] [int]$Reserve,
    [Parameter(Position = 3)] [int]$Critical
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Documented GUIDs - Microsoft Learn, "Battery settings" subgroup.
# https://learn.microsoft.com/en-us/windows-hardware/customize/power-settings/battery-settings
$SubBattery   = 'e73a048d-bf27-4f12-9731-8b2076e8891f' # SUB_BATTERY
$GuidLow      = '8183ba9a-e910-48da-8769-14ae6dc1170a' # BATLEVELLOW
$GuidReserve  = 'f3c5027d-cd16-4930-aa6b-90db844a8f00' # BATLEVELRESERVE - no alias on some builds, GUID required
$GuidCritical = '9a66d8d7-4ff7-4ef9-b5a2-5a326ca2a469' # BATLEVELCRIT

$Presets = @{
    standard = @{ Low = 10; Reserve = 7;  Critical = 5  } # Windows defaults
    safe     = @{ Low = 20; Reserve = 15; Critical = 10 } # warning ~10% earlier, 10-point margin
}

function Show-Usage {
    @'
Usage: pwsh -File .\windows-battery-safety.ps1 <mode> [<low> <reserve> <critical>]

Modes:
  standard                          Windows defaults:  low 10, reserve 7, critical 5
  safe                              Safer margins:     low 20, reserve 15, critical 10
  custom <low> <reserve> <critical> Custom percentages, must satisfy
                                    low > reserve > critical, each within 0-100
                                    e.g. custom 25 18 12

Exit codes: 0 = success, 1 = powercfg/verification failure, 2 = usage error.
'@ | Write-Host
    exit 2
}

function Get-BatteryThreshold([string]$SettingGuid) {
    $out = powercfg /query SCHEME_CURRENT $SubBattery $SettingGuid 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "FAILED: powercfg /query for $SettingGuid`n$out"
        exit 1
    }
    $ac = ([regex]'Current AC Power Setting Index:\s*0x([0-9a-fA-F]+)').Match("$out")
    $dc = ([regex]'Current DC Power Setting Index:\s*0x([0-9a-fA-F]+)').Match("$out")
    if (-not ($ac.Success -and $dc.Success)) {
        Write-Host "FAILED: could not parse powercfg output for $SettingGuid`n$out"
        exit 1
    }
    [pscustomobject]@{
        AC = [Convert]::ToInt32($ac.Groups[1].Value, 16)
        DC = [Convert]::ToInt32($dc.Groups[1].Value, 16)
    }
}

function Set-BatteryThreshold([string]$SettingGuid, [int]$Value) {
    foreach ($flag in '/setacvalueindex', '/setdcvalueindex') {
        $out = powercfg $flag SCHEME_CURRENT $SubBattery $SettingGuid $Value 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "FAILED: powercfg $flag $SettingGuid $Value`n$out"
            exit 1
        }
    }
}

# --- resolve mode to a target triple ---
switch ($Mode) {
    { $_ -in 'standard', 'safe' } {
        $Low = $Presets[$_].Low
        $Reserve = $Presets[$_].Reserve
        $Critical = $Presets[$_].Critical
    }
    'custom' {
        $bound = $PSBoundParameters.Keys
        if (-not ($bound -contains 'Low' -and $bound -contains 'Reserve' -and $bound -contains 'Critical')) {
            Write-Host 'ERROR: custom requires <low> <reserve> <critical>.'
            Show-Usage
        }
    }
    default {
        if ($Mode) { Write-Host "ERROR: unknown mode '$Mode'." }
        Show-Usage
    }
}

# --- validate ranges and ordering ---
foreach ($pair in @(@('low', $Low), @('reserve', $Reserve), @('critical', $Critical))) {
    if ($pair[1] -lt 0 -or $pair[1] -gt 100) {
        Write-Host "ERROR: $($pair[0]) value $($pair[1]) is out of range (0-100)."
        exit 2
    }
}
if (-not ($Low -gt $Reserve -and $Reserve -gt $Critical)) {
    Write-Host "ERROR: thresholds must satisfy low > reserve > critical (got low=$Low reserve=$Reserve critical=$Critical)."
    exit 2
}

# --- capture before ---
$before = @{
    Low      = Get-BatteryThreshold $GuidLow
    Reserve  = Get-BatteryThreshold $GuidReserve
    Critical = Get-BatteryThreshold $GuidCritical
}

# --- apply (AC and DC) and activate ---
Set-BatteryThreshold $GuidLow $Low
Set-BatteryThreshold $GuidReserve $Reserve
Set-BatteryThreshold $GuidCritical $Critical
$out = powercfg /setactive SCHEME_CURRENT 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "FAILED: powercfg /setactive`n$out"
    exit 1
}

# --- verify after ---
$after = @{
    Low      = Get-BatteryThreshold $GuidLow
    Reserve  = Get-BatteryThreshold $GuidReserve
    Critical = Get-BatteryThreshold $GuidCritical
}

$targets = @{ Low = $Low; Reserve = $Reserve; Critical = $Critical }
$rows = foreach ($name in 'Low', 'Reserve', 'Critical') {
    $ok = $after[$name].AC -eq $targets[$name] -and $after[$name].DC -eq $targets[$name]
    [pscustomobject]@{
        Threshold = $name
        Before    = "$($before[$name].AC)/$($before[$name].DC)"
        After     = "$($after[$name].AC)/$($after[$name].DC)"
        Target    = $targets[$name]
        Verified  = $ok ? 'yes' : 'NO'
    }
}

Write-Host "Mode: $Mode (values are AC/DC percentages of battery capacity)"
$rows | Format-Table -AutoSize | Out-String | Write-Host

if ($rows.Verified -contains 'NO') {
    Write-Host 'FAILED: one or more thresholds did not apply.'
    exit 1
}

Write-Host "OK: battery thresholds applied to the active power scheme - low $Low%, reserve $Reserve%, critical $Critical%."
exit 0

