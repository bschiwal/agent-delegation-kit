# Installed by agent-delegation-kit. Edit hooks/context-meter.ps1 in the kit and
# reinstall rather than editing this copy.
#
# UserPromptSubmit hook. Tells the main session how big its own context is.
# Every after-action report so far said "I can't see my own token count", and
# the rule to hand off at a gate was skipped four sessions running while that
# context grew past 100K (2026-09-28 reviews).
#
# On each user message it reads the session transcript and adds one line:
# the current context (the last assistant turn's input + cache write + cache
# read tokens) and the total input read so far (the same sum over every turn).
# Above $WarnAt it adds the hand-off advice; above $StrongAt, more firmly.
# Subagent transcripts live in separate files, so only the main session counts.
# Any error produces no output: the prompt goes through unchanged.
#
# Windows PowerShell 5.1, no dependencies.

$WarnAt = 100000
$StrongAt = 150000

$ErrorActionPreference = 'Stop'

function Get-Count {
    param([string]$Text, [string]$Key)
    $m = [regex]::Match($Text, '"' + $Key + '":(\d+)')
    if ($m.Success) { return [long]$m.Groups[1].Value }
    return [long]0
}

function Format-Tokens {
    param([long]$N)
    if ($N -ge 1000000) { return ('{0:0.0}M' -f ($N / 1000000.0)) }
    return ('{0}k' -f [math]::Round($N / 1000.0))
}

try {
    $in = [Console]::In.ReadToEnd() | ConvertFrom-Json
    $tp = [string]$in.transcript_path
    if ([string]::IsNullOrEmpty($tp) -or -not (Test-Path -LiteralPath $tp)) { exit 0 }

    # One entry per assistant message id: a message is written as several lines,
    # one per content block, each carrying the same usage.
    $turns = @{}
    $lastId = $null
    $fs = New-Object System.IO.FileStream($tp, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    $reader = New-Object System.IO.StreamReader($fs)
    try {
        while ($null -ne ($line = $reader.ReadLine())) {
            if ($line.IndexOf('"role":"assistant"') -lt 0) { continue }
            if ($line.IndexOf('"isSidechain":true') -ge 0) { continue }
            $u = $line.IndexOf('"usage":')
            if ($u -lt 0) { continue }
            $id = [regex]::Match($line, '"id":"(msg_[^"]+)"')
            if (-not $id.Success) { continue }
            $usage = $line.Substring($u)
            $turns[$id.Groups[1].Value] = (Get-Count $usage 'input_tokens') +
                (Get-Count $usage 'cache_creation_input_tokens') +
                (Get-Count $usage 'cache_read_input_tokens')
            $lastId = $id.Groups[1].Value
        }
    }
    finally { $reader.Dispose() }
    if ($null -eq $lastId) { exit 0 }

    $current = [long]$turns[$lastId]
    $total = [long]0
    foreach ($v in $turns.Values) { $total += [long]$v }

    $note = 'agent-delegation-kit context: this session''s context is about ' +
        (Format-Tokens $current) + ' tokens, and it has read about ' +
        (Format-Tokens $total) + ' input tokens so far over ' + $turns.Count +
        ' turns. Use these figures for the Main session line of the team report.'
    if ($current -ge $StrongAt) {
        $note += ' This is past ' + (Format-Tokens $StrongAt) + ': every further turn re-reads all of' +
            ' it. Unless you are mid-step, write the resume note now and ask the user' +
            ' the Hand off? question.'
    }
    elseif ($current -ge $WarnAt) {
        $note += ' This is past ' + (Format-Tokens $WarnAt) + '. If the last step was a gate - a' +
            ' pass reviewed, a Desktop save checked - write the resume note and ask the' +
            ' user the Hand off? question before starting more work.'
    }

    $out = [ordered]@{
        hookSpecificOutput = [ordered]@{
            hookEventName     = 'UserPromptSubmit'
            additionalContext = $note
        }
    }
    [Console]::Out.Write((ConvertTo-Json -InputObject $out -Depth 4 -Compress))
    exit 0
}
catch {
    exit 0
}
