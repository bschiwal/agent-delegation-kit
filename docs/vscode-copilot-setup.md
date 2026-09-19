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

- `~\.copilot\agents\` - the 14 Copilot agents (model-builder is Claude Code only), available in every workspace
- `~\.copilot\instructions\` - the always-on routing rules (from
  `-WithInstructions`), so ad-hoc chat follows the cost policy too

If PowerShell refuses to run the script:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

## 3. Confirm

Reload the VS Code window (`Ctrl+Shift+P` -> *Developer: Reload Window*), open
Chat, and click the agent dropdown above the input box. The 14 agents should be
listed. `/agents` opens **Configure Custom Agents** if you want to inspect or edit
one.

## 4. Use them

Pick the agent from the dropdown, then type your request. The agent's model is
already set - you do not need to touch the model picker.

Each agent declares its model as a **prioritised list**:

```yaml
model: ['Claude Opus 5', 'Claude Opus 4.8', 'Claude Opus 4.7', 'GPT-6 Astra']
```

VS Code tries them in order and uses the first one available. This matters in a
managed org: if your admin has disabled a model, the agent falls through to the
next instead of failing. It also means the fallback order encodes intent - for
review agents it is Claude first, all the way down, with GPT-6 Astra only as a
last-resort backstop.

## Project-scoped install

To commit the agents into a repo so the whole team gets them:

```powershell
.\scripts\install.ps1 -Target copilot -Scope project -Path C:\repos\my-app
```

That writes to `<repo>\.github\agents\` and `<repo>\.github\instructions\`, both of
which are meant to be committed.

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

**An agent runs on the wrong model.** The first model in its list is not available
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
