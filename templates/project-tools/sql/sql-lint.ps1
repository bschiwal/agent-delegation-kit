<#
.SYNOPSIS
    Mechanical checks on T-SQL scripts, so reviewers spend their turns on logic.

.DESCRIPTION
    Starter script from agent-delegation-kit. Copy it into the project's tools
    folder; the project owns it from then on - add the project's own rules here.

    Errors (exit code 1):
      batch-first    CREATE VIEW/PROCEDURE/FUNCTION/TRIGGER is not the first
                     statement of its batch (needs GO before it)
      batch-one      a second CREATE ... in the same batch (needs GO between)
      double-term    ;; - a compile error that a glance misses
      var-across-go  a @variable used in a later batch than the one declaring it
      header         a view without the header block (-HeaderPatterns)
      view-order     ORDER BY in a view without TOP or OFFSET
      never-output   a column from the never-output list (-NeverOutputFile)
                     appears in a SELECT list
    Warnings:
      select-star    SELECT * (in a view it is an error)
      nolock         NOLOCK / READUNCOMMITTED hint
      sqlcmd-check   a $(Variable) with no IF ... $(Variable) check before its use
      never-output-ref  a never-output column used outside a SELECT list (a join
                     or filter) - fine in itself, listed so a reviewer can confirm

    Output is one line per finding and a summary; it is built to be read by an
    agent, so it stays short.

.EXAMPLE
    .\tools\sql-lint.ps1 -Path .\sql
.EXAMPLE
    .\tools\sql-lint.ps1 -Path .\sql\04_export.sql,.\sql\07_audit.sql -NeverOutputFile .\tools\never-output.txt
#>
param(
    [string[]]$Path = @('.'),
    [string]$NeverOutputFile,
    [string[]]$HeaderPatterns = @('^\s*--\s*Grain:', '^\s*--\s*Source:', '^\s*--\s*Filters:'),
    [int]$HeaderWithinLines = 30,
    [int]$MaxFindings = 200
)

$ErrorActionPreference = 'Stop'

# Comments and string literals are blanked (line breaks kept), so line numbers
# hold and keywords inside them never count.
function Remove-CommentsAndStrings([string]$Sql) {
    $sb = New-Object System.Text.StringBuilder $Sql.Length
    $i = 0; $n = $Sql.Length
    while ($i -lt $n) {
        $c = $Sql[$i]
        if ($c -eq '-' -and $i + 1 -lt $n -and $Sql[$i + 1] -eq '-') {
            while ($i -lt $n -and $Sql[$i] -ne "`n") { [void]$sb.Append(' '); $i++ }
        }
        elseif ($c -eq '/' -and $i + 1 -lt $n -and $Sql[$i + 1] -eq '*') {
            $depth = 0
            do {
                if ($i + 1 -lt $n -and $Sql[$i] -eq '/' -and $Sql[$i + 1] -eq '*') { $depth++; [void]$sb.Append('  '); $i += 2; continue }
                if ($i + 1 -lt $n -and $Sql[$i] -eq '*' -and $Sql[$i + 1] -eq '/') { $depth--; [void]$sb.Append('  '); $i += 2; continue }
                if ($Sql[$i] -eq "`n") { [void]$sb.Append("`n") } else { [void]$sb.Append(' ') }
                $i++
            } while ($i -lt $n -and $depth -gt 0)
        }
        elseif ($c -eq "'") {
            [void]$sb.Append("'"); $i++
            while ($i -lt $n) {
                if ($Sql[$i] -eq "'") {
                    if ($i + 1 -lt $n -and $Sql[$i + 1] -eq "'") { [void]$sb.Append('  '); $i += 2; continue }
                    break
                }
                if ($Sql[$i] -eq "`n") { [void]$sb.Append("`n") } else { [void]$sb.Append(' ') }
                $i++
            }
            if ($i -lt $n) { [void]$sb.Append("'"); $i++ }
        }
        else { [void]$sb.Append($c); $i++ }
    }
    return $sb.ToString()
}

function Get-LineNumber([string]$Text, [int]$Index) {
    return ([regex]::Matches($Text.Substring(0, $Index), "`n")).Count + 1
}

$neverOutput = @()
if ($NeverOutputFile) {
    $neverOutput = @(Get-Content $NeverOutputFile | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') })
}

$files = @()
foreach ($p in $Path) {
    if (Test-Path $p -PathType Container) { $files += Get-ChildItem $p -Recurse -Filter *.sql | ForEach-Object { $_.FullName } }
    elseif (Test-Path $p) { $files += (Resolve-Path $p).Path }
    else { Write-Warning "Not found: $p" }
}
if ($files.Count -eq 0) { Write-Output 'sql-lint: no .sql files found'; exit 1 }

$findings = New-Object System.Collections.Generic.List[object]
function Add-Finding($File, $Line, $Level, $Rule, $Message) {
    $findings.Add([pscustomobject]@{ File = $File; Line = $Line; Level = $Level; Rule = $Rule; Message = $Message })
}

$base = (Get-Location).Path
foreach ($f in $files) {
    $rel = $f
    if ($f.StartsWith($base)) { $rel = $f.Substring($base.Length).TrimStart('\', '/') }
    $raw = [System.IO.File]::ReadAllText($f) -replace "`r`n", "`n"
    $bare = Remove-CommentsAndStrings $raw
    $lines = $bare -split "`n"
    $rawLines = $raw -split "`n"

    # Batches, split on GO lines as sqlcmd does. Each keeps its starting line.
    $batches = @()
    $start = 0
    for ($li = 0; $li -lt $lines.Count; $li++) {
        if ($lines[$li] -match '^\s*GO(\s+\d+)?\s*$') {
            $batches += [pscustomobject]@{ First = $start + 1; Text = (($lines[$start..([math]::Max($start, $li - 1))]) -join "`n"); Empty = ($li -eq $start) }
            $start = $li + 1
        }
    }
    if ($start -lt $lines.Count) { $batches += [pscustomobject]@{ First = $start + 1; Text = (($lines[$start..($lines.Count - 1)]) -join "`n"); Empty = $false } }

    $isView = $false
    $declaredIn = @{}
    for ($bi = 0; $bi -lt $batches.Count; $bi++) {
        $b = $batches[$bi]
        if ($b.Empty) { continue }
        $t = $b.Text

        # batch-first / batch-one
        $creates = [regex]::Matches($t, '(?i)\bCREATE\s+(OR\s+ALTER\s+)?(VIEW|PROC|PROCEDURE|FUNCTION|TRIGGER)\b')
        $alters = [regex]::Matches($t, '(?i)(?<!OR\s{1,5})\bALTER\s+(VIEW|PROC|PROCEDURE|FUNCTION|TRIGGER)\b')
        $defs = @($creates) + @($alters) | Sort-Object Index
        if ($defs.Count -gt 0) {
            $first = $defs[0]
            if ($first.Value -match '(?i)VIEW') { $isView = $true }
            if ($t.Substring(0, $first.Index).Trim() -ne '') {
                Add-Finding $rel ($b.First + (Get-LineNumber $t $first.Index) - 1) 'E' 'batch-first' "$($first.Value.ToUpper() -replace '\s+', ' ') must be the first statement in its batch - put GO before it"
            }
            for ($d = 1; $d -lt $defs.Count; $d++) {
                Add-Finding $rel ($b.First + (Get-LineNumber $t $defs[$d].Index) - 1) 'E' 'batch-one' 'a second object definition in the same batch - put GO between them'
            }
            if ($first.Value -match '(?i)VIEW') {
                $hasOrder = $t -match '(?i)\bORDER\s+BY\b'
                $hasTop = $t -match '(?i)\bTOP\s*\(|\bTOP\s+\d|\bOFFSET\s+'
                $inOver = $t -match '(?i)\bOVER\s*\([^)]*ORDER\s+BY'
                if ($hasOrder -and -not $hasTop -and -not $inOver) {
                    $m = [regex]::Match($t, '(?i)\bORDER\s+BY\b')
                    Add-Finding $rel ($b.First + (Get-LineNumber $t $m.Index) - 1) 'E' 'view-order' 'ORDER BY in a view without TOP or OFFSET - sort in the report instead'
                }
            }
        }

        # var-across-go: variables declared in earlier batches and used here without a new DECLARE
        $declaredHere = @{}
        foreach ($m in [regex]::Matches($t, '(?i)\bDECLARE\s+(@\w+)')) { $declaredHere[$m.Groups[1].Value.ToLower()] = $true }
        foreach ($m in [regex]::Matches($t, '(?i)\bDECLARE\s+@\w+[^;]*?,\s*(@\w+)')) { $declaredHere[$m.Groups[1].Value.ToLower()] = $true }
        $reported = @{}
        foreach ($m in [regex]::Matches($t, '(?<![@\w])(@\w+)')) {
            $v = $m.Groups[1].Value.ToLower()
            if ($declaredHere.ContainsKey($v) -or $reported.ContainsKey($v)) { continue }
            if ($declaredIn.ContainsKey($v)) {
                $reported[$v] = $true
                Add-Finding $rel ($b.First + (Get-LineNumber $t $m.Index) - 1) 'E' 'var-across-go' "$($m.Groups[1].Value) was declared in an earlier batch; a GO ends its scope - re-declare it or remove the GO"
            }
        }
        foreach ($k in $declaredHere.Keys) { $declaredIn[$k] = $bi }

        # never-output columns in a SELECT list (between SELECT and its FROM)
        if ($neverOutput.Count -gt 0) {
            foreach ($sel in [regex]::Matches($t, '(?is)\bSELECT\b(.*?)(\bFROM\b|$)')) {
                foreach ($col in $neverOutput) {
                    $cm = [regex]::Match($sel.Groups[1].Value, '(?i)(?<![\w])\[?' + [regex]::Escape($col) + '\]?(?![\w])')
                    if ($cm.Success) {
                        Add-Finding $rel ($b.First + (Get-LineNumber $t ($sel.Groups[1].Index + $cm.Index)) - 1) 'E' 'never-output' "$col is on the never-output list and appears in a SELECT list"
                    }
                }
            }
        }
    }

    # never-output columns used anywhere else (joins, filters): listed for a reviewer to confirm
    foreach ($col in $neverOutput) {
        $all = [regex]::Matches($bare, '(?i)(?<![\w])\[?' + [regex]::Escape($col) + '\]?(?![\w])')
        if ($all.Count -gt 0) {
            $flagged = @($findings | Where-Object { $_.File -eq $rel -and $_.Rule -eq 'never-output' -and $_.Message.StartsWith("$col ") })
            if ($all.Count -gt $flagged.Count) {
                Add-Finding $rel (Get-LineNumber $bare $all[0].Index) 'W' 'never-output-ref' "$col referenced $($all.Count) time(s) outside output - confirm it is only joined or filtered on"
            }
        }
    }

    # double-term
    foreach ($m in [regex]::Matches($bare, ';\s*;')) { Add-Finding $rel (Get-LineNumber $bare $m.Index) 'E' 'double-term' ';; - remove the extra terminator' }

    # header (views only)
    if ($isView) {
        $top = ($rawLines | Select-Object -First $HeaderWithinLines) -join "`n"
        $missing = @($HeaderPatterns | Where-Object { $top -notmatch "(?m)$_" })
        if ($missing.Count -gt 0) { Add-Finding $rel 1 'E' 'header' "view header missing: $(($missing | ForEach-Object { [regex]::Match($_, '[A-Za-z]{3,}').Value }) -join ', ')" }
    }

    # select-star, nolock
    foreach ($m in [regex]::Matches($bare, '(?i)\bSELECT\s+(DISTINCT\s+)?(TOP\s*\(?\s*\d+\s*\)?\s+)?\*')) {
        $lvl = 'W'; if ($isView) { $lvl = 'E' }
        Add-Finding $rel (Get-LineNumber $bare $m.Index) $lvl 'select-star' 'SELECT * - list the columns'
    }
    foreach ($m in [regex]::Matches($bare, '(?i)\b(NOLOCK|READUNCOMMITTED)\b')) { Add-Finding $rel (Get-LineNumber $bare $m.Index) 'W' 'nolock' "$($m.Value) hint - dirty reads give wrong numbers" }

    # sqlcmd-check: every $(Var) is checked by an IF before it is otherwise used
    $vars = @{}
    foreach ($m in [regex]::Matches($raw, '\$\((\w+)\)')) {
        $name = $m.Groups[1].Value
        if ($vars.ContainsKey($name)) { continue }
        $vars[$name] = $true
        $uses = [regex]::Matches($raw, '\$\(' + [regex]::Escape($name) + '\)')
        $checkLine = $null
        foreach ($u in $uses) {
            $ln = Get-LineNumber $raw $u.Index
            if ($rawLines[$ln - 1] -match '(?i)^\s*:setvar\b') { continue }
            if ($rawLines[$ln - 1] -match '(?i)\bIF\b') { $checkLine = $ln }
            break
        }
        if ($null -eq $checkLine) {
            $firstUse = Get-LineNumber $raw $uses[0].Index
            Add-Finding $rel $firstUse 'W' 'sqlcmd-check' "`$($name) is used before any IF checks its value - validate it at the top and THROW on a bad value"
        }
    }
}

$errors = @($findings | Where-Object { $_.Level -eq 'E' }).Count
$warnings = @($findings | Where-Object { $_.Level -eq 'W' }).Count
$shown = 0
foreach ($x in ($findings | Sort-Object File, Line)) {
    if ($shown -ge $MaxFindings) { Write-Output "... $($findings.Count - $shown) more not shown (-MaxFindings)"; break }
    Write-Output ('{0}:{1}  {2}  {3}  {4}' -f $x.File, $x.Line, $x.Level, $x.Rule, $x.Message)
    $shown++
}
$byRule = ($findings | Group-Object Rule | Sort-Object Name | ForEach-Object { "$($_.Name) $($_.Count)" }) -join ', '
if ($byRule) { $byRule = " ($byRule)" }
Write-Output "sql-lint: $($files.Count) files, $errors errors, $warnings warnings$byRule"
if (-not $NeverOutputFile) { Write-Output 'sql-lint: never-output check skipped - pass -NeverOutputFile' }
if ($errors -gt 0) { exit 1 }
exit 0
