<#
.SYNOPSIS
  Compiles registry/agents/*.md into Claude Code and GitHub Copilot agent files.

.DESCRIPTION
  One source file per agent produces two outputs:
    build/claude/agents/<name>.md          - Claude Code sub-agent format
    build/copilot/agents/<name>.agent.md   - VS Code custom agent format

  Models are never written in an agent source. Each agent names a role; roles
  resolve to models through registry/policy.json. Change the policy, rebuild,
  and every agent follows.

.PARAMETER Preset
  'personal' (default) routes purely on measured cost and merit.
  'work' applies registry/policy.json workplace_overrides.profiles.work, which
  reserves Anthropic models for reasoning and review roles.

.EXAMPLE
  .\scripts\build.ps1
  .\scripts\build.ps1 -Preset work
#>
[CmdletBinding()]
param(
    [ValidateSet('personal', 'work')]
    [string]$Preset = 'personal'
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot

# --- load registry -----------------------------------------------------------

$models = Get-Content (Join-Path $repo 'registry\models.json') -Raw | ConvertFrom-Json
$policy = Get-Content (Join-Path $repo 'registry\policy.json') -Raw | ConvertFrom-Json

$overrides = @{}
$profileNode = $policy.workplace_overrides.profiles.$Preset
if ($null -ne $profileNode -and $null -ne $profileNode.role_overrides) {
    foreach ($p in $profileNode.role_overrides.PSObject.Properties) {
        $overrides[$p.Name] = $p.Value
    }
}

# Copilot names that are valid in agent mode, for validation.
$agentCapable = @{}
foreach ($m in $models.models) {
    if ($m.agent_mode -eq $false) { $agentCapable[$m.copilot_name] = $false }
    else { $agentCapable[$m.copilot_name] = $true }
}

# --- helpers -----------------------------------------------------------------

function Write-Utf8NoBom {
    # PowerShell 5.1's -Encoding utf8 emits a BOM, which lands before the opening
    # '---' and can stop a YAML frontmatter parser from recognising the block.
    param([string]$Path, [string]$Text)
    [System.IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding($false)))
}

function Format-YamlScalar {
    param([string]$Value)
    # Single-quoted YAML: the only escape needed is a doubled single quote.
    return "'" + ($Value -replace "'", "''") + "'"
}

$yamlKeywords = @('true', 'false', 'null', 'yes', 'no', 'on', 'off', '~')

function Format-YamlPlain {
    # Emit a bare scalar where YAML allows it, so output matches the style in the
    # Claude Code and VS Code docs. Anything with a colon, quote, leading/trailing
    # space or reserved indicator gets quoted instead.
    param([string]$Value)
    if ($Value -match '^[A-Za-z0-9_][A-Za-z0-9_ ,.\-]*$' -and
        $Value -notmatch '\s$' -and
        $yamlKeywords -notcontains $Value.ToLower()) {
        return $Value
    }
    return (Format-YamlScalar $Value)
}

function Format-YamlList {
    param([string[]]$Items)
    $quoted = @()
    foreach ($i in $Items) { $quoted += (Format-YamlScalar $i) }
    return '[' + ($quoted -join ', ') + ']'
}

function Read-AgentSource {
    param([string]$Path)

    $raw = Get-Content $Path -Raw
    # Source layout: '---', a JSON object, '---', then the markdown body.
    $m = [regex]::Match($raw, '(?s)^\s*---\s*\r?\n(?<json>.*?)\r?\n---\s*\r?\n(?<body>.*)$')
    if (-not $m.Success) {
        throw "$([System.IO.Path]::GetFileName($Path)): expected a '---' fenced JSON block followed by a markdown body."
    }

    $meta = $null
    try { $meta = $m.Groups['json'].Value | ConvertFrom-Json }
    catch { throw "$([System.IO.Path]::GetFileName($Path)): frontmatter is not valid JSON. $($_.Exception.Message)" }

    foreach ($required in 'name', 'role', 'description') {
        if ([string]::IsNullOrWhiteSpace($meta.$required)) {
            throw "$([System.IO.Path]::GetFileName($Path)): missing required field '$required'."
        }
    }

    return [pscustomobject]@{
        Meta = $meta
        Body = $m.Groups['body'].Value.TrimEnd() + "`n"
        File = [System.IO.Path]::GetFileName($Path)
    }
}

function Get-ExtraProperties {
    param($Node, [string[]]$Exclude)
    $out = [ordered]@{}
    if ($null -eq $Node) { return $out }
    foreach ($p in $Node.PSObject.Properties) {
        if ($Exclude -notcontains $p.Name) { $out[$p.Name] = $p.Value }
    }
    return $out
}

function Format-YamlValue {
    param($Value)
    if ($Value -is [bool]) { if ($Value) { return 'true' } else { return 'false' } }
    if ($Value -is [int] -or $Value -is [long] -or $Value -is [double] -or $Value -is [decimal]) { return "$Value" }
    if ($Value -is [array]) { return (Format-YamlList ([string[]]$Value)) }
    return (Format-YamlPlain ([string]$Value))
}

# --- build -------------------------------------------------------------------

$claudeOut  = Join-Path $repo 'build\claude\agents'
$copilotOut = Join-Path $repo 'build\copilot\agents'
foreach ($d in $claudeOut, $copilotOut) {
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    Get-ChildItem $d -Filter '*.md' -ErrorAction SilentlyContinue | Remove-Item -Force
}

$sources = Get-ChildItem (Join-Path $repo 'registry\agents') -Filter '*.md' | Sort-Object Name
if ($sources.Count -eq 0) { throw 'No agent sources found in registry/agents.' }

$summary = @()
$warnings = @()

foreach ($src in $sources) {
    $agent = Read-AgentSource $src.FullName
    $meta  = $agent.Meta
    $role  = $policy.roles.($meta.role)
    if ($null -eq $role) {
        throw "$($agent.File): role '$($meta.role)' is not defined in registry/policy.json."
    }

    # A model hardcoded in an agent source is exactly what goes stale, so it is
    # dropped rather than emitted - but say so instead of doing it silently.
    foreach ($platform in 'claude', 'copilot') {
        if ($null -ne $meta.$platform -and $null -ne $meta.$platform.model) {
            $warnings += "$($agent.File): ignoring '$platform.model' - models come from the role ('$($meta.role)'), not from the agent. Remove it."
        }
    }

    # ---- Claude Code output ----
    $claudeExtra = Get-ExtraProperties $meta.claude @('model')
    $lines = @('---')
    $lines += "name: $($meta.name)"
    $lines += "description: $(Format-YamlScalar $meta.description)"
    $lines += "model: $($role.claude.model)"
    if ($null -ne $role.claude.effort -and -not $claudeExtra.Contains('effort')) {
        $lines += "effort: $($role.claude.effort)"
    }
    foreach ($k in $claudeExtra.Keys) { $lines += "${k}: $(Format-YamlValue $claudeExtra[$k])" }
    $lines += '---'
    $lines += ''
    $claudeText = ($lines -join "`n") + "`n" + $agent.Body
    Write-Utf8NoBom (Join-Path $claudeOut "$($meta.name).md") $claudeText

    # ---- Copilot output ----
    $copilotModels = [string[]]$role.copilot
    if ($overrides.ContainsKey($meta.role)) { $copilotModels = [string[]]$overrides[$meta.role] }

    foreach ($cm in $copilotModels) {
        if (-not $agentCapable.ContainsKey($cm)) {
            $warnings += "$($meta.name): model '$cm' is not in registry/models.json - it may not exist in the picker."
        }
        elseif ($agentCapable[$cm] -eq $false) {
            $warnings += "$($meta.name): model '$cm' is chat-only and cannot drive an agent. Remove it from role '$($meta.role)'."
        }
    }

    $copilotExtra = Get-ExtraProperties $meta.copilot @('model')
    $lines = @('---')
    $lines += "name: $($meta.name)"
    $lines += "description: $(Format-YamlScalar $meta.description)"
    $lines += "model: $(Format-YamlList $copilotModels)"
    foreach ($k in $copilotExtra.Keys) { $lines += "${k}: $(Format-YamlValue $copilotExtra[$k])" }
    $lines += '---'
    $lines += ''
    $copilotText = ($lines -join "`n") + "`n" + $agent.Body
    Write-Utf8NoBom (Join-Path $copilotOut "$($meta.name).agent.md") $copilotText

    $summary += [pscustomobject]@{
        Agent   = $meta.name
        Role    = $meta.role
        Claude  = $role.claude.model
        Copilot = $copilotModels[0]
    }
}

# --- always-on routing instructions ------------------------------------------
# The template carries the prose; the tables are generated so they cannot drift
# from registry/policy.json.

$templatePath = Join-Path $repo 'templates\model-routing.instructions.md'
if (Test-Path $templatePath) {
    $tpl = Get-Content $templatePath -Raw

    # Routing table, one row per role.
    $rows = @('| Kind of work | Model |', '|---|---|')
    foreach ($p in $policy.roles.PSObject.Properties) {
        $picks = [string[]]$p.Value.copilot
        if ($overrides.ContainsKey($p.Name)) { $picks = [string[]]$overrides[$p.Name] }
        $first = $picks[0]
        $rest = ''
        if ($picks.Count -gt 1) { $rest = ' (fall back: ' + (($picks[1..($picks.Count - 1)]) -join ', ') + ')' }
        $rows += "| $($p.Value.intent) | **$first**$rest |"
    }
    $routingTable = $rows -join "`n"

    # Blended cost list, cheapest first, for the models actually routed to.
    $routedNames = @()
    foreach ($p in $policy.roles.PSObject.Properties) { $routedNames += [string[]]$p.Value.copilot }
    foreach ($p in $policy.workplace_overrides.profiles.PSObject.Properties) {
        if ($null -ne $p.Value.role_overrides) {
            foreach ($r in $p.Value.role_overrides.PSObject.Properties) { $routedNames += [string[]]$r.Value }
        }
    }
    $routedNames = $routedNames | Select-Object -Unique
    $costLines = @()
    foreach ($m in ($models.models | Where-Object { $routedNames -contains $_.copilot_name } | Sort-Object blended)) {
        $costLines += "- $($m.copilot_name) - **$('{0:N2}' -f $m.blended)**"
    }
    $costList = $costLines -join "`n"

    $agentList = '`' + (($summary | ForEach-Object { $_.Agent }) -join '` `') + '`'

    $tpl = [regex]::Replace($tpl, '(?s)(<!-- BEGIN:routing-table -->).*?(<!-- END:routing-table -->)', ('$1' + "`n" + $routingTable.Replace('$', '$$') + "`n" + '$2'))
    $tpl = [regex]::Replace($tpl, '(?s)(<!-- BEGIN:cost-list -->).*?(<!-- END:cost-list -->)',       ('$1' + "`n" + $costList.Replace('$', '$$')     + "`n" + '$2'))
    $tpl = [regex]::Replace($tpl, '(?s)(<!-- BEGIN:agent-list -->).*?(<!-- END:agent-list -->)',     ('$1' + "`n" + $agentList.Replace('$', '$$')    + "`n" + '$2'))

    $instrOut = Join-Path $repo 'build\instructions'
    if (-not (Test-Path $instrOut)) { New-Item -ItemType Directory -Path $instrOut -Force | Out-Null }
    Write-Utf8NoBom (Join-Path $instrOut 'model-routing.instructions.md') $tpl
}

# --- generated model reference ----------------------------------------------

$md = @()
$md += '# Model reference (generated)'
$md += ''
$md += "Generated by ``scripts/build.ps1``. Do not edit - change ``registry/models.json`` and rebuild."
$md += ''
$md += "Catalogue verified **$($models.verified_on)**. Prices are USD per 1M tokens under GitHub Copilot usage-based billing."
$md += ''
$md += '`blended = 0.8 * input + 0.2 * output` - agent turns are input-heavy, so this ranks real spend better than headline output price.'
$md += ''
$md += '| Model | Vendor | In | Out | Blended | Tier | Merit | Agent mode |'
$md += '|---|---|---:|---:|---:|---|---:|---|'
foreach ($m in ($models.models | Sort-Object blended)) {
    $am = 'yes'
    if ($m.agent_mode -eq $false) { $am = '**no**' }
    elseif ($null -eq $m.agent_mode) { $am = 'unverified' }
    $md += "| $($m.copilot_name) | $($m.vendor) | `$$('{0:N2}' -f $m.price.in) | `$$('{0:N2}' -f $m.price.out) | **$('{0:N2}' -f $m.blended)** | $($m.tier) | $($m.merit) | $am |"
}
$md += ''
$md += '## Role routing'
$md += ''
$md += "Built with profile **$Preset**."
$md += ''
$md += '| Role | Claude Code | Copilot (first choice) | Posture |'
$md += '|---|---|---|---|'
foreach ($p in $policy.roles.PSObject.Properties) {
    $r = $p.Value
    $first = $r.copilot[0]
    if ($overrides.ContainsKey($p.Name)) { $first = $overrides[$p.Name][0] }
    $md += "| $($p.Name) | $($r.claude.model) | $first | $($r.cost_posture) |"
}
$md += ''
$md += '## Agents'
$md += ''
$md += '| Agent | Role | Claude model | Copilot first choice |'
$md += '|---|---|---|---|'
foreach ($s in $summary) { $md += "| $($s.Agent) | $($s.Role) | $($s.Claude) | $($s.Copilot) |" }
$md += ''

$docsDir = Join-Path $repo 'docs'
if (-not (Test-Path $docsDir)) { New-Item -ItemType Directory -Path $docsDir -Force | Out-Null }
Write-Utf8NoBom (Join-Path $docsDir 'MODELS.md') (($md -join "`n") + "`n")

# --- report ------------------------------------------------------------------

Write-Host ''
Write-Host "Built $($summary.Count) agents (profile: $Preset)" -ForegroundColor Green
$summary | Format-Table -AutoSize
Write-Host "  build/claude/agents/   $($summary.Count) files"
Write-Host "  build/copilot/agents/  $($summary.Count) files"
Write-Host "  docs/MODELS.md         regenerated"

if ($warnings.Count -gt 0) {
    Write-Host ''
    Write-Host 'Warnings:' -ForegroundColor Yellow
    foreach ($w in ($warnings | Select-Object -Unique)) { Write-Host "  - $w" -ForegroundColor Yellow }
}
Write-Host ''
