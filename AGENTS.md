# Working on this repo

This repo generates agent profiles for two platforms from one source. Read
`README.md` for what it does; this file is about changing it.

## The one rule

**Never put a model name in an agent source.** Agents name a `role`;
`registry/policy.json` maps roles to models. That indirection is the whole point -
Copilot's catalogue changes every few weeks, and a model hardcoded in fourteen
agent files is fourteen files to fix. `build.ps1` drops a stray `model` field and
warns.

## Where to make a change

| I want to... | Edit |
|---|---|
| Change which model a kind of work uses | `registry/policy.json` -> `roles` |
| Satisfy an employer model policy | `registry/policy.json` -> `workplace_overrides` |
| Add or reword an agent's prompt | `registry/agents/<name>.md` |
| Correct a price | Run `scripts/refresh-models.ps1 -Apply` - do not hand-edit |
| Change a merit score or note | `registry/models.json` - these are hand-maintained |
| Record which models your org actually allows | `scripts/set-availability.ps1` - do not hand-edit availability.json |
| Change the always-on chat rules | `templates/model-routing.instructions.md` |
| Change the auto-refresh schedule | `.github/workflows/refresh-models.yml` |

After any change: `.\scripts\build.ps1`. Then `.\scripts\install.ps1` to pick it
up locally.

## Generated files

`build/` and `docs/MODELS.md` are generated. Do not hand-edit them; the next build
overwrites. They are committed anyway so that cloning and running `install.ps1`
works without a build step.

In `templates/model-routing.instructions.md`, the regions between
`<!-- BEGIN:x -->` and `<!-- END:x -->` are filled in by `build.ps1`. Edit the
prose around them, not inside them.

## Agent source format

A `---` fenced **JSON** block, then the prompt as markdown. JSON rather than YAML
because PowerShell 5.1 parses JSON natively and has no YAML support without a
module, and this repo deliberately has no dependencies.

```markdown
---
{
  "name": "kebab-case-name",
  "role": "must exist in policy.json",
  "description": "When to delegate to this agent - this is what Claude and Copilot match on.",
  "claude":  { "tools": "Read, Grep", "maxTurns": 30 },
  "copilot": { "tools": ["read", "search"] }
}
---

You are a ...
```

Everything under `claude` or `copilot` passes through to that platform's
frontmatter verbatim, so any field either platform supports works without changing
the build script. `tools` is a comma-separated string for Claude and an array for
Copilot - that difference is in the platforms, not this repo.

Two top-level fields control orchestration, and neither is emitted as-is:

| Field | Effect |
|---|---|
| `"delegates": "*"` | This agent orchestrates. The build generates its allow-list from every delegable agent except itself: `Agent(a, b, ...)` prepended to Claude `tools`, and `agents: [...]` plus the `agent` tool set for Copilot. An array of names instead of `"*"` restricts it, and unknown names fail the build. |
| `"delegable": false` | Keep this agent out of every orchestrator's allow-list. Set on `triage-lead` (no orchestrator calls another) and `delegation-router` (a plan-only agent is useless to something that executes). |

Because the allow-list is generated, a new agent joins `triage-lead`'s team on the
next build. Its prompt still has a hand-written roster table saying *when* to use
each agent - update that when you add one, or the PM will know the agent exists
but not what it is for.

## Writing agent prompts

The prompts are the actual product; the scripts are plumbing. What makes them work:

- **Say what is out of scope.** "Do not report style or naming" is why the code
  reviewer returns three real bugs instead of twelve nits.
- **Set a standard of proof.** Every review agent has to name a concrete failure
  case. Without that, cheaper models pad the list with hypotheticals.
- **Specify output shape.** Unspecified output means prose, and prose from an agent
  is context the caller pays for.
- **For cheap agents, forbid the expensive habit.** `repo-scout` is told not to
  dump file contents, because dumping files defeats the reason it exists.
- **Tell it to admit what it did not check.** "Say which classes you cleared" turns
  a confident summary into an honest one.

## Testing a change

There is no test suite. Verify by hand:

```powershell
.\scripts\build.ps1                  # must report 14 agents, no warnings
.\scripts\build.ps1 -Preset work     # review roles must still be Claude
.\scripts\refresh-models.ps1         # must parse ~29 models, no broken routes
.\scripts\set-availability.ps1 -List # every role must resolve to something
```

Availability filtering is the part most likely to break silently, so exercise the
blocked path rather than trusting the unrestricted default:

```powershell
# Simulate an org that blocks the whole premium tier
.\scripts\set-availability.ps1 -Preset work -Mode allow `
  -Models 'Claude Sonnet 5','Claude Haiku 4.5','GPT-5.6 Luna','Gemini 3.7 Flash'
.\scripts\build.ps1 -Preset work     # must SUBSTITUTE review to Claude Sonnet 5, loudly
.\scripts\set-availability.ps1 -Preset work -Mode all   # reset
```

Two properties matter there: no role silently ends up on a cheap model, and no
unscored model is ever substituted in.

The `refresh-models.ps1` JSON emitter must be idempotent - run it with `-Apply`
three times and `registry/models.json` must stop changing after the first. Escape
drift in `Format-JsonString` is how that breaks.

The workflow's embedded PowerShell is not covered by the script parse check. After
editing `.github/workflows/refresh-models.yml`, extract each `run: |` block and
run it through `[System.Management.Automation.Language.Parser]::ParseInput`, or
trigger the workflow manually with `apply` unchecked.

Then install into a scratch directory rather than your real config:

```powershell
.\scripts\install.ps1 -Scope project -Path $env:TEMP\kit-test -WithInstructions
.\scripts\install.ps1 -Scope project -Path $env:TEMP\kit-test -Uninstall
```

Check the generated frontmatter by eye - `build/claude/agents/*.md` and
`build/copilot/agents/*.agent.md`. Two things have broken before and are worth
looking for: a UTF-8 BOM before the opening `---` (which stops frontmatter being
recognised, hence `Write-Utf8NoBom`), and over-quoted YAML scalars.

## PowerShell constraints

Targets **Windows PowerShell 5.1**, so:

- No `&&` or `||`, no ternary, no `??`, no `?.`
- `ConvertFrom-Json` returns `PSCustomObject`, not a hashtable - no `-AsHashtable`
- `Set-Content -Encoding utf8` writes a BOM. Use `Write-Utf8NoBom`.
- Do not name a parameter `$Profile` - it shadows an automatic variable. Hence
  `-Preset`.
- **Variable names are case-insensitive.** A local `$list` assigns to the
  `[switch]$List` parameter and throws a type-conversion error from the call site,
  which makes it look like a parameter-binding bug. This has bitten twice
  (`$Profile`, `$list`). Prefix locals that shadow a parameter - `$profModels`,
  `$profMode`.
- In a double-quoted string the backtick is the escape character, so three
  literal backticks need six. Use a single-quoted `'```'` instead, especially in
  the workflow's embedded PowerShell.
- In `-replace`, the replacement operand is a literal string where `\` is not
  special. To emit a JSON-escaped backslash the replacement is `'\\'`, not
  `'\\\\'` - the latter produces four and compounds on every rewrite.

## Refresh script fragility

`refresh-models.ps1` parses GitHub's docs markdown. Each vendor publishes its own
table with different columns - only OpenAI has `Cache write`, only some have
`Tier` - so columns are mapped by header name per table. If GitHub restructures
those pages the script throws rather than writing a half-parsed registry. Fix
`Get-PricingRows`; do not fall back to hand-maintaining prices.
