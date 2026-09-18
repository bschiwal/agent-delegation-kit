<#
.SYNOPSIS
  Records which Copilot models you can actually pick, per preset.

.DESCRIPTION
  Entitlement depends on your plan and your org admin's policy, and there is no
  reliable API for it - the VS Code model picker is the ground truth. This script
  takes that list, matches it against registry/models.json, and writes
  registry/availability.json so the build can drop unreachable models from every
  agent.

  To capture the list: in VS Code press Ctrl+Alt+. to open the model picker and
  copy what it shows.

.PARAMETER Preset
  Which profile to record: work or personal.

.PARAMETER Mode
  allow - only the given models are available (the usual case for a managed org)
  deny  - everything EXCEPT the given models
  all   - no restriction; clears the list

.PARAMETER Models
  Model names as shown in the picker. Matching is case-insensitive and tolerates
  minor punctuation differences.

.PARAMETER FromFile
  A text file with one model name per line - easier than quoting a long list.
  Blank lines, and leading bullets or dashes, are ignored.

.PARAMETER List
  Show the current availability and what it means for each role, and change nothing.

.EXAMPLE
  .\scripts\set-availability.ps1 -List
  .\scripts\set-availability.ps1 -Preset work -Mode allow -Models 'Claude Sonnet 5','GPT-5.6 Luna','Gemini 3.7 Flash'
  .\scripts\set-availability.ps1 -Preset work -Mode allow -FromFile .\my-picker-list.txt
  .\scripts\set-availability.ps1 -Preset work -Mode all
#>
[CmdletBinding()]
param(
    [ValidateSet('personal', 'work')] [string]$Preset,
    [ValidateSet('all', 'allow', 'deny')] [string]$Mode,
    [string[]]$Models,
    [string]$FromFile,
    [switch]$List
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$availPath = Join-Path $repo 'registry\availability.json'
$modelsPath = Join-Path $repo 'registry\models.json'
$policyPath = Join-Path $repo 'registry\policy.json'

function Write-Utf8NoBom {
    param([string]$Path, [string]$Text)
    [System.IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding($false)))
}

function Format-JsonString {
    param([string]$Value)
    if ($null -eq $Value) { return 'null' }
    $s = $Value -replace '\\', '\\'
    $s = $s -replace '"', '\"'
    return '"' + $s + '"'
}

function Get-Normalized {
    # Fold case, punctuation and spacing so 'GPT-5.6 Luna', 'gpt 5.6 luna' and
    # 'GPT5.6Luna' all match the same catalogue entry.
    param([string]$Name)
    return (($Name -replace '[^A-Za-z0-9.]', '').ToLower())
}

$catalogue = Get-Content $modelsPath -Raw | ConvertFrom-Json
$avail     = Get-Content $availPath -Raw | ConvertFrom-Json
$policy    = Get-Content $policyPath -Raw | ConvertFrom-Json

# --- list mode ---------------------------------------------------------------

if ($List -or (-not $Preset)) {
    foreach ($p in $avail.profiles.PSObject.Properties) {
        $prof = $p.Value
        Write-Host ''
        Write-Host "[$($p.Name)]" -ForegroundColor Cyan
        Write-Host "  mode:        $($prof.mode)"
        if ($prof.verified_on) { Write-Host "  verified on: $($prof.verified_on)" }
        else { Write-Host '  verified on: never - not yet recorded' -ForegroundColor Yellow }
        if ($prof.mode -ne 'all') {
            Write-Host "  models:      $($prof.models.Count) listed"
            foreach ($m in $prof.models) { Write-Host "    $m" }
        }
        if ($prof.note) { Write-Host "  note: $($prof.note)" -ForegroundColor DarkGray }

        # What each role can actually reach under this profile.
        $allowed = @()
        foreach ($m in $catalogue.models) {
            $ok = $true
            if ($prof.mode -eq 'allow') { $ok = ($prof.models -contains $m.copilot_name) }
            elseif ($prof.mode -eq 'deny') { $ok = -not ($prof.models -contains $m.copilot_name) }
            if ($ok) { $allowed += $m.copilot_name }
        }
        Write-Host "  reachable:   $($allowed.Count) of $($catalogue.models.Count) models"
        Write-Host '  roles:'
        foreach ($r in $policy.roles.PSObject.Properties) {
            $picks = [string[]]$r.Value.copilot
            $reachable = @()
            foreach ($pick in $picks) { if ($allowed -contains $pick) { $reachable += $pick } }
            if ($reachable.Count -eq 0) {
                Write-Host "    $($r.Name): NOTHING REACHABLE - build will substitute" -ForegroundColor Red
            }
            elseif ($reachable[0] -ne $picks[0]) {
                Write-Host "    $($r.Name): $($reachable[0])  (first choice $($picks[0]) is blocked)" -ForegroundColor Yellow
            }
            else {
                Write-Host "    $($r.Name): $($reachable[0])" -ForegroundColor Green
            }
        }
    }
    Write-Host ''
    if (-not $Preset) {
        Write-Host 'To record a profile: set-availability.ps1 -Preset work -Mode allow -Models ... (or -FromFile)' -ForegroundColor Cyan
        Write-Host ''
    }
    return
}

# --- write mode --------------------------------------------------------------

if (-not $Mode) { throw 'Specify -Mode (all, allow or deny), or use -List to inspect.' }

$names = @()
if ($FromFile) {
    if (-not (Test-Path $FromFile)) { throw "File not found: $FromFile" }
    foreach ($line in (Get-Content $FromFile)) {
        $t = $line.Trim() -replace '^[-*•]\s*', ''   # tolerate a pasted bullet list
        if (-not [string]::IsNullOrWhiteSpace($t)) { $names += $t }
    }
}
if ($Models) { $names += $Models }

if ($Mode -eq 'all') {
    $names = @()
}
elseif ($names.Count -eq 0) {
    throw "-Mode $Mode needs model names. Pass -Models or -FromFile."
}

# Match against the catalogue so a typo does not silently blank out a role.
$lookup = @{}
foreach ($m in $catalogue.models) { $lookup[(Get-Normalized $m.copilot_name)] = $m.copilot_name }

$resolved = @()
$unmatched = @()
foreach ($n in $names) {
    $key = Get-Normalized $n
    if ($lookup.ContainsKey($key)) {
        if ($resolved -notcontains $lookup[$key]) { $resolved += $lookup[$key] }
    }
    else { $unmatched += $n }
}

if ($unmatched.Count -gt 0) {
    Write-Host ''
    Write-Host 'Not found in the catalogue:' -ForegroundColor Yellow
    foreach ($u in $unmatched) { Write-Host "  $u" -ForegroundColor Yellow }
    Write-Host '  Either the name is off, or GitHub added it since the last refresh.' -ForegroundColor DarkGray
    Write-Host '  Try: .\scripts\refresh-models.ps1 -Apply' -ForegroundColor DarkGray
    Write-Host ''
}

# Rebuild the document, preserving the other profile untouched.
$out = New-Object System.Text.StringBuilder
[void]$out.AppendLine('{')
[void]$out.AppendLine('  "schema_version": 1,')
[void]$out.AppendLine("  ""_intent"": $(Format-JsonString $avail._intent),")
[void]$out.AppendLine("  ""_how_to_fill"": $(Format-JsonString $avail._how_to_fill),")
[void]$out.AppendLine("  ""_modes"": $(Format-JsonString $avail._modes),")
[void]$out.AppendLine('')
[void]$out.AppendLine('  "profiles": {')

$profLines = @()
foreach ($p in $avail.profiles.PSObject.Properties) {
    $prof = $p.Value
    if ($p.Name -eq $Preset) {
        $profMode = $Mode
        $profModels = $resolved
        $verified = (Get-Date -Format 'yyyy-MM-dd')
        if ($Mode -eq 'all') { $note = 'No restriction recorded - the whole catalogue is assumed reachable.' }
        else { $note = "Recorded from the VS Code model picker. Re-check when your plan or org policy changes." }
    }
    else {
        $profMode = $prof.mode
        $profModels = [string[]]$prof.models
        $verified = $prof.verified_on
        $note = $prof.note
    }

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("    ""$($p.Name)"": {")
    [void]$sb.AppendLine("      ""mode"": $(Format-JsonString $profMode),")
    if ($null -eq $profModels -or $profModels.Count -eq 0) {
        [void]$sb.AppendLine('      "models": [],')
    }
    else {
        [void]$sb.AppendLine('      "models": [')
        $ml = @()
        foreach ($m in $profModels) { $ml += "        $(Format-JsonString $m)" }
        [void]$sb.AppendLine(($ml -join ",`n"))
        [void]$sb.AppendLine('      ],')
    }
    if ($verified) { [void]$sb.AppendLine("      ""verified_on"": $(Format-JsonString $verified),") }
    else { [void]$sb.AppendLine('      "verified_on": null,') }
    [void]$sb.Append("      ""note"": $(Format-JsonString $note)")
    [void]$sb.AppendLine('')
    [void]$sb.Append('    }')
    $profLines += $sb.ToString()
}
[void]$out.AppendLine(($profLines -join ",`n"))
[void]$out.AppendLine('  }')
[void]$out.Append('}')

$json = $out.ToString()
try { $json | ConvertFrom-Json | Out-Null }
catch { throw "Emitted JSON is invalid - availability not written. $($_.Exception.Message)" }
Write-Utf8NoBom $availPath ($json + "`n")

Write-Host ''
Write-Host "Recorded availability for '$Preset': mode $Mode, $($resolved.Count) model(s)." -ForegroundColor Green
Write-Host '  Now run scripts\build.ps1 to re-route the agents around what you cannot reach.' -ForegroundColor Cyan
Write-Host ''
