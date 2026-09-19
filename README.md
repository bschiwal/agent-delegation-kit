# agent-delegation-kit

A shared set of specialist agent profiles for **Claude Code** (CLI and Claude
Desktop) and **GitHub Copilot** (VS Code), with one routing policy that decides
which model each agent runs on.

The point: **reviewing runs on the best Claude model, everything else runs on the
cheapest model that can finish the job.** You write an agent once; the kit emits
it in both platforms' formats with the right model already filled in.

```
registry/agents/code-reviewer.md          <- you write this once
          |
          +-- build/claude/agents/code-reviewer.md          model: opus
          +-- build/copilot/agents/code-reviewer.agent.md   model: ['Claude Opus 5', ...]
```

---

## Install

Requires Windows PowerShell 5.1 (built into Windows) and git. Nothing else - no
Node, no Python, no modules.

```powershell
git clone https://github.com/BSchiwal/agent-delegation-kit.git
cd agent-delegation-kit
.\scripts\install.ps1
```

That builds the agents and installs them for both Claude Code and Copilot, for
every project on the machine. Restart Claude Code and reload VS Code, and the
agents are there.

Platform-specific walkthroughs: [Claude Code and Claude Desktop](docs/claude-setup.md)
and [VS Code + Copilot](docs/vscode-copilot-setup.md).

If PowerShell blocks the script, allow local scripts for your user once:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

### Install options

| Command | Result |
|---|---|
| `.\scripts\install.ps1` | Both platforms, user-wide |
| `.\scripts\install.ps1 -Target claude` | Claude Code only |
| `.\scripts\install.ps1 -Target copilot` | Copilot only |
| `.\scripts\install.ps1 -Preset work` | Apply the workplace model policy (see below) |
| `.\scripts\install.ps1 -WithInstructions` | **Recommended.** Every Claude Code session orchestrates the agents itself (no need to name them); also installs Copilot model-routing rules |
| `.\scripts\install.ps1 -Scope project -Path C:\repos\my-app` | Install into one repo, to commit and share with a team |
| `.\scripts\install.ps1 -Uninstall` | Remove everything this kit installed |

Installs are tracked in a manifest, so `-Uninstall` removes exactly what the kit
put there and leaves your own agents alone. If a file it would write already
exists and the kit did not create it, the install skips it and tells you; add
`-Force` to overwrite.

### Where files land

| Platform | Scope | Path |
|---|---|---|
| Claude Code / Claude Desktop | user | `~\.claude\agents\` |
| Claude Code / Claude Desktop | project | `<repo>\.claude\agents\` |
| Copilot (VS Code) | user | `~\.copilot\agents\` |
| Copilot (VS Code) | project | `<repo>\.github\agents\` |
| Copilot instructions | user | `~\.copilot\instructions\` |
| Copilot instructions | project | `<repo>\.github\instructions\` |

VS Code also reads `.claude/agents`, so a project-scope install gives Copilot two
copies of each agent. Use `-Target copilot -Scope project` if you only want one.

---

## Using the agents

### Claude Code (CLI, and Claude Desktop)

Claude Desktop runs the same Claude Code engine and reads the same
`~\.claude\agents` folder, so one install covers both.

- Ask *"which subagents do you have?"* to confirm they loaded. (Claude Code
  removed its `/agents` wizard; agents are plain files in `~\.claude\agents`.)
- Ask for one by name: *"use code-reviewer on this branch"*.
- Claude also picks agents on its own from their `description`, so
  *"review this diff"* usually routes to `code-reviewer` without being told.

Each agent carries its own model, tool allow-list, effort level and turn cap, so
delegating to `repo-scout` genuinely costs less than searching inline - it runs
on Haiku at low effort with no write tools.

### Delegation: you don't pick the agents

There is one delegation policy, and it can run in two places:

| Where you work | Who orchestrates | What you do |
|---|---|---|
| **Claude Code, installed with `-WithInstructions`** (recommended) | The main session itself | Nothing - just describe the task |
| **Copilot**, or Claude Code without the policy | `triage-lead` | Pick `triage-lead` and describe the task |

Either way the work goes the same route. Recon goes to cheap agents first, then
design if the approach isn't obvious, then the build. Every code change goes
through `code-reviewer`, and anything that produces a number also goes through
`data-model-reviewer`. The answer ends with the chain that actually ran:

```
Team: repo-scout -> pbir-builder x3 -> code-reviewer + data-model-reviewer
```

A code change whose team line has no reviewer means the review was skipped, so ask
for it. The policy is strong guidance, not an enforced rule.

**Claude Code.** `-WithInstructions` adds the policy to `~\.claude\CLAUDE.md`
through one marked import block, so every session orchestrates on Opus with its
full tools, MCP servers, skills and memory. In that setup the installer **skips
`triage-lead`** on purpose. A second orchestrator under the main session relays
everything twice and can't reach the Power BI / Fabric tools - see
[docs/routing.md](docs/routing.md#4-cost-is-turns-times-context) for what that cost.
Don't set `"agent": "triage-lead"` in your settings either, because that replaces
the system prompt and strips the session's tools. Details in
[docs/claude-setup.md](docs/claude-setup.md#make-every-session-a-triage-lead).

**Copilot.** Copilot never loads `CLAUDE.md`, so `triage-lead` is how you get
delegation there. It has no edit tools on purpose, so it can't skip a specialist
and do the work itself. It hands back anything that needs tools it doesn't have.

**Want the plan before any work?** Ask for "a plan only". The main session or
`triage-lead` returns the plan and runs nothing. For a design of the code itself,
ask `architect`, which writes the plan to `.claude/plans/`.

The routing rules live once, in `templates/partials/delegation-core.md`, and are
built into both the Claude Code policy and `triage-lead`, so the two can't drift
apart.

### GitHub Copilot (VS Code)

Needs a recent VS Code with the Copilot Chat extension - custom agents use the
`.agent.md` format that replaced custom chat modes. If your Chat view shows
"chat modes" rather than "agents", update VS Code.

- Open Chat and pick the agent from the dropdown above the input box.
- `/agents` opens **Configure Custom Agents** to see and edit them.
- Each agent's `model:` is a prioritised list - VS Code tries them in order and
  uses the first one available to your plan, so a model your org has disabled
  falls through to the next instead of failing.

---

## The routing policy

Agents never name a model. They name a **role**, and
[`registry/policy.json`](registry/policy.json) maps roles to models. Change the
policy once and every agent follows on the next build.

| Role | Claude Code | Copilot | Why |
|---|---|---|---|
| `review` | `opus` | Claude Opus 5 | Quality first. A missed bug costs more than the tokens. |
| `deep-reasoning` | `opus` | Claude Opus 5 | A bad plan is paid for by every agent downstream. |
| `triage` | `sonnet` | Claude Sonnet 5 | Runs in front of every request, so it must be cheap; delegates the deep thinking. |
| `implement` | `sonnet` | Claude Sonnet 5 | Best merit-per-dollar in the standard tier. |
| `bulk-edit` | `haiku` | MAI-Code-1.1-Flash | Mechanical and verifiable - judgement barely matters. |
| `search` | `haiku` | GPT-5.6 Luna | Burns input tokens, needs almost no reasoning. |
| `summarize` | `haiku` | GPT-5.6 Luna | Highest-leverage cheap role in the kit. |
| `write-prose` | `haiku` | GPT-5.6 Luna | Cheap tier is fine for docs and commit messages. |

Full reasoning in [docs/routing.md](docs/routing.md). Generated price and merit
tables in [docs/MODELS.md](docs/MODELS.md).

### Reviewers stay on Claude

Every review agent routes to Claude Opus 5, with Opus 4.8 and 4.7 as availability
fallbacks. The only non-Claude fallback on a review role is GPT-6 Astra, and it
sits last as a backstop for when Claude is unavailable - it is not a cost saving,
it costs twice what Opus 5 does.

### Cheap is measured, not assumed

Blended cost per 1M tokens (`0.8 x input + 0.2 x output`, because agent turns are
input-heavy):

| Model | Blended | |
|---|---:|---|
| GPT-5.6 Luna, MAI-Code-1.1-Flash | 0.40 | the real cheap tier |
| Gemini 3.7 Flash | 1.35 | promo pricing through 2026-12-31 |
| Claude Sonnet 5 | 3.60 | |
| GPT-5.4 | 5.00 | **more expensive than Sonnet 5** |
| Claude Opus 5 | 9.00 | |
| GPT-5.5 | 10.00 | **more expensive than Opus 5** |
| GPT-6 Astra | 18.00 | |

Two things worth knowing before you swap a Claude model out to save money:

1. **Claude Sonnet 5 ($2/$10) is cheaper than GPT-5.4, GPT-5.5, GPT-5.6 Sol and
   Gemini 3.5 Flash.** The familiar advice to avoid Sonnet was written against
   Sonnet 4 at $3/$15. Substituting GPT-5.4 for Sonnet 5 raises the bill by ~40%.
2. **Claude Opus 5 is cheaper than GPT-5.5 and GPT-6 Astra.** If the task needs a
   frontier model, Opus 5 is the economical frontier choice.

The genuinely cheap models are GPT-5.6 Luna, MAI-Code-1.1-Flash, GPT-5.4 nano and
GPT-5 mini - all around $0.20 input. That is the tier worth routing bulk work to,
and it is where this kit sends it.

### The work preset

If your employer asks that Anthropic models be reserved for work that needs them,
build with `-Preset work`. Reviewing and reasoning keep Claude - that *is* the
work that needs it - while `implement` and `write-prose` move to non-Anthropic
models even where Sonnet 5 would have been cheaper:

```powershell
.\scripts\install.ps1 -Preset work
```

Edit `workplace_overrides.profiles.work` in
[`registry/policy.json`](registry/policy.json) to match your own policy.

---

## Availability: what you can actually pick

Your model picker shows a fraction of GitHub's catalogue - plan tier and org
policy remove models, usually the expensive top-end ones this kit prefers. That
matters, because an agent whose whole fallback chain is blocked does not fail
loudly; it falls through and the host substitutes something, possibly the cheapest
model available. A review that looks like a review and isn't.

So record what you actually have. In VS Code, `Ctrl+Alt+.` shows the picker:

```powershell
.\scripts\set-availability.ps1 -List     # what is recorded, and what each role resolves to
.\scripts\set-availability.ps1 -Preset work -Mode allow `
  -Models 'Claude Sonnet 5','Claude Haiku 4.5','GPT-5.6 Luna','Gemini 3.7 Flash'
.\scripts\build.ps1 -Preset work
```

The build then strips blocked models from every agent and tells you where it hurt:

```
Availability: mode 'allow', 6 of 29 models reachable

SUBSTITUTED - every preferred model for these roles is blocked:
  role 'review' (quality-first)
    wanted: Claude Opus 5, Claude Opus 4.8, Claude Opus 4.7, GPT-6 Astra
    using:  Claude Sonnet 5 (merit 4)
```

Substitution picks by the role's `cost_posture` - highest merit for
`quality-first`, cheapest viable for `cheapest-viable` - and never picks an
unscored model. It is a safety net, not a fix: when you see it, put a model you
can reach into that role in `policy.json`.

**If the top models are blocked for you**, the shortest path is to run reviews in
Claude Code instead - it bills through your Claude subscription rather than
Copilot, so an org restriction on Copilot models doesn't apply. Implement in
Copilot, review in Claude Code, same agents on both sides. Full detail in
[docs/availability.md](docs/availability.md).

Availability is tracked per preset, so `work` and `personal` differ independently.

---

## Keeping the model list current

Copilot's catalogue changes every few weeks. The kit reads it from GitHub's own
docs rather than hardcoding it.

**Manually:**

```powershell
.\scripts\refresh-models.ps1          # report what changed
.\scripts\refresh-models.ps1 -Apply   # write registry/models.json
.\scripts\build.ps1                   # regenerate agents and docs
```

The report tells you what is new, what changed price, what disappeared, and -
importantly - whether `policy.json` still routes to a model that no longer exists.

**Automatically:** [`.github/workflows/refresh-models.yml`](.github/workflows/refresh-models.yml)
runs the same check every Monday and opens a PR when anything moved. The PR body
lists each new model with its price and tier and flags that it needs a merit
score, so releases arrive as a reviewable diff instead of being noticed six months
later. `workflow_dispatch` runs it on demand, with an option to report without
committing.

`-Apply` overwrites prices, vendors, category and release status. It never
overwrites `merit`, `agent_mode` or `notes`: those are your editorial judgements,
and a scraper should not silently replace your opinion of a model with a number
off a web page. New models arrive with `merit: null`, and automatic substitution
never picks an unscored model - so a model nobody has evaluated cannot quietly
become your code reviewer.

---

## Adding or changing an agent

One file per agent in [`registry/agents/`](registry/agents/): a JSON frontmatter
block, then the prompt as markdown.

```markdown
---
{
  "name": "my-agent",
  "role": "review",
  "description": "When Claude or Copilot should delegate to this agent.",
  "claude":  { "tools": "Read, Grep, Glob, Bash", "maxTurns": 30, "color": "red" },
  "copilot": { "tools": ["read", "search"] }
}
---

You are a ... (the system prompt)
```

- `role` must exist in `policy.json` - that is what supplies the model.
- Anything under `claude` or `copilot` is passed through to that platform's
  frontmatter verbatim, so you can use any field either platform supports
  (`permissionMode`, `effort`, `omitClaudeMd`, `handoffs`, `agents`, ...).
- Never put a `model` in an agent. The build drops it and warns, because a
  hardcoded model is exactly what goes stale.

Then `.\scripts\install.ps1`.

The build validates as it goes: unknown role, malformed JSON, or a Copilot model
that is chat-only and cannot drive an agent all surface as errors or warnings.

---

## The agents

| Agent | Role | Use it for |
|---|---|---|
| `code-reviewer` | review | Correctness bugs in a diff, before a PR |
| `security-reviewer` | review | Injection, authz gaps, secret exposure, SSRF |
| `data-model-reviewer` | review | Wrong numbers in semantic models, DAX, SQL |
| `architect` | deep-reasoning | A plan before code exists |
| `debugger` | deep-reasoning | Root cause of a failure |
| `triage-lead` | triage | Orchestrator for Copilot, or Claude Code without the delegation policy - also does "plan only" |
| `implementer` | implement | Build to a settled spec |
| `pbir-builder` | implement | Power BI report pages from a spec, via a generator script - one page per run |
| `model-builder` | implement | Live Power BI model changes via the modeling MCP, tested with DAX - Claude Code only, uses your session's connection |
| `test-author` | implement | Tests for existing code |
| `bulk-editor` | bulk-edit | The same mechanical change across many files |
| `repo-scout` | search | Where is X, how does Y work |
| `log-triager` | summarize | Compress a wall of build or test output |
| `doc-writer` | write-prose | Docs from settled code |
| `pr-scribe` | write-prose | Commit messages and PR descriptions |

The highest-value combination is **cheap model implements, Claude reviews** -
`implementer` then `code-reviewer`. It generally beats doing the whole job on a
premium model, and it certainly beats doing the whole job cheaply.

---

## Repo layout

```
registry/
  models.json       model catalogue: prices, tiers, merit scores
  availability.json what your plan and org actually let you pick
  policy.json       roles -> models. The file you edit to change routing.
  agents/           agent sources, one per agent
templates/
  model-routing.instructions.md   always-on rules; tables filled in at build
scripts/
  build.ps1           registry -> build/
  install.ps1         build/ -> Claude Code and Copilot
  refresh-models.ps1  GitHub docs -> registry/models.json
  set-availability.ps1  record which models you can actually reach
build/                generated; committed so a clone installs without building
docs/
  routing.md          why the policy is what it is
  availability.md     handling blocked models
  claude-setup.md     Claude Code and Claude Desktop walkthrough
  vscode-copilot-setup.md   VS Code + Copilot walkthrough
  MODELS.md           generated price and merit tables
```

## Notes and limits

- **Windows-first.** The scripts target Windows PowerShell 5.1 because that is
  what ships on Windows. They avoid PowerShell 7 syntax, so they should run under
  `pwsh` on macOS and Linux, but that is untested.
- **Merit scores are opinions.** The 1-5 `merit` column in `models.json` is a
  hand-maintained judgement of quality ignoring price, not a benchmark. Tune it
  when your experience disagrees.
- **Prices move.** Re-run `refresh-models.ps1` occasionally. The Gemini Flash
  promotional pricing in particular expires 2026-12-31.
