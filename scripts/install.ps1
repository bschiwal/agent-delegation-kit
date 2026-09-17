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
  Also install the always-on routing rules, so ad-hoc chat follows the cost
  policy and not just the named agents. For Copilot this drops an
  .instructions.md file in place; for Claude Code it prints the one line to add
  to your CLAUDE.md rather than editing that file for you.

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

# --- uninstall ---------------------------------------------------------------

if ($Uninstall) {
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

if ($blocked.Count -gt 0) {
    Write-Host ''
    Write-Host 'Skipped - a file not installed by this kit is already there:' -ForegroundColor Yellow
    foreach ($b in $blocked) { Write-Host "  $b" -ForegroundColor Yellow }
    Write-Host '  Re-run with -Force to overwrite.' -ForegroundColor Yellow
}

Write-Host ''
Write-Host 'Next steps:' -ForegroundColor Cyan
if ($Target -eq 'claude' -or $Target -eq 'both') {
    Write-Host '  Claude Code : restart the CLI (or Claude Desktop), then run /agents to confirm.'
}
if ($Target -eq 'copilot' -or $Target -eq 'both') {
    Write-Host '  VS Code     : reload the window, then open Chat and pick an agent from the dropdown.'
}
if ($WithInstructions -and ($Target -eq 'claude' -or $Target -eq 'both')) {
    # Claude Code's always-on context is CLAUDE.md, which is yours - appending to
    # it automatically risks clobbering your own notes, so this only tells you the
    # one line to add.
    $instrFile = Join-Path $repo 'build\instructions\model-routing.instructions.md'
    Write-Host ''
    Write-Host '  To apply the routing rules to Claude Code chat as well, add this line to'
    Write-Host "  $(Join-Path $userHome '.claude\CLAUDE.md') :"
    Write-Host "      @$instrFile" -ForegroundColor White
    Write-Host '  (the agents already carry their own models - this is only for ad-hoc chat)'
}
Write-Host ''
