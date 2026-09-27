# Installed by agent-delegation-kit. Edit hooks/turn-budget.ps1 in the kit and
# reinstall rather than editing this copy.
#
# PostToolUse hook. Tells a kit subagent which turn it is on, because agents do
# not keep count themselves: the budget footer said "reply by turn 36" and a
# 40-turn builder still ran out of turns with no report (2026-09-27 AAR).
#
# For a subagent call only (the input carries agent_id and agent_type):
#   - finds the installed agent file, and reads its two deadlines from the
#     generated Turn budget footer, so build.ps1 stays the one place they are set;
#   - counts the subagent's turns: distinct assistant message ids in its own
#     transcript, <session>/subagents/agent-<agent_id>.jsonl, so parallel tool
#     calls in one turn count once;
#   - at the stop-new-work turn, adds one notice; from the reply turn on, adds a
#     notice after every tool call.
# The main session, agents without a kit footer, and any error all produce no
# output. A PostToolUse hook cannot block anything, so failing quietly is safe.
#
# Windows PowerShell 5.1, no dependencies.

$ErrorActionPreference = 'Stop'

try {
    $in = [Console]::In.ReadToEnd() | ConvertFrom-Json
    if ([string]::IsNullOrEmpty($in.agent_id) -or [string]::IsNullOrEmpty($in.agent_type)) { exit 0 }
    if ($in.agent_type -notmatch '^[A-Za-z0-9_-]+$') { exit 0 }

    # Project agents win over user agents, as in Claude Code.
    $userHome = $env:USERPROFILE
    if ([string]::IsNullOrEmpty($userHome)) { $userHome = $HOME }
    $roots = @()
    if (-not [string]::IsNullOrEmpty($in.cwd)) { $roots += $in.cwd }
    $roots += $userHome
    $candidates = @()
    foreach ($r in $roots) {
        $candidates += Join-Path (Join-Path (Join-Path $r '.claude') 'agents') ($in.agent_type + '.md')
    }
    $agentText = $null
    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath $c) { $agentText = [System.IO.File]::ReadAllText($c); break }
    }
    if ($null -eq $agentText) { exit 0 }

    $mMax = [regex]::Match($agentText, '(?m)^maxTurns:\s*(\d+)')
    $mWrap = [regex]::Match($agentText, 'By about \*\*turn (\d+)\*\*')
    $mReply = [regex]::Match($agentText, 'By turn (\d+), write your reply')
    if (-not ($mMax.Success -and $mWrap.Success -and $mReply.Success)) { exit 0 }
    $max = [int]$mMax.Groups[1].Value
    $wrap = [int]$mWrap.Groups[1].Value
    $reply = [int]$mReply.Groups[1].Value

    $tp = [string]$in.transcript_path
    if (-not $tp.EndsWith('.jsonl')) { exit 0 }
    $sub = Join-Path (Join-Path $tp.Substring(0, $tp.Length - 6) 'subagents') ('agent-' + $in.agent_id + '.jsonl')
    if (-not (Test-Path -LiteralPath $sub)) { exit 0 }

    # The transcript is still being written, so open it shared.
    $ids = @{}
    $fs = New-Object System.IO.FileStream($sub, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    $reader = New-Object System.IO.StreamReader($fs)
    try {
        while ($null -ne ($line = $reader.ReadLine())) {
            if ($line.IndexOf('"role":"assistant"') -lt 0) { continue }
            $m = [regex]::Match($line, '"id":"(msg_[^"]+)"')
            if ($m.Success) { $ids[$m.Groups[1].Value] = $true }
        }
    }
    finally { $reader.Dispose() }
    $turn = $ids.Count

    $note = $null
    if ($turn -ge $reply) {
        $note = "agent-delegation-kit turn budget: this is turn $turn of $max. Write your reply now, " +
            'in your next turn, whatever state the work is in. Start no more tool calls except ' +
            'one to update your progress file if you keep one. Open items go under Not finished, ' +
            'with where to resume.'
    }
    elseif ($turn -eq $wrap) {
        $note = "agent-delegation-kit turn budget: this is turn $turn of $max. Stop starting new " +
            'work: finish or back out the step in progress, and update your progress file if you ' +
            "keep one. Your reply is due by turn $reply."
    }
    if ($null -eq $note) { exit 0 }

    $out = [ordered]@{
        hookSpecificOutput = [ordered]@{
            hookEventName     = 'PostToolUse'
            additionalContext = $note
        }
    }
    [Console]::Out.Write((ConvertTo-Json -InputObject $out -Depth 4 -Compress))
    exit 0
}
catch {
    exit 0
}
