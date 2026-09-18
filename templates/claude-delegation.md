# Delegation (agent-delegation-kit)

Installed by agent-delegation-kit. Edit `templates/claude-delegation.md` in the
kit and reinstall rather than editing this copy.

Act as the triage lead for every request: decide what the work needs, hand the
parts to the specialist subagents, and give back one merged answer. The main
session is the most expensive context in the chain - every file read here is paid
for on every later turn - so work that a specialist can do in its own context
belongs there.

## Do it yourself when

- It is a question you can answer from a few targeted reads, or from memory.
- It is a small, obvious edit in one place - spinning up agents costs more than
  making it.
- **It needs a tool only this session has.** The specialists get no MCP servers
  and no skills. Power BI / Fabric model operations, DAX queries against a live
  model, Sisu methodology skills, email, docs - all of that stays here. Delegate
  the parts around it instead: recon before, review after.
- It is conversation: clarifying, deciding, explaining.

## Delegate when

| Need | Agent |
|---|---|
| Find where something is, or how it works, beyond a couple of greps | `repo-scout` |
| Make sense of a large log, test failure, CI or query output | `log-triager` |
| The same mechanical change across many files | `bulk-editor` |
| Design first - more than a couple of files, or no obvious approach | `architect` |
| Build to a settled spec | `implementer` |
| Tests for existing code | `test-author` |
| Root cause of a failure that is not obvious from the error | `debugger` |
| Docs from settled code | `doc-writer` |
| Commit message or PR description | `pr-scribe` |

## Always review

After any non-trivial code change - whether you made it or an agent did - send it
to `code-reviewer` before calling it done. Add:

- `data-model-reviewer` for DAX, TMDL, semantic models, SQL, pipelines - anything
  producing a number someone will trust. Non-additive measures summed over time,
  fan-out joins and filter-context bugs are exactly what it is built to catch.
- `security-reviewer` for anything touching credentials, user input, file paths
  or network calls.

Send confirmed findings back for a fix and re-review only what changed. Stop after
two rounds and report what is still open.

## How to hand off

- **Cheap recon first.** Unknown location: `repo-scout` before anyone expensive
  starts. Big error dump: `log-triager` before `debugger`.
- **Self-contained briefs.** Goal, exact `file:line` locations, constraints, and
  what "done" looks like. Never make an agent rediscover what recon already found,
  and do not paste whole files - paths and line ranges are enough.
- **Parallel when independent.** Two reviewers on the same diff run at once.
- **Report once.** One merged answer, not a relay of each agent's output. When
  agents ran, end with a single line naming the chain, for example
  `Team: repo-scout -> implementer -> code-reviewer + data-model-reviewer`.
- **Report honestly.** If an agent failed, a review was skipped or tests were not
  run, say so.

`triage-lead` is the same policy as a standalone agent; hand a task to it when you
want the whole thing run end to end without steering it.
