# Installed by agent-delegation-kit. Edit hooks/fable-gate.ps1 in the kit and
# reinstall rather than editing this copy.
#
# PreToolUse hook for the Agent tool. Fable is reserved for work the user asked
# for, so a subagent call with model "fable" goes through silently only when:
#   - the user's latest request grants it ("ok to use Fable if you need it"), or
#   - since that request, the user picked a "Yes..." option on an AskUserQuestion
#     about Fable.
# A latest request that rules Fable out ("don't use fable") denies the call.
# Anything else falls back to Claude Code's own permission prompt, so the user
# always has the last word - and an unattended run, with nobody to approve,
# stays on the default model.
#
# Windows PowerShell 5.1, no dependencies. If the hook itself fails on a Fable
# call, it asks rather than letting the call through.

$ErrorActionPreference = 'Stop'

function Write-Decision {
    param([string]$Decision, [string]$Reason)
    $out = [ordered]@{
        hookSpecificOutput = [ordered]@{
            hookEventName            = 'PreToolUse'
            permissionDecision       = $Decision
            permissionDecisionReason = $Reason
        }
    }
    [Console]::Out.Write((ConvertTo-Json -InputObject $out -Depth 4 -Compress))
}

# Text the user actually typed, without IDE context, reminders or pasted blocks -
# an open file that mentions Fable is not a grant.
function Get-PromptText {
    param($Entry)
    $content = $Entry.message.content
    $text = ''
    if ($content -is [string]) { $text = $content }
    else {
        foreach ($part in @($content)) {
            if ($null -ne $part -and $part.type -eq 'text') { $text += "`n" + $part.text }
        }
    }
    $strip = '(?s)<(system-reminder|ide_[a-z_]+|command-[a-z-]+|local-command-[a-z-]+|pasted_content|task-notification)\b[^>]*>.*?</\1>'
    $text = [regex]::Replace($text, $strip, ' ')
    return $text.Replace([char]0x2019, "'").Replace([char]0x2018, "'")
}

# The word Fable, but not fable-gate.ps1 or other hyphenated names.
$F = '\bfable\b(?!-)'

# Refusals are anchored to a verb or a "no", so "don't hesitate to use Fable"
# is not one.
$refuse = @(
    "\b(don't|dont|do not|never|stop|quit|no longer|can't|cannot|try not to)\s+(ever\s+)?(use|using|pick|picking|run|running|escalate|escalating|switch|switching)?\s*(to\s+|on\s+)?$F",
    "\b(no|not|without|avoid|skip|no more)\s+$F",
    "$F\s+(isn't|is not)\s+(needed|necessary|allowed|ok|okay|worth it)\b",
    "$F\b[^.]{0,20}\btoo (expensive|costly|much)\b"
)
# Grants must be explicit permission or an imperative, never a bare mention.
$grant = @(
    "\b(ok|okay|fine|alright|allowed|permitted|approved|free)\s+(for you\s+)?to\s+(use|try|escalate to|switch to)\s+$F",
    "\byou\s+(can|may)\s+(use|try|escalate to|switch to)\s+$F",
    "\b(feel free|go ahead|don't hesitate|do not hesitate)\b[^.]{0,20}$F",
    "\bpermission\b[^.]{0,20}$F",
    "$F\s+is\s+(fine|ok|okay|allowed|approved)\b"
)
$imperative = "^\s*(please\s+|just\s+|and\s+)?(use|try)\s+$F"
# A question, even typed without its "?".
$question = '^\s*(so\s+|and\s+|but\s+)?(is|are|was|were|would|could|should|can|do|does|did|will|may|might|shall)\b'

# 'grant', 'refuse' or $null for one prompt's text. Questions never grant. A
# prompt that both grants and refuses ("no Fable for builds. Use Fable for the
# architect") is left to the permission prompt rather than guessed at.
function Get-PromptVerdict {
    param([string]$Text)
    $granted = $false
    $refused = $false
    foreach ($m in [regex]::Matches($Text, '[^.!?;\r\n]+[.!?;]?')) {
        $s = $m.Value
        if ($s -notmatch "(?i)$F") { continue }
        $isRefusal = $false
        foreach ($p in $refuse) { if ($s -match "(?i)$p") { $isRefusal = $true } }
        if ($isRefusal) { $refused = $true; continue }
        if ($s.TrimEnd().EndsWith('?') -or $s -match "(?i)$question") { continue }
        foreach ($p in $grant) { if ($s -match "(?i)$p") { $granted = $true } }
        foreach ($clause in ($s -split '[,:]')) {
            if ($clause -match "(?i)$imperative") { $granted = $true }
        }
    }
    if ($refused -and $granted) { return $null }
    if ($refused) { return 'refuse' }
    if ($granted) { return 'grant' }
    return $null
}

# True if this AskUserQuestion result shows a "Yes..." option picked on a
# question about Fable. A typed answer is not an option, so it never approves.
function Test-FableApproval {
    param($Entry)
    $result = $Entry.toolUseResult
    if ($null -ne $result -and $null -ne $result.answers) {
        foreach ($q in @($result.questions)) {
            if ($null -eq $q) { continue }
            $about = "$($q.question) $($q.header)" -match "(?i)$F"
            $picked = $result.answers.PSObject.Properties[$q.question]
            if (-not $about -or $null -eq $picked) { continue }
            $label = "$($picked.Value)"
            $isOption = @($q.options | Where-Object { $null -ne $_ -and $_.label -eq $label }).Count -gt 0
            if ($isOption -and $label -match '(?i)^\s*yes\b') { return $true }
        }
        return $false
    }
    # No structured result: fall back to the tool_result text, '"question"="label"'.
    foreach ($part in @($Entry.message.content)) {
        if ($null -eq $part -or $part.type -ne 'tool_result') { continue }
        foreach ($m in [regex]::Matches("$($part.content)", '"([^"]*)"="([^"]*)"')) {
            if ($m.Groups[1].Value -match "(?i)$F" -and $m.Groups[2].Value -match '(?i)^\s*yes\b') { return $true }
        }
    }
    return $false
}

$isFable = $false
try {
    [Console]::InputEncoding = New-Object System.Text.UTF8Encoding($false)
    $payload = [Console]::In.ReadToEnd() | ConvertFrom-Json
    $model = "$($payload.tool_input.model)"
    if ($model -notmatch '(?i)fable') { exit 0 }
    $isFable = $true

    $ask = 'Fable was not granted for this request. It costs about twice Opus per token. Approve to use it for this one call; deny to stay on the default model.'
    $path = "$($payload.transcript_path)"
    if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path -LiteralPath $path)) {
        Write-Decision 'ask' $ask
        exit 0
    }

    # Claude Code is still appending to the transcript, so open it shared.
    $fs = [System.IO.File]::Open($path, 'Open', 'Read', 'ReadWrite')
    try {
        $reader = New-Object System.IO.StreamReader($fs, (New-Object System.Text.UTF8Encoding($false)))
        $lines = $reader.ReadToEnd() -split "`n"
    }
    finally { $fs.Dispose() }

    # Walk back to the user's latest request, noting any Fable approval after it.
    $approved = $false
    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
        $line = $lines[$i]
        if ($line.IndexOf('"type":"user"') -lt 0) { continue }
        if ($line.IndexOf('"isSidechain":true') -ge 0 -or $line.IndexOf('"isMeta":true') -ge 0) { continue }

        # A compaction summary replaces everything before it, including the
        # request - an old grant it quotes does not carry over.
        if ($line.IndexOf('"isCompactSummary":true') -ge 0) { break }

        if ($line.IndexOf('"tool_result"') -ge 0) {
            # Cheap filter before parsing: tool results can be large.
            if ($approved -or $line -notmatch '(?i)fable' -or $line -notmatch 'answers|been answered') { continue }
            try { if (Test-FableApproval ($line | ConvertFrom-Json)) { $approved = $true } } catch { }
            continue
        }

        try { $entry = $line | ConvertFrom-Json } catch { continue }
        if ($entry.type -ne 'user') { continue }
        # Background-agent notifications and other harness messages are logged as
        # user lines too; only a human prompt counts. Older prompts have no origin.
        if ($null -ne $entry.origin -and $entry.origin.kind -ne 'human') { continue }

        $verdict = Get-PromptVerdict (Get-PromptText $entry)
        if ($verdict -eq 'refuse') {
            Write-Decision 'deny' 'The user ruled out Fable in this request. Run this agent on its default model.'
            exit 0
        }
        if ($verdict -eq 'grant' -or $approved) { exit 0 }   # no opinion: normal permissions apply
        break
    }

    # Reached a compaction summary or the start: a Yes picked since still counts.
    if ($approved) { exit 0 }
    Write-Decision 'ask' $ask
    exit 0
}
catch {
    if ($isFable) { Write-Decision 'ask' 'The Fable gate hit an error reading the transcript. Approve to use Fable for this call; deny to stay on the default model.' }
    exit 0
}
