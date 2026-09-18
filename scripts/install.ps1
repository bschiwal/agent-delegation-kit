<#
.SYNOPSIS
  Installs the built agent profiles into Claude Code and/or GitHub Copilot.

.DESCRIPTION
  Runs build.ps1 first, then copies the generated agents to the right place:

    Claude Code / Claude Desktop
      user     ~/.claude/agents/
      project  <Path>/.claude/agents/

    GitHub Copilot in VS Code
      user     ~/.copilot/agents/
      project  <Path>/.github/agents/

  Every install writes a manifest next to the files it copied, so -Uninstall
  removes exactly what this kit put there and never touches your own agents.

.PARAMETER Target
  claude | copilot | both (default: both)

.PARAMETER Scope
  user (default) installs for every project on this machine.
  project installs into the repo given by -Path, to be committed and shared.

.PARAMETER Path
  Workspace root for -Scope project. Defaults to the current directory.

.PARAMETER Preset
  personal (default) or work. Passed through to build.ps1.

.PARAMETER Force
  Overwrite files that exist but are not in this kit's manifest.

.PARAMETER Uninstall
  Remove previously installed files instead of installing.

.PARAMETER WithInstructions
  Also install the always-on rules. For Copilot: a model-routing
  .instructions.md file. For Claude Code: agent-delegation.md next to CLAUDE.md,
  plus a marked @import block in CLAUDE.md so every new session acts as triage
  lead. Only that block is ever added or removed; the rest of CLAUDE.md is left
  alone.

.EXAMPLE
  .\scripts\install.ps1
  .\scripts\install.ps1 -Target copilot -Preset work -WithInstructions
  .\scripts\install.ps1 -Scope project -Path C:\repos\my-app
  .\scripts\install.ps1 -Uninstall
#>
[CmdletBinding()]
param(
    [ValidateSet('claude', 'copilot', 'both')] [string]$Target = 'both',
    [ValidateSet('user', 'project')]           [string]$Scope  = 'user',
    [string]$Path,
    [ValidateSet('personal', 'work')]          [string]$Preset = 'personal',
    [switch]$Force,
    [switch]$Uninstall,
    [switch]$WithInstructions
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$manifestName = '.agent-delegation-kit.json'

function Write-Utf8NoBom {
    param([string]$Path, [string]$Text)
    [System.IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding($false)))
}

if ($Scope -eq 'project') {
    if ([string]::IsNullOrWhiteSpace($Path)) { $Path = (Get-Location).Path }
    if (-not (Test-Path $Path)) { throw "Workspace path not found: $Path" }
    $Path = (Resolve-Path $Path).Path
}

# --- resolve destinations ----------------------------------------------------

$userHome = $env:USERPROFILE
if ([string]::IsNullOrWhiteSpace($userHome)) { $userHome = $HOME }

$plans = @()
if ($Target -eq 'claude' -or $Target -eq 'both') {
    if ($Scope -eq 'user') { $dest = Join-Path $userHome '.claude\agents' }
    else { $dest = Join-Path $Path '.claude\agents' }
    $plans += [pscustomobject]@{ Name = 'Claude Code'; Source = Join-Path $repo 'build\claude\agents'; Dest = $dest; Filter = '*.md' }
}
if ($Target -eq 'copilot' -or $Target -eq 'both') {
    if ($Scope -eq 'user') { $dest = Join-Path $userHome '.copilot\agents' }
    else { $dest = Join-Path $Path '.github\agents' }
    $plans += [pscustomobject]@{ Name = 'GitHub Copilot'; Source = Join-Path $repo 'build\copilot\agents'; Dest = $dest; Filter = '*.agent.md' }

    if ($WithInstructions -or $Uninstall) {
        # Always-on routing rules, so ad-hoc chat follows the cost policy too and
        # not only the named agents. Included on uninstall so they get cleaned up.
        if ($Scope -eq 'user') { $idest = Join-Path $userHome '.copilot\instructions' }
        else { $idest = Join-Path $Path '.github\instructions' }
        $plans += [pscustomobject]@{ Name = 'Copilot instructions'; Source = Join-Path $repo 'build\instructions'; Dest = $idest; Filter = '*.instructions.md' }
    }
}

# --- Claude Code delegation instructions ---------------------------------------
# The policy file is copied next to CLAUDE.md and pulled in with a single @import
# inside a marked block. CLAUDE.md belongs to the user, so the kit only ever adds
# or removes its own block and never rewrites anything else in the file.

$claudeInstr = $null
if (($Target -eq 'claude' -or $Target -eq 'both') -and ($WithInstructions -or $Uninstall)) {
    if ($Scope -eq 'user') {
        $claudeInstr = [pscustomobject]@{
            PolicyFile = Join-Path $userHome '.claude\agent-delegation.md'
            ClaudeMd   = Join-Path $userHome '.claude\CLAUDE.md'
            Import     = '@~/.claude/agent-delegation.md'
        }
    }
    else {
        $claudeInstr = [pscustomobject]@{
            PolicyFile = Join-Path $Path '.claude\agent-delegation.md'
            ClaudeMd   = Join-Path $Path 'CLAUDE.md'
            Import     = '@.claude/agent-delegation.md'
        }
    }
}
$blockBegin = '<!-- agent-delegation-kit:begin -->'
$blockEnd   = '<!-- agent-delegation-kit:end -->'
$policyMarker = 'Installed by agent-delegation-kit'

function Remove-ClaudeInstructions {
    param($Spec)
    $removed = @()
    if (Test-Path $Spec.ClaudeMd) {
        $text = [System.IO.File]::ReadAllText($Spec.ClaudeMd)
        $pattern = '(\r?\n)?' + [regex]::Escape($blockBegin) + '.*?' + [regex]::Escape($blockEnd) + '(\r?\n)?'
        $new = [regex]::Replace($text, $pattern, "`n", 'Singleline')
        if ($new -ne $text) {
            if ([string]::IsNullOrWhiteSpace($new)) {
                # The file only ever held our block - leave nothing behind.
                Remove-Item $Spec.ClaudeMd -Force
                $removed += "$($Spec.ClaudeMd) (only held the kit's import)"
            }
            else {
                Write-Utf8NoBom $Spec.ClaudeMd ($new.TrimEnd() + "`n")
                $removed += "import block from $($Spec.ClaudeMd)"
            }
        }
    }
    if (Test-Path $Spec.PolicyFile) {
        # Only delete it if it is ours - never a same-named file the user wrote.
        if ([System.IO.File]::ReadAllText($Spec.PolicyFile).Contains($policyMarker)) {
            Remove-Item $Spec.PolicyFile -Force
            $removed += $Spec.PolicyFile
        }
    }
    return $removed
}

# --- uninstall ---------------------------------------------------------------

if ($Uninstall) {
    if ($null -ne $claudeInstr) {
        foreach ($r in (Remove-ClaudeInstructions $claudeInstr)) {
            Write-Host "Claude instructions: removed $r" -ForegroundColor Green
        }
    }
    $removedTotal = 0
    foreach ($p in $plans) {
        $manifestPath = Join-Path $p.Dest $manifestName
        if (-not (Test-Path $manifestPath)) {
            Write-Host "$($p.Name): nothing installed at $($p.Dest)" -ForegroundColor DarkGray
            continue
        }
        $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
        $removed = 0
        foreach ($f in $manifest.files) {
            $fp = Join-Path $p.Dest $f
            if (Test-Path $fp) { Remove-Item $fp -Force; $removed++ }
        }
        Remove-Item $manifestPath -Force
        Write-Host "$($p.Name): removed $removed file(s) from $($p.Dest)" -ForegroundColor Green
        $removedTotal += $removed
    }
    Write-Host ''
    Write-Host "Uninstalled $removedTotal file(s). Restart Claude Code / reload VS Code to pick up the change."
    return
}

# --- build -------------------------------------------------------------------

Write-Host "Building agents (profile: $Preset)..." -ForegroundColor Cyan
& (Join-Path $PSScriptRoot 'build.ps1') -Preset $Preset | Out-Null

# --- install -----------------------------------------------------------------

$blocked = @()

foreach ($p in $plans) {
    if (-not (Test-Path $p.Source)) { throw "Missing build output: $($p.Source). Run scripts/build.ps1." }
    if (-not (Test-Path $p.Dest)) { New-Item -ItemType Directory -Path $p.Dest -Force | Out-Null }

    $manifestPath = Join-Path $p.Dest $manifestName
    $known = @()
    if (Test-Path $manifestPath) {
        $known = (Get-Content $manifestPath -Raw | ConvertFrom-Json).files
    }

    $files = Get-ChildItem $p.Source -Filter $p.Filter
    $written = @()
    foreach ($f in $files) {
        $targetPath = Join-Path $p.Dest $f.Name
        if ((Test-Path $targetPath) -and ($known -notcontains $f.Name) -and (-not $Force)) {
            # A file we did not install already lives here. Do not clobber it.
            $blocked += "$($p.Dest)\$($f.Name)"
            continue
        }
        Copy-Item $f.FullName $targetPath -Force
        $written += $f.Name
    }

    # Retire files from an older version of the kit that no longer exist.
    $stale = @()
    foreach ($k in $known) {
        if ($written -notcontains $k) {
            $kp = Join-Path $p.Dest $k
            if (Test-Path $kp) { Remove-Item $kp -Force; $stale += $k }
        }
    }

    $manifest = [ordered]@{
        kit          = 'agent-delegation-kit'
        installed_on = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        preset       = $Preset
        scope        = $Scope
        source_repo  = $repo
        files        = $written
    }
    Write-Utf8NoBom $manifestPath (($manifest | ConvertTo-Json -Depth 4))

    Write-Host "$($p.Name) -> $($p.Dest)" -ForegroundColor Green
    Write-Host "  $($written.Count) file(s) installed" -NoNewline
    if ($stale.Count -gt 0) { Write-Host ", $($stale.Count) stale removed" } else { Write-Host '' }
}

if ($null -ne $claudeInstr) {
    $src = Join-Path $repo 'templates\claude-delegation.md'
    $ours = $true
    if ((Test-Path $claudeInstr.PolicyFile) -and -not $Force) {
        $ours = [System.IO.File]::ReadAllText($claudeInstr.PolicyFile).Contains($policyMarker)
    }
    if (-not $ours) {
        $blocked += $claudeInstr.PolicyFile
    }
    else {
        $dir = Split-Path $claudeInstr.PolicyFile -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Write-Utf8NoBom $claudeInstr.PolicyFile ([System.IO.File]::ReadAllText($src))

        $block = "$blockBegin`n$($claudeInstr.Import)`n$blockEnd"
        if (-not (Test-Path $claudeInstr.ClaudeMd)) {
            Write-Utf8NoBom $claudeInstr.ClaudeMd ($block + "`n")
            $mdAction = 'created'
        }
        else {
            $existing = [System.IO.File]::ReadAllText($claudeInstr.ClaudeMd)
            if ($existing.Contains($blockBegin)) {
                $mdAction = 'already imports it'
            }
            else {
                Write-Utf8NoBom $claudeInstr.ClaudeMd ($existing.TrimEnd() + "`n`n" + $block + "`n")
                $mdAction = 'import appended'
            }
        }
        Write-Host "Claude instructions -> $($claudeInstr.PolicyFile)" -ForegroundColor Green
        Write-Host "  $($claudeInstr.ClaudeMd): $mdAction"
    }
}

if ($blocked.Count -gt 0) {
    Write-Host ''
    Write-Host 'Skipped - a file not installed by this kit is already there:' -ForegroundColor Yellow
    foreach ($b in $blocked) { Write-Host "  $b" -ForegroundColor Yellow }
    Write-Host '  Re-run with -Force to overwrite.' -ForegroundColor Yellow
}

Write-Host ''
Write-Host 'Next steps:' -ForegroundColor Cyan
if ($Target -eq 'claude' -or $Target -eq 'both') {
    Write-Host '  Claude Code : start a new session (VS Code: Reload Window), then ask'
    Write-Host '                "which subagents do you have?" to confirm.'
}
if ($Target -eq 'copilot' -or $Target -eq 'both') {
    Write-Host '  VS Code     : reload the window, then open Chat and pick an agent from the dropdown.'
}
if ($null -ne $claudeInstr) {
    Write-Host '                New sessions now act as triage lead by default: they delegate'
    Write-Host '                to the specialists and keep Opus, MCP, skills and memory.'
}
Write-Host ''
