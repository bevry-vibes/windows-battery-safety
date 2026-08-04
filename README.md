# Windows Battery Safety

Configure Windows battery thresholds so the low-battery warning actually leaves you time to plug in before the machine hibernates.

## The problem

Windows defaults give you almost no margin:

```
100% ──────── 10% ──────── 7% ──────── 5% ──────── 0%
             low warning  reserve    HIBERNATE
                          warning
```

Only 5 points separate the warning (10%) from the hibernate trigger (5%). On a worn battery that stretch can drain in seconds — or the gauge can jump straight past it — so by the time the warning appears, hibernate is already queued, and plugging in no longer saves you.

## The fix

This non-interactive CLI moves the thresholds to give you a real margin:

```
100% ─── 20% ──────── 15% ──────── 10% ──────── 0%
         low warning  reserve      HIBERNATE
                      warning
```

## Requirements

- Windows
- [PowerShell 7.6+](https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-windows) (`pwsh`) — the `#Requires -Version 7.6` guard fails fast on older hosts such as Windows PowerShell 5.1

## Usage

```powershell
pwsh -File .\windows-battery-safety.ps1 standard
pwsh -File .\windows-battery-safety.ps1 safe
pwsh -File .\windows-battery-safety.ps1 custom 25 18 12
```

| Mode | Low (warning) | Reserve (final warning) | Critical (hibernate) |
| --- | --- | --- | --- |
| `standard` | 10% | 7% | 5% |
| `safe` | 20% | 15% | 10% |
| `custom <low> <reserve> <critical>` | your value | your value | your value |

- `standard` restores the Windows defaults.
- `safe` applies the recommended margins: warning ~10 points earlier, and 10 points between warning and hibernate.
- `custom` takes three percentages which must satisfy `low > reserve > critical`, each within `0-100`.

The tool is fully non-interactive: it validates arguments, applies the thresholds to the active power scheme (both on-battery and plugged-in values), verifies the result by re-reading the values, and prints a before/after table.

Exit codes: `0` success, `1` powercfg/verification failure, `2` usage error.

## How it works

A thin wrapper around the documented `powercfg` interface:

- `powercfg /setacvalueindex SCHEME_CURRENT SUB_BATTERY <setting-guid> <value>` (plugged in)
- `powercfg /setdcvalueindex SCHEME_CURRENT SUB_BATTERY <setting-guid> <value>` (on battery)
- `powercfg /setactive SCHEME_CURRENT`, then `powercfg /query` to verify

Setting GUIDs (Microsoft Learn, Battery settings subgroup):

| Threshold | Setting | GUID |
| --- | --- | --- |
| Low | `BATLEVELLOW` | `8183ba9a-e910-48da-8769-14ae6dc1170a` |
| Reserve | `BATLEVELRESERVE`* | `f3c5027d-cd16-4930-aa6b-90db844a8f00` |
| Critical | `BATLEVELCRIT` | `9a66d8d7-4ff7-4ef9-b5a2-5a326ca2a469` |

\* The reserve setting has no powercfg alias registered on some Windows builds, so the tool addresses all three settings by GUID, which always works.

Two documented behaviours worth knowing:

- The critical battery state actually triggers at the *higher* of your configured critical threshold and the battery firmware's ACPI low-capacity alert — so a configured value can never push the trigger below what the firmware considers safe.
- The reserve level is warning-only; there is no "reserve battery action" setting. Only the critical threshold can sleep/hibernate/shut down the machine.

## Reverting

```powershell
pwsh -File .\windows-battery-safety.ps1 standard
```

or nuke every power scheme customisation with `powercfg /restoredefaultschemes`.

## References

- [Battery settings overview — Microsoft Learn](https://learn.microsoft.com/en-us/windows-hardware/customize/power-settings/battery-settings)
- [Low battery threshold — Microsoft Learn](https://learn.microsoft.com/en-us/windows-hardware/customize/power-settings/battery-settings-low-battery-threshold)
- [Reserve battery level — Microsoft Learn](https://learn.microsoft.com/en-us/windows-hardware/customize/power-settings/battery-settings-reserve-battery-level)
- [Critical battery threshold — Microsoft Learn](https://learn.microsoft.com/en-us/windows-hardware/customize/power-settings/battery-settings-critical-battery-threshold)
- [Critical battery action — Microsoft Learn](https://learn.microsoft.com/en-us/windows-hardware/customize/power-settings/battery-settings-critical-battery-action)
- [Powercfg command-line options — Microsoft Learn](https://learn.microsoft.com/en-us/windows-hardware/design/device-experiences/powercfg-command-line-options)

<!-- LICENSE/ -->

## License

Unless stated otherwise all works are:

- Copyright &copy; [Benjamin Lupton](https://balupton.com)

and licensed under:

- [Reciprocal Public License 1.5](http://spdx.org/licenses/RPL-1.5.html)

<!-- /LICENSE -->
