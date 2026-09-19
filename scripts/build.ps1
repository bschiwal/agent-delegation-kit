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

# Availability: what this preset can actually pick. Org policy and plan tier
# remove models, and a role whose whole fallback chain is blocked would otherwise
# emit a model list that never resolves.
$availPath = Join-Path $repo 'registry\availability.json'
$availMode = 'all'
$availList = @()
$availVerified = $null
if (Test-Path $availPath) {
    $avail = Get-Content $availPath -Raw | ConvertFrom-Json
    $availProfile = $avail.profiles.$Preset
    if ($null -ne $availProfile) {
        $availMode = $availProfile.mode
        $availList = [string[]]$availProfile.models
        $availVerified = $availProfile.verified_on
    }
}

function Test-Available {
    param([string]$Name)
    if ($availMode -eq 'allow') { return ($availList -contains $Name) }
    if ($availMode -eq 'deny')  { return (-not ($availList -contains $Name)) }
    return $true
}

# Models reachable under this preset, richest metadata first for substitution.
$reachable = @()
foreach ($m in $models.models) {
    if ((Test-Available $m.copilot_name) -and ($m.agent_mode -ne $false)) { $reachable += $m }
}
if ($reachable.Count -eq 0) {
    throw "No agent-capable models are available under preset '$Preset'. Check registry/availability.json."
}

function Get-Substitute {
    # A role's entire preferred chain is blocked. Pick the best reachable stand-in
    # from the role's cost posture rather than emitting a list that resolves to
    # nothing and lets the host choose silently.
    param([string]$Posture)
    if ($Posture -eq 'quality-first') {
        return ($reachable | Sort-Object -Property @{E={$_.merit}; Descending=$true}, @{E={$_.blended}} | Select-Object -First 1)
    }
    if ($Posture -eq 'cheapest-viable') {
        $viable = $reachable | Where-Object { $_.merit -ge 2.5 }
        if ($viable.Count -eq 0) { $viable = $reachable }
        return ($viable | Sort-Object -Property @{E={$_.blended}} | Select-Object -First 1)
    }
    # balanced: best merit per dollar, tie-broken by price
    return ($reachable |
        Sort-Object -Property @{E={ if ($_.blended -gt 0) { $_.merit / $_.blended } else { 0 } }; Descending=$true}, @{E={$_.blended}} |
        Select-Object -First 1)
}

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
$substitutions = @()
$degraded = @()

# Pre-pass: an orchestrating agent's allow-list is every other delegable agent,
# so all names must be known before any agent is emitted. Generating the list
# means a newly added agent joins the orchestrator's team without anyone
# remembering to edit it.
$parsed = @()
foreach ($src in $sources) { $parsed += (Read-AgentSource $src.FullName) }
$delegableNames = @($parsed | Where-Object { $_.Meta.delegable -ne $false } | ForEach-Object { $_.Meta.name } | Sort-Object)
$allNames = @($parsed | ForEach-Object { $_.Meta.name })

function Get-BudgetFooter {
    # Appended to every agent. A run's cost is turns x context, and a run cut off at
    # maxTurns loses its unreported work and gets paid for again on the re-run -
    # 9 of 22 runs in the 2026-09-18 audit ended exactly that way. So every agent
    # is told its budget and to hand back partial results before the hard stop.
    param($MaxTurns)
    $lines = @('', '## Turn budget', '')
    if ($null -ne $MaxTurns) {
        $wrap = [math]::Max(1, [math]::Floor([int]$MaxTurns * 0.75))
        $lines += "You have at most **$MaxTurns turns**, and every turn re-reads your whole"
        $lines += 'context - turns are the main cost of this run. By about **turn ' + $wrap + '**, stop'
        $lines += 'starting new work: finish or back out the step in progress, then hand back'
    }
    else {
        $lines += 'Every turn re-reads your whole context, so turns are the main cost of this'
        $lines += 'run. Well before you run out, stop starting new work: finish or back out'
        $lines += 'the step in progress, then hand back'
    }
    $lines += 'what is done, what is left, and exactly where to resume. A run cut off at the'
    $lines += 'limit loses everything it had not yet reported and has to be paid for again.'
    $lines += ''
    $lines += 'Spend turns carefully:'
    $lines += ''
    $lines += '- Do several independent things per turn - read three files at once, make'
    $lines += '  related edits together.'
    $lines += '- For many similar files or edits, write and run one script instead of one'
    $lines += '  edit per turn.'
    $lines += '- Read line ranges and grep with context, not whole files you only need a'
    $lines += '  slice of.'
    $lines += '- If the task is plainly too big for your budget, say so at the start and'
    $lines += '  propose a split instead of starting a run you cannot finish.'
    $lines += '- If you delegate, launch subagents in the foreground (run_in_background:'
    $lines += '  false) and wait for them - do not end your turn while children still run.'
    return ($lines -join "`n") + "`n"
}

# --- shared templates ----------------------------------------------------------
# The routing rules live once, in templates/partials/, and are pulled into every
# consumer at build time: <!-- INCLUDE:name --> inserts a partial, and
# <!-- GENERATE:roster --> inserts the agent table built from each agent's "when".
# Before this, the main-session policy and triage-lead each carried a hand-written
# copy, and the copies had already drifted.

$claudeOnlyNames = @($parsed | Where-Object { $_.Meta.copilot -is [bool] -and $_.Meta.copilot -eq $false } | ForEach-Object { $_.Meta.name })

$tierLabel = @{ haiku = 'cheap'; sonnet = 'standard'; opus = 'premium'; fable = 'frontier' }
$tierOrder = @{ cheap = 0; standard = 1; premium = 2; frontier = 3 }

foreach ($a in $parsed) {
    if ($a.Meta.delegable -ne $false -and [string]::IsNullOrWhiteSpace($a.Meta.when)) {
        throw "$($a.File): delegable agents need a short ""when"" field - it becomes the agent's row in the generated roster."
    }
}

function Get-RosterTable {
    $rows = @()
    foreach ($a in $parsed) {
        if ($a.Meta.delegable -eq $false) { continue }
        $model = $policy.roles.($a.Meta.role).claude.model
        $tier = $tierLabel[$model]
        if ($null -eq $tier) { $tier = $model }
        $when = $a.Meta.when
        if ($claudeOnlyNames -contains $a.Meta.name) { $when += ' *(Claude Code only)*' }
        $rows += [pscustomobject]@{ When = $when; Name = $a.Meta.name; Tier = $tier; Order = $tierOrder[$tier] }
    }
    $lines = @('| Need | Agent | Tier |', '|---|---|---|')
    foreach ($r in ($rows | Sort-Object Order, Name)) {
        $lines += "| $($r.When) | ``$($r.Name)`` | $($r.Tier) |"
    }
    return ($lines -join "`n")
}

function Expand-Template {
    param([string]$Text)
    $partialDir = Join-Path $repo 'templates\partials'
    $out = [regex]::Replace($Text, '<!--\s*INCLUDE:([\w\-]+)\s*-->', {
        param($m)
        $p = Join-Path $partialDir ($m.Groups[1].Value + '.md')
        if (-not (Test-Path $p)) { throw "Template include not found: $p" }
        return ([System.IO.File]::ReadAllText($p).Trim())
    })
    $roster = Get-RosterTable
    $out = [regex]::Replace($out, '<!--\s*GENERATE:roster\s*-->', { param($m) $roster })
    if ($out -match '<!--\s*(INCLUDE|GENERATE):') { throw "Unexpanded template marker left in output: $($Matches[0])" }
    return $out
}

function Get-DelegateList {
    # "delegates": "*" means every delegable agent except itself; an array names
    # them explicitly and is validated so a typo cannot silently shrink the team.
    param($Meta, [string]$File)
    if ($null -eq $Meta.delegates) { return $null }
    if ($Meta.delegates -is [string] -and $Meta.delegates -eq '*') {
        return @($delegableNames | Where-Object { $_ -ne $Meta.name })
    }
    $named = [string[]]$Meta.delegates
    foreach ($n in $named) {
        if ($allNames -notcontains $n) { throw "${File}: delegates names unknown agent '$n'." }
    }
    return @($named | Where-Object { $_ -ne $Meta.name })
}

foreach ($agent in $parsed) {
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

    $delegates = Get-DelegateList $meta $agent.File

    # ---- Claude Code output ----
    $claudeExtra = Get-ExtraProperties $meta.claude @('model')
    if ($null -ne $delegates -and $delegates.Count -gt 0) {
        # Agent(a, b, c) is an allow-list: the orchestrator can spawn only these.
        $agentTool = 'Agent(' + ($delegates -join ', ') + ')'
        if ($claudeExtra.Contains('tools') -and -not [string]::IsNullOrWhiteSpace($claudeExtra['tools'])) {
            $claudeExtra['tools'] = $agentTool + ', ' + $claudeExtra['tools']
        }
        else { $claudeExtra['tools'] = $agentTool }
    }
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
    $claudeText = ($lines -join "`n") + "`n" + (Expand-Template $agent.Body) + (Get-BudgetFooter $meta.claude.maxTurns)
    Write-Utf8NoBom (Join-Path $claudeOut "$($meta.name).md") $claudeText

    # "copilot": false marks a Claude-Code-only agent - typically one whose job
    # needs MCP tools that Copilot custom agents cannot reference the same way.
    # Emitting it for Copilot would give Copilot an agent that cannot do its job.
    if ($meta.copilot -is [bool] -and $meta.copilot -eq $false) {
        $summary += [pscustomobject]@{
            Agent   = $meta.name
            Role    = $meta.role
            Claude  = $role.claude.model
            Copilot = '(Claude only)'
        }
        continue
    }

    # ---- Copilot output ----
    $preferred = [string[]]$role.copilot
    if ($overrides.ContainsKey($meta.role)) { $preferred = [string[]]$overrides[$meta.role] }

    foreach ($cm in $preferred) {
        if (-not $agentCapable.ContainsKey($cm)) {
            $warnings += "$($meta.name): model '$cm' is not in registry/models.json - it may not exist in the picker."
        }
        elseif ($agentCapable[$cm] -eq $false) {
            $warnings += "$($meta.name): model '$cm' is chat-only and cannot drive an agent. Remove it from role '$($meta.role)'."
        }
    }

    # Drop models this preset cannot reach - a blocked model in the list is dead
    # weight at best, and at worst hides that the role never gets its first choice.
    $copilotModels = @()
    $dropped = @()
    foreach ($cm in $preferred) {
        if (Test-Available $cm) { $copilotModels += $cm } else { $dropped += $cm }
    }

    if ($copilotModels.Count -eq 0) {
        $sub = Get-Substitute $role.cost_posture
        $copilotModels = @($sub.copilot_name)
        $substitutions += [pscustomobject]@{
            Agent    = $meta.name
            Role     = $meta.role
            Posture  = $role.cost_posture
            Blocked  = ($preferred -join ', ')
            Chosen   = $sub.copilot_name
            Merit    = $sub.merit
        }
    }
    elseif ($dropped.Count -gt 0) {
        $degraded += [pscustomobject]@{
            Agent   = $meta.name
            Role    = $meta.role
            Dropped = ($dropped -join ', ')
            NowUses = $copilotModels[0]
            WasFirstChoice = ($dropped -contains $preferred[0])
        }
    }

    $copilotExtra = Get-ExtraProperties $meta.copilot @('model')
    if ($null -ne $delegates -and $delegates.Count -gt 0) {
        # VS Code needs both: the 'agent' tool set to delegate at all, and the
        # 'agents' list to say which custom agents it may call. Claude-only agents
        # do not exist on the Copilot side, so they are left out of its list.
        $copilotExtra['agents'] = [string[]]@($delegates | Where-Object { $claudeOnlyNames -notcontains $_ })
        $ctools = @()
        if ($copilotExtra.Contains('tools')) { $ctools = [string[]]$copilotExtra['tools'] }
        if ($ctools -notcontains 'agent') { $ctools += 'agent' }
        $copilotExtra['tools'] = [string[]]$ctools
    }
    $lines = @('---')
    $lines += "name: $($meta.name)"
    $lines += "description: $(Format-YamlScalar $meta.description)"
    $lines += "model: $(Format-YamlList $copilotModels)"
    foreach ($k in $copilotExtra.Keys) { $lines += "${k}: $(Format-YamlValue $copilotExtra[$k])" }
    $lines += '---'
    $lines += ''
    $copilotText = ($lines -join "`n") + "`n" + (Expand-Template $agent.Body) + (Get-BudgetFooter $null)
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

# Main-session delegation policy for Claude Code. install.ps1 -WithInstructions
# copies this next to the user's CLAUDE.md. It shares its routing rules with
# triage-lead through templates/partials/delegation-core.md.
$delegationTpl = Join-Path $repo 'templates\claude-delegation.md'
if (Test-Path $delegationTpl) {
    $instrOut = Join-Path $repo 'build\instructions'
    if (-not (Test-Path $instrOut)) { New-Item -ItemType Directory -Path $instrOut -Force | Out-Null }
    $delegation = Expand-Template ([System.IO.File]::ReadAllText($delegationTpl))
    Write-Utf8NoBom (Join-Path $instrOut 'claude-delegation.md') ($delegation.TrimEnd() + "`n")
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
if ($availMode -eq 'all') {
    $md += "Availability for preset **$Preset** is unrestricted, so the whole catalogue is assumed reachable."
}
else {
    $md += "Availability for preset **$Preset**: mode ``$availMode``, **$($reachable.Count) of $($models.models.Count)** models reachable"
    if ($availVerified) { $md += " (recorded $availVerified)." } else { $md += '.' }
    $md += ''
    $md += 'A model marked *blocked* is in GitHub''s catalogue but not available to this profile, so the build strips it from every agent. Update with `scripts/set-availability.ps1`.'
}
$md += ''

$md += '| Model | Vendor | In | Out | Blended | Tier | Merit | Agent mode | Reachable |'
$md += '|---|---|---:|---:|---:|---|---:|---|---|'
foreach ($m in ($models.models | Sort-Object blended)) {
    $am = 'yes'
    if ($m.agent_mode -eq $false) { $am = '**no**' }
    elseif ($null -eq $m.agent_mode) { $am = 'unverified' }
    if (Test-Available $m.copilot_name) { $reach = 'yes' } else { $reach = '**blocked**' }
    $merit = $m.merit
    if ($null -eq $merit) { $merit = '_unscored_' }
    $md += "| $($m.copilot_name) | $($m.vendor) | `$$('{0:N2}' -f $m.price.in) | `$$('{0:N2}' -f $m.price.out) | **$('{0:N2}' -f $m.blended)** | $($m.tier) | $merit | $am | $reach |"
}

$unscored = @($models.models | Where-Object { $null -eq $_.merit })
if ($unscored.Count -gt 0) {
    $md += ''
    $md += "**$($unscored.Count) model(s) are unscored.** Automatic substitution never picks an unscored model, so they stay unused until you set ``merit`` in ``registry/models.json`` or name one explicitly in a role: " + (($unscored | ForEach-Object { $_.copilot_name }) -join ', ') + '.'
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

if ($availMode -ne 'all') {
    Write-Host ''
    Write-Host "Availability: mode '$availMode', $($reachable.Count) of $($models.models.Count) models reachable" -ForegroundColor Cyan
    if ($availVerified) { Write-Host "  recorded $availVerified" -ForegroundColor DarkGray }
}
elseif ($null -eq $availVerified) {
    Write-Host ''
    Write-Host "Availability for '$Preset' has never been recorded - assuming the whole catalogue." -ForegroundColor DarkGray
    Write-Host '  If your org blocks models, run: .\scripts\set-availability.ps1 -List' -ForegroundColor DarkGray
}

if ($substitutions.Count -gt 0) {
    Write-Host ''
    Write-Host 'SUBSTITUTED - every preferred model for these roles is blocked:' -ForegroundColor Red
    foreach ($s in ($substitutions | Sort-Object Role -Unique)) {
        Write-Host "  role '$($s.Role)' ($($s.Posture))" -ForegroundColor Red
        Write-Host "    wanted: $($s.Blocked)" -ForegroundColor DarkGray
        Write-Host "    using:  $($s.Chosen) (merit $($s.Merit))" -ForegroundColor Yellow
    }
    Write-Host '  Fix properly by adding a reachable model to that role in registry/policy.json.' -ForegroundColor DarkGray
}

if ($degraded.Count -gt 0) {
    $lostFirst = $degraded | Where-Object { $_.WasFirstChoice }
    if ($lostFirst.Count -gt 0) {
        Write-Host ''
        Write-Host 'First choice blocked - these roles fall back:' -ForegroundColor Yellow
        foreach ($d in ($lostFirst | Sort-Object Role -Unique)) {
            Write-Host "  role '$($d.Role)': blocked $($d.Dropped) -> now uses $($d.NowUses)" -ForegroundColor Yellow
        }
    }
}

if ($warnings.Count -gt 0) {
    Write-Host ''
    Write-Host 'Warnings:' -ForegroundColor Yellow
    foreach ($w in ($warnings | Select-Object -Unique)) { Write-Host "  - $w" -ForegroundColor Yellow }
}
Write-Host ''
