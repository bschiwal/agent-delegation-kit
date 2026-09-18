<#
.SYNOPSIS
  Refreshes registry/models.json from the live GitHub Copilot docs.

.DESCRIPTION
  GitHub serves the raw Markdown for its docs pages by appending .md to the URL,
  so the pricing tables can be parsed directly instead of scraping rendered HTML.

  Sources:
    .../copilot-billing/models-and-pricing.md   - the catalogue and per-token prices

  Run without -Apply to see a report of what changed. Run with -Apply to write
  registry/models.json.

  What -Apply overwrites: prices, blended cost, vendor, category, release status.
  What -Apply never touches: merit, agent_mode, and notes. Those are editorial
  judgements you maintain - a refresh must not silently overwrite your opinion
  of a model with a number scraped off a web page. New models arrive with
  merit null and agent_mode null so they show up as needing your review.

.PARAMETER Apply
  Write the changes to registry/models.json. Without it, this reports only.

.PARAMETER OfflineFile
  Parse a previously saved copy of models-and-pricing.md instead of fetching.

.EXAMPLE
  .\scripts\refresh-models.ps1
  .\scripts\refresh-models.ps1 -Apply
#>
[CmdletBinding()]
param(
    [switch]$Apply,
    [string]$OfflineFile
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$modelsPath = Join-Path $repo 'registry\models.json'

$pricingUrl   = 'https://docs.github.com/en/copilot/reference/copilot-billing/models-and-pricing.md'

# Input-heavy agent turns: see registry/models.json _blended_formula.
$W_IN  = 0.8
$W_OUT = 0.2

function Write-Utf8NoBom {
    param([string]$Path, [string]$Text)
    [System.IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding($false)))
}

function Get-DocMarkdown {
    param([string]$Url)
    try {
        return (Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 40).Content
    }
    catch {
        throw "Could not fetch $Url - $($_.Exception.Message)"
    }
}

function ConvertTo-Money {
    # '$1.75' -> 1.75 ; 'Not applicable' / '' -> $null
    param([string]$Cell)
    $c = $Cell.Trim()
    if ($c -notmatch '^\$') { return $null }
    return [double]($c -replace '[\$,]', '')
}

function Split-MarkdownRow {
    param([string]$Line)
    $cells = @()
    foreach ($c in ($Line.Trim().Trim('|') -split '\|')) { $cells += $c.Trim() }
    return $cells
}

function Get-Cell {
    param($Cells, $Header, [string]$Column)
    if (-not $Header.ContainsKey($Column)) { return $null }
    $idx = $Header[$Column]
    if ($idx -ge $Cells.Count) { return $null }
    return $Cells[$idx]
}

function Get-PricingRows {
    param([string]$Markdown)

    # Each vendor publishes its own table and the columns differ between them -
    # only OpenAI carries 'Cache write', only some carry 'Tier'. So map columns by
    # header name per table rather than assuming a fixed order.
    $rows = @()
    $vendor = $null
    $header = $null

    foreach ($line in ($Markdown -split "`r?`n")) {

        $h = [regex]::Match($line, '^###\s+(?<v>.+?)\s*$')
        if ($h.Success) {
            $vendor = $h.Groups['v'].Value.Trim()
            $header = $null
            continue
        }

        if ($line -notmatch '^\s*\|') { continue }
        if ($line -match '^\s*\|[\s\-:|]+\|\s*$') { continue }   # separator row

        $cells = Split-MarkdownRow $line

        # A row whose first cell is 'Model' is this table's header.
        if ($cells[0] -eq 'Model' -or $cells[0] -eq 'Model name') {
            $header = @{}
            for ($i = 0; $i -lt $cells.Count; $i++) { $header[$cells[$i]] = $i }
            continue
        }

        if ($null -eq $header) { continue }
        if ([string]::IsNullOrWhiteSpace($cells[0])) { continue }

        # Where a table has a Tier column, take the Default row only; 'Long context'
        # is the same model priced above a token threshold, not a separate choice.
        $tier = Get-Cell $cells $header 'Tier'
        if ($null -ne $tier -and $tier -ne '' -and $tier -ne 'Default') { continue }

        $in  = ConvertTo-Money (Get-Cell $cells $header 'Input')
        $out = ConvertTo-Money (Get-Cell $cells $header 'Output')
        if ($null -eq $in -or $null -eq $out) { continue }

        # Strip footnote markers and the docs' trailing '(preview)' annotation -
        # neither is part of the name shown in the model picker. Release status
        # already carries the preview flag in its own column.
        $name = ((Get-Cell $cells $header 'Model') -replace '\[\^[^\]]+\]', '').Trim()
        $name = ($name -replace '\s*\((preview|beta|deprecated)\)\s*$', '').Trim()
        if ([string]::IsNullOrWhiteSpace($name)) { continue }

        $rows += [pscustomobject]@{
            Name       = $name
            Vendor     = $vendor
            Release    = (Get-Cell $cells $header 'Release status')
            Category   = (Get-Cell $cells $header 'Category')
            In         = $in
            CachedIn   = ConvertTo-Money (Get-Cell $cells $header 'Cached input')
            CacheWrite = ConvertTo-Money (Get-Cell $cells $header 'Cache write')
            Out        = $out
            Blended    = [math]::Round(($W_IN * $in) + ($W_OUT * $out), 2)
        }
    }
    return $rows
}

function Format-JsonString {
    param([string]$Value)
    if ($null -eq $Value) { return 'null' }
    $s = $Value -replace '\\', '\\'
    $s = $s -replace '"', '\"'
    $s = $s -replace "`r", '\r'
    $s = $s -replace "`n", '\n'
    $s = $s -replace "`t", '\t'
    return '"' + $s + '"'
}

function Format-JsonNumber {
    param($Value)
    if ($null -eq $Value) { return 'null' }
    return ('{0}' -f ([double]$Value))
}

function Format-ModelsJson {
    # Hand-rolled emitter: ConvertTo-Json in PowerShell 5.1 produces colon-aligned
    # output that is painful to hand-edit, and this file exists to be hand-edited
    # (merit and notes are editorial). One line per model keeps it diff-friendly.
    param($Doc)

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('{')
    [void]$sb.AppendLine("  ""schema_version"": $($Doc.schema_version),")
    [void]$sb.AppendLine("  ""verified_on"": $(Format-JsonString $Doc.verified_on),")

    [void]$sb.AppendLine('  "sources": [')
    $srcLines = @()
    foreach ($s in $Doc.sources) { $srcLines += "    $(Format-JsonString $s)" }
    [void]$sb.AppendLine(($srcLines -join ",`n"))
    [void]$sb.AppendLine('  ],')

    foreach ($k in '_pricing_note', '_blended_formula', '_merit_note', '_agent_mode_note') {
        [void]$sb.AppendLine("  ""$k"": $(Format-JsonString $Doc.$k),")
    }

    [void]$sb.AppendLine('  "models": [')
    $modelLines = @()
    foreach ($m in $Doc.models) {
        $p = $m.price
        $parts = @()
        $parts += """id"": $(Format-JsonString $m.id)"
        $parts += """copilot_name"": $(Format-JsonString $m.copilot_name)"
        $parts += """vendor"": $(Format-JsonString $m.vendor)"
        $parts += """category"": $(Format-JsonString $m.category)"
        $parts += """release"": $(Format-JsonString $m.release)"
        $parts += """price"": { ""in"": $(Format-JsonNumber $p.in), ""cached_in"": $(Format-JsonNumber $p.cached_in), ""out"": $(Format-JsonNumber $p.out), ""cache_write"": $(Format-JsonNumber $p.cache_write) }"
        $parts += """blended"": $(Format-JsonNumber $m.blended)"
        $parts += """tier"": $(Format-JsonString $m.tier)"
        $parts += """merit"": $(Format-JsonNumber $m.merit)"
        if ($null -eq $m.agent_mode) { $am = 'null' } elseif ($m.agent_mode) { $am = 'true' } else { $am = 'false' }
        $parts += """agent_mode"": $am"
        $parts += """notes"": $(Format-JsonString $m.notes)"
        $modelLines += '    { ' + ($parts -join ', ') + ' }'
    }
    [void]$sb.AppendLine(($modelLines -join ",`n"))
    [void]$sb.AppendLine('  ],')

    [void]$sb.AppendLine('  "claude_code_models": [')
    $ccLines = @()
    foreach ($c in $Doc.claude_code_models) {
        $ccLines += "    { ""alias"": $(Format-JsonString $c.alias), ""model_id"": $(Format-JsonString $c.model_id), ""tier"": $(Format-JsonString $c.tier), ""merit"": $(Format-JsonNumber $c.merit) }"
    }
    [void]$sb.AppendLine(($ccLines -join ",`n"))
    [void]$sb.AppendLine('  ]')
    [void]$sb.Append('}')
    return $sb.ToString()
}

function Get-TierFromBlended {
    param([double]$Blended)
    if ($Blended -lt 1.00)  { return 'economy' }
    if ($Blended -lt 4.00)  { return 'standard' }
    if ($Blended -lt 12.00) { return 'premium' }
    return 'frontier'
}

# --- fetch and parse ---------------------------------------------------------

if ($OfflineFile) {
    if (-not (Test-Path $OfflineFile)) { throw "Offline file not found: $OfflineFile" }
    Write-Host "Parsing $OfflineFile" -ForegroundColor Cyan
    $pricingMd = Get-Content $OfflineFile -Raw
}
else {
    Write-Host 'Fetching GitHub Copilot pricing docs...' -ForegroundColor Cyan
    $pricingMd = Get-DocMarkdown $pricingUrl
}

$live = Get-PricingRows $pricingMd
if ($live.Count -eq 0) {
    throw 'Parsed zero models. The docs table layout has probably changed - check Get-PricingRows.'
}
Write-Host "  parsed $($live.Count) models (Default tier) across $((($live | Select-Object -ExpandProperty Vendor -Unique)).Count) vendors"

# --- diff against the registry ----------------------------------------------

$current = Get-Content $modelsPath -Raw | ConvertFrom-Json
$byName = @{}
foreach ($m in $current.models) { $byName[$m.copilot_name] = $m }

$added = @(); $changed = @(); $gone = @(); $unchanged = 0

foreach ($l in $live) {
    if (-not $byName.ContainsKey($l.Name)) {
        $added += $l
        continue
    }
    $e = $byName[$l.Name]
    $deltas = @()
    if ([double]$e.price.in  -ne $l.In)  { $deltas += "input `$$($e.price.in) -> `$$($l.In)" }
    if ([double]$e.price.out -ne $l.Out) { $deltas += "output `$$($e.price.out) -> `$$($l.Out)" }
    if ($deltas.Count -gt 0) { $changed += [pscustomobject]@{ Name = $l.Name; Deltas = $deltas; Row = $l } }
    else { $unchanged++ }
}

$liveNames = @()
foreach ($l in $live) { $liveNames += $l.Name }
foreach ($m in $current.models) {
    if ($liveNames -notcontains $m.copilot_name) { $gone += $m.copilot_name }
}

# --- report ------------------------------------------------------------------

Write-Host ''
Write-Host "Registry last verified: $($current.verified_on)" -ForegroundColor DarkGray
Write-Host ''

if ($added.Count -gt 0) {
    Write-Host "NEW - $($added.Count) model(s) not in the registry:" -ForegroundColor Green
    foreach ($a in ($added | Sort-Object Blended)) {
        Write-Host ("  {0,-30} {1,-12} in `${2,-6} out `${3,-7} blended {4,-6} -> tier {5}" -f `
            $a.Name, $a.Vendor, $a.In, $a.Out, $a.Blended, (Get-TierFromBlended $a.Blended))
    }
    Write-Host '  These need a merit score and an agent_mode check before you route to them.' -ForegroundColor DarkGray
    Write-Host ''
}

if ($changed.Count -gt 0) {
    Write-Host "PRICE CHANGED - $($changed.Count) model(s):" -ForegroundColor Yellow
    foreach ($c in $changed) { Write-Host "  $($c.Name): $($c.Deltas -join ', ')" }
    Write-Host ''
}

if ($gone.Count -gt 0) {
    Write-Host "NOT IN THE PRICING TABLE - $($gone.Count) model(s) in the registry:" -ForegroundColor Magenta
    foreach ($g in $gone) { Write-Host "  $g" }
    Write-Host '  Either retired, or renamed. Check before removing - a role may still route to it.' -ForegroundColor DarkGray
    Write-Host ''
}

if ($added.Count -eq 0 -and $changed.Count -eq 0 -and $gone.Count -eq 0) {
    Write-Host "Registry is current - all $unchanged models match the docs." -ForegroundColor Green
}

# Any model a role routes to that the docs no longer list is a live breakage.
$policy = Get-Content (Join-Path $repo 'registry\policy.json') -Raw | ConvertFrom-Json
$routed = @()
foreach ($p in $policy.roles.PSObject.Properties) { $routed += [string[]]$p.Value.copilot }
foreach ($p in $policy.workplace_overrides.profiles.PSObject.Properties) {
    if ($null -ne $p.Value.role_overrides) {
        foreach ($r in $p.Value.role_overrides.PSObject.Properties) { $routed += [string[]]$r.Value }
    }
}
$brokenRoutes = @()
foreach ($r in ($routed | Select-Object -Unique)) {
    if ($liveNames -notcontains $r) { $brokenRoutes += $r }
}
if ($brokenRoutes.Count -gt 0) {
    Write-Host 'WARNING - policy.json routes to models the docs no longer list:' -ForegroundColor Red
    foreach ($b in $brokenRoutes) { Write-Host "  $b" -ForegroundColor Red }
    Write-Host ''
}

if (-not $Apply) {
    Write-Host 'Report only. Re-run with -Apply to write registry/models.json.' -ForegroundColor Cyan
    Write-Host ''
    return
}

# --- apply -------------------------------------------------------------------

$merged = @()
foreach ($l in ($live | Sort-Object Blended)) {
    if ($byName.ContainsKey($l.Name)) {
        $e = $byName[$l.Name]
        $merged += [ordered]@{
            id           = $e.id
            copilot_name = $l.Name
            vendor       = $l.Vendor
            category     = $l.Category
            release      = $l.Release
            price        = [ordered]@{ in = $l.In; cached_in = $l.CachedIn; out = $l.Out; cache_write = $l.CacheWrite }
            blended      = $l.Blended
            tier         = $e.tier          # editorial - keep
            merit        = $e.merit         # editorial - keep
            agent_mode   = $e.agent_mode    # editorial - keep
            notes        = $e.notes         # editorial - keep
        }
    }
    else {
        $slug = ($l.Name.ToLower() -replace '[^a-z0-9\.]+', '-').Trim('-')
        $merged += [ordered]@{
            id           = $slug
            copilot_name = $l.Name
            vendor       = $l.Vendor
            category     = $l.Category
            release      = $l.Release
            price        = [ordered]@{ in = $l.In; cached_in = $l.CachedIn; out = $l.Out; cache_write = $l.CacheWrite }
            blended      = $l.Blended
            tier         = (Get-TierFromBlended $l.Blended)
            merit        = $null
            agent_mode   = $null
            notes        = 'NEW from refresh - set merit, confirm agent-mode support in the picker, then consider it for a role.'
        }
    }
}

# Keep registry entries the pricing table no longer lists, flagged rather than dropped.
foreach ($m in $current.models) {
    if ($liveNames -notcontains $m.copilot_name) {
        $keep = [ordered]@{}
        foreach ($p in $m.PSObject.Properties) { $keep[$p.Name] = $p.Value }
        $keep['notes'] = "NOT IN PRICING DOCS as of $(Get-Date -Format 'yyyy-MM-dd') - verify it still exists. " + [string]$m.notes
        $merged += $keep
    }
}

$out = [ordered]@{
    schema_version     = $current.schema_version
    verified_on        = (Get-Date -Format 'yyyy-MM-dd')
    sources            = $current.sources
    _pricing_note      = $current._pricing_note
    _blended_formula   = $current._blended_formula
    _merit_note        = $current._merit_note
    _agent_mode_note   = $current._agent_mode_note
    models             = $merged
    claude_code_models = $current.claude_code_models
}

$json = Format-ModelsJson ([pscustomobject]$out)
# Fail loudly rather than leaving the registry unparseable.
try { $json | ConvertFrom-Json | Out-Null }
catch { throw "Emitted JSON is invalid - registry not written. $($_.Exception.Message)" }
Write-Utf8NoBom $modelsPath ($json + "`n")

Write-Host "Wrote registry/models.json - $($merged.Count) models, verified_on $(Get-Date -Format 'yyyy-MM-dd')." -ForegroundColor Green
if ($added.Count -gt 0) {
    Write-Host "  $($added.Count) new model(s) have merit null and agent_mode null - set those before routing to them." -ForegroundColor Yellow
}
Write-Host '  Now run scripts/build.ps1 to regenerate the agents and docs/MODELS.md.' -ForegroundColor Cyan
Write-Host ''
