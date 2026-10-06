# VS Code + GitHub Copilot setup

## 1. Prerequisites

- VS Code, reasonably current. Custom agents use the `.agent.md` format that
  replaced custom chat modes - if your Chat view still says "chat modes" rather
  than "agents", update VS Code.
- The **GitHub Copilot** and **GitHub Copilot Chat** extensions, signed in to an
  account with a Copilot plan.

Confirm the model picker works: open Chat (`Ctrl+Alt+I`), then `Ctrl+Alt+.` to
open the model picker. What you see there is what your plan and your org's policy
actually allow - it is the ground truth, ahead of any table in this repo.

## 2. Install the agents

```powershell
git clone https://github.com/BSchiwal/agent-delegation-kit.git
cd agent-delegation-kit
.\scripts\install.ps1 -Target copilot -WithInstructions
```

This writes to:

- `~\.copilot\agents\` - the 16 agents, available in every workspace
- `~\.copilot\instructions\` - the always-on routing rules (from
  `-WithInstructions`), so ad-hoc chat follows the cost policy too

If PowerShell refuses to run the script:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

## 3. Confirm

Reload the VS Code window (`Ctrl+Shift+P` -> *Developer: Reload Window*), open
Chat, and click the agent dropdown above the input box. The 16 agents should be
listed. `/agents` opens **Configure Custom Agents** if you want to inspect or edit
one.

## 4. Use them

Pick the agent from the dropdown, then **set the model picker yourself**, then
type your request.

**The agent you pick runs on the picker, not its profile.** Tested in VS Code
1.139 (the Copilot harness, 2026-10-06): `triage-lead` was set to GPT-5.6 Terra
and ran on whatever the picker showed, and the picker does not change when you
pick an agent - with a list or a single name in `model:`. **Agents it calls
follow their own profiles**: in the same session `repo-scout` ran on GPT-6 Luna
and `pbir-builder` on GPT-5.6 Terra, while the picker was on Gemini. So the
picker decides one agent's model - the one you talk to - and the profiles decide
the rest, which is most of the work.

In practice: before you start, set the picker to the first model on the picked
agent's `model:` line (open its file in `~\.copilot\agents\`). Avoid **Auto**:
it hands the orchestrator, the longest-running context, to GitHub's choice.
Support for the agent's own `model:` in the harness landed in VS Code Insiders
1.141 ([microsoft/vscode#338489](https://github.com/microsoft/vscode/issues/338489));
re-test when it reaches stable.

To check which models a session really used, read the harness's session log:

```powershell
$s = Get-ChildItem "$env:USERPROFILE\.copilot\session-state" -Directory | Sort-Object LastWriteTime -Descending | Select-Object -First 1
Get-ChildItem $s.FullName -Recurse -File | Select-String -Pattern '"model"\s*:\s*"[^"]+"' -AllMatches |
  ForEach-Object { $_.Matches.Value } | Group-Object | Select-Object Count, Name
```

It counts each model name in the newest session. Read only those names - the
files are a full record of the session.

Each agent declares its model as a **prioritised list**:

```yaml
model: ['Claude Opus 5', 'Claude Opus 4.8', 'Claude Opus 4.7', 'GPT-6 Astra']
```

When an agent is called by another, VS Code tries them in order and uses the
first one available. This matters in a
managed org: if your admin has disabled a model, the agent falls through to the
next instead of failing. It also means the fallback order encodes intent - for
review agents it is Claude first, all the way down, with GPT-6 Astra only as a
last-resort backstop.

## Power BI model agents

`model-builder` changes a live Power BI model, and `data-model-reviewer` runs
read-only DAX to check its own assumptions. Both need the **Power BI modeling MCP
server** installed in VS Code. `pbir-builder` uses the **powerbi-report-authoring**
skill, and says so in its reply if it can't load it.

**1. Tell the kit your server's name.** VS Code references MCP tools as
`<server>/<tool>`, where `<server>` is whatever name the server is registered
under on your machine. To find it, open Chat, click the tools icon (**Configure
Tools**), and look at the heading the Power BI modeling tools are grouped under.
Or check the key in your `mcp.json`. If it isn't `powerbi-modeling-mcp`, edit
`copilot_server` in [`registry/mcp.json`](../registry/mcp.json) and reinstall:

```powershell
.\scripts\install.ps1 -Target copilot -Preset work
```

VS Code **ignores tools it can't find without warning**, so a wrong name doesn't
error. The agent just runs without its tools, and `model-builder` says so up
front.

**2. Test it** with a Power BI model open in Desktop. Pick `model-builder` in the
agent dropdown and send:

```
Read-only check: connect to the model I have open in Desktop, then report the
connection name and the number of measures. Don't change anything.
```

A connection name and a measure count mean it works.

**How connections work here.** In Claude Code a subagent was confirmed to reuse
the main session's connection. In Copilot you often pick `model-builder` directly
from the dropdown, so it may have no caller to inherit a connection from. The
Copilot build of `model-builder` therefore connects by itself, but only when
exactly one open Desktop model matches what you named, and asks you otherwise.
Whether a connection opened in one Copilot chat carries into an agent that
`triage-lead` calls hasn't been tested yet.

**The reviewer's DAX tool is granted singly** (`<server>/dax_query_operations`),
so it can only query, not change the model. VS Code documents the whole-server
form (`<server>/*`), and the single-tool form comes from GitHub's custom agent
reference. If VS Code doesn't resolve the single tool, the reviewer runs without
it and hands its data questions back as "needs live check" queries. Nothing
breaks.

## Project-scoped install

To commit the agents into a repo so the whole team gets them:

```powershell
.\scripts\install.ps1 -Target copilot -Scope project -Path C:\repos\my-app
```

That writes to `<repo>\.github\agents\` and `<repo>\.github\instructions\`, both of
which are meant to be committed.

## Your organization's model policy (local files)

An employer's model policy and usage figures don't belong in a public repo, so
they live in two git-ignored files:

| File | Holds | Created by |
|---|---|---|
| `registry/policy.local.json` | Which models each role uses, plus the cost figures and rules shown in the Copilot instructions | copying `registry/policy.local.example.json` |
| `registry/availability.local.json` | Which models your picker actually offers | `.\scripts\set-availability.ps1 -Local ...` |

When either file has a profile for the preset you build, the build applies it,
reports `Local overrides applied`, and writes to **`build/local/`**, which is also
git-ignored. That way a work build can never end up in a commit. `install.ps1`
picks up the local build automatically.

### A clone on the work machine

Keep these files on the machine that uses them. Clone the repo on the work
machine (no fork needed - it only ever pulls), and create the two files there.
Set `"config_only_clone": true` in that clone's `policy.local.json`.

That marks the clone as **config-only**: it changes its `*.local.json` files and
`docs/feedback/local/`, and nothing else. Everything else - agent prompts, the
model catalogue, the rules - arrives with `git pull`. If a committed file has
changed there, the build stops and names it, because the next pull would
overwrite it or refuse to run.

Each update cycle - new models, retired models, a changed policy:

```powershell
git pull                                                     # latest kit and catalogue
.\scripts\set-availability.ps1 -Local -Preset work -Mode allow -Models '...', '...'
# edit role_overrides in registry\policy.local.json if a role's first choice changed
.\scripts\build.ps1 -Preset work                             # read any SUBSTITUTED / fallback lines
.\scripts\install.ps1 -Preset work -WithInstructions
```

Or give a Claude session in the clone the update list and let it do the same:
`AGENTS.md` tells it to touch only the local files there.

New models reach the catalogue through the weekly refresh workflow on the public
repo, so a model your org adds is in `registry/models.json` after a pull. If one
isn't yet, wait for the refresh rather than editing `models.json` in the clone.

**Lessons go home as notes.** Session reviews written on the work machine land in
`docs/feedback/local/` (gitignored). Copy that folder home now and then; see its
README.

## Working within an org model policy

If your workplace asks that Anthropic models be reserved for work that needs
them, build with the work preset:

```powershell
.\scripts\install.ps1 -Target copilot -Preset work -WithInstructions
```

That keeps Claude on the review and reasoning roles - which is precisely the work
that needs it - and moves `implement` and `write-prose` onto Gemini and GPT models.

Two things worth raising with whoever set that policy:

1. **Claude Sonnet 5 is $2/$10 per 1M tokens - cheaper than GPT-5.4 ($2.50/$15),
   GPT-5.5 ($5/$30) and GPT-5.6 Sol ($4/$20).** A rule phrased as "avoid Sonnet to
   save money" was written against Sonnet 4 at $3/$15 and now increases spend
   against most of the GPT line.
2. **Claude Opus 5 is $5/$25 - cheaper than GPT-5.5 and less than half GPT-6
   Astra.** For work that genuinely needs a frontier model, Opus 5 is the
   economical frontier choice.

The numbers are in [MODELS.md](MODELS.md), regenerated from GitHub's own pricing
docs, if you need to show your work.

To edit the policy rather than argue it, change
`workplace_overrides.profiles.work` in `registry/policy.json` and rebuild.

## Tool sets

Agents restrict themselves with the `tools` field, using VS Code's tool set names:

| Tool set | Grants |
|---|---|
| `read` | Read files |
| `search` | Search the workspace |
| `edit` | Modify files |
| `execute` | Run commands in the terminal |
| `web` | Fetch web content |
| `agent` | Delegate to other agents |

Review agents get `read`, `search`, `execute` - enough to read code and run
`git diff`, not enough to change anything. If a tool name is ever rejected,
`/agents` shows the valid set for your VS Code build.

## Troubleshooting

**Agents do not appear in the dropdown.** Reload the window. Then check the files
are there:

```powershell
Get-ChildItem ~\.copilot\agents
```

**The agent you picked runs on the wrong model.** It runs on the picker - see
"Use them" above. Set the picker to the model you want.

**An agent called by another runs on the wrong model.** The first model in its list is not available
to your account, so it fell through. Open the model picker to see what you
actually have, then reorder the role in `registry/policy.json` and rebuild.

**A model in the picker is not in this repo's tables.** GitHub added it since the
last refresh. Run `.\scripts\refresh-models.ps1` to see what changed, then
`-Apply` and `build.ps1`.

**The routing instructions seem to be ignored.** Personal instructions outrank
repository ones, so a conflicting rule in your own `~\.copilot\instructions`
wins. Check for duplicates.

**Duplicate agents.** VS Code reads both `~\.copilot\agents` and
`~\.claude\agents`, so installing with `-Target both` at project scope can show
each agent twice. Install Copilot-only at project scope if that bothers you.
