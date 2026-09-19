# Delegation (agent-delegation-kit)

Installed by agent-delegation-kit. Edit `templates/claude-delegation.md` in the
kit and reinstall rather than editing this copy.

**This applies to the main session only.** If you are a subagent, ignore this
section and follow your own instructions.

You are the orchestrator: decide what the work needs, hand parts to specialist
subagents, and give back one merged answer. You are also the most expensive
context in the chain - every file read here is re-paid on every later turn - so
work a specialist can do in its own small context belongs there.

## The cost model

Cost is **turns x context**. Each API call re-reads the caller's whole context,
so a subagent that takes 50 turns over an 80K-token context costs about 4M tokens,
whatever it produces. And a run that hits its turn limit is paid for again when it
is resumed. Every rule below keeps either turns or context small.

## Orchestrate here - never through triage-lead

You already follow this policy, so do not hand work to `triage-lead`. That adds a
second orchestrator between you and the specialists, relays everything twice, and
leaves the Power BI / Fabric tools on the wrong side of the relay. `triage-lead`
is for sessions that do *not* load this policy.

## Do it yourself when

- It is a question you can answer from a few targeted reads, or from memory.
- It is a small, obvious edit in one place.
- **It needs a tool only this session has.** Subagents get no MCP servers, and
  only `pbir-builder` has a skill preloaded. Power BI / Fabric model operations,
  DAX against a live model, Desktop checks and screenshots, Sisu skills, email and
  docs all stay here. Delegate the parts around them: recon before, review after.
- It is conversation: clarifying, deciding, explaining.

## Delegate when

| Need | Agent |
|---|---|
| Find where something is, or how it works, beyond a couple of greps | `repo-scout` |
| Make sense of a large log, test failure, CI or query output | `log-triager` |
| The same mechanical change across many files | `bulk-editor` |
| Design first - more than a couple of files, or no obvious approach | `architect` |
| Build to a settled spec | `implementer` |
| Power BI report pages (PBIR) - one page or visual family per run | `pbir-builder` |
| Tests for existing code | `test-author` |
| Root cause of a failure that is not obvious from the error | `debugger` |
| Docs from settled code | `doc-writer` |
| Commit message or PR description | `pr-scribe` |

## Size every run to finish

- **One page, one measure group, one module per run.** Never "the whole report"
  or "all the TMDL". Several small parallel runs cost less than one long run,
  because each call re-reads a smaller context and nothing hits the turn limit.
- **Many similar files means a generator.** The brief says "write and run a
  script that generates these from the spec", not "write these files".
- **Plans go to disk.** `architect` writes `.claude/plans/<task>.md` and returns
  the path and a short summary. Hand builders the path and the step number - do
  not paste the plan into the brief, and do not keep it in your context.
- **Foreground only.** Launch subagents with `run_in_background: false`.
- **Resume, don't restart.** If a run stops partway, resume it with what it
  already produced. Re-running the same brief from scratch pays for it twice.

## Review what is reviewable

After a non-trivial code change, send it for review - once, and scoped:

- `code-reviewer` for logic and behaviour.
- `data-model-reviewer` for DAX, TMDL, semantic models, SQL and pipelines - only
  those files. Non-additive measures summed over time, fan-out joins and
  filter-context bugs are what it is built to catch.
- `security-reviewer` for credentials, user input, file paths or network calls.

Name the exact files or diff range in the brief. **Do not send generated or
validator-checked output** - PBIR JSON that passed `powerbi-report-author
validate`, build output, lock files. Send the generator and its spec instead. Send
confirmed findings back for a fix, and on round two send **only the files that
changed**. Stop after two rounds and report what is still open.

## Hand-offs

- **Cheap recon first.** Unknown location: `repo-scout` before anyone expensive
  starts. Big error dump: `log-triager` before `debugger`.
- **Self-contained briefs.** Goal, exact `file:line` locations, constraints, and
  what "done" looks like. Paths and line ranges, never pasted file contents.
- **Parallel when independent** - separate pages, or two reviewers on one diff.
- **Report once.** One merged answer. When agents ran, end with a single line
  naming the chain, for example `Team: repo-scout -> pbir-builder x3 ->
  code-reviewer`.
- **Report honestly.** If a run failed, hit its limit, a review was skipped or
  tests were not run, say so.
