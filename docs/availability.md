# Availability: what you can actually pick

The pricing tables describe GitHub's whole catalogue. Your model picker usually
shows a fraction of it. Plan tier, org policy and preview gating all remove
models, and the ones removed first tend to be the expensive top-end ones this
kit would otherwise prefer.

That matters more than it sounds. A review agent declaring:

```yaml
model: ['Claude Opus 5', 'Claude Opus 4.8', 'Claude Opus 4.7', 'GPT-6 Astra']
```

on an account where all four are blocked does not fail loudly. It falls through
the whole list and the host substitutes something - quite possibly the cheapest
model available, which is the opposite of what a reviewer should run on. You get a
review that looks like a review and isn't.

So the kit tracks availability explicitly.

## Recording what you have

Open VS Code, press `Ctrl+Alt+.` to show the model picker, and write down exactly
what it lists. That picker is the ground truth: it already reflects your plan and
your admin's policy. There is no API that reports this reliably, which is why this
step is manual.

Then record it:

```powershell
.\scripts\set-availability.ps1 -Preset work -Mode allow `
  -Models 'Claude Sonnet 5','Claude Haiku 4.5','GPT-5.3-Codex','GPT-5.6 Luna','Gemini 3.7 Flash'
```

For a long list, paste one name per line into a file instead - leading bullets and
blank lines are ignored:

```powershell
.\scripts\set-availability.ps1 -Preset work -Mode allow -FromFile .\picker.txt
```

Then rebuild:

```powershell
.\scripts\build.ps1 -Preset work
```

Names are matched case- and punctuation-insensitively against
`registry/models.json`, and anything that doesn't match is reported rather than
silently dropped - a typo that blanked out a role would be worse than no
filtering at all.

## Modes

| Mode | Meaning |
|---|---|
| `all` | No restriction. The whole catalogue is assumed reachable. The default. |
| `allow` | Only the listed models exist for this profile. Usual case for a managed org. |
| `deny` | Everything except the listed models. Use when only a few are blocked. |

Availability is per preset, so `work` and `personal` are tracked separately - the
usual situation, where your own account is unrestricted and your employer's is not.

## What the build does with it

```powershell
.\scripts\set-availability.ps1 -List
```

shows each profile, how many models are reachable, and what every role resolves to.
Then on build, three things happen:

**Blocked models are stripped** from every agent's `model:` list. A blocked entry is
dead weight at best, and at worst hides that the role never gets its first choice.

**A degraded role is reported.** If the first choice is blocked but a later fallback
survives, the build says so:

```
First choice blocked - these roles fall back:
  role 'review': blocked Claude Opus 5 -> now uses Claude Opus 4.8
```

**An impossible role is substituted, loudly.** If the entire chain is blocked, the
build picks a stand-in based on the role's `cost_posture` rather than emitting a
list that resolves to nothing:

| Posture | Substitution rule |
|---|---|
| `quality-first` | Highest `merit` reachable, cheapest on a tie |
| `balanced` | Best merit-per-dollar reachable |
| `cheapest-viable` | Lowest blended cost with `merit >= 2.5` |

```
SUBSTITUTED - every preferred model for these roles is blocked:
  role 'review' (quality-first)
    wanted: Claude Opus 5, Claude Opus 4.8, Claude Opus 4.7, GPT-6 Astra
    using:  Claude Sonnet 5 (merit 4)
```

Substitution is a safety net, not a fix. When you see it, add a model you can
actually reach to that role in `registry/policy.json` so the intent is explicit in
the file rather than inferred at build time.

Unscored models (`merit: null`) are never chosen by substitution, so a model that
arrived in an automated refresh cannot quietly become your code reviewer.

## If the top models are blocked for you

This is the common case on a managed Copilot plan, and it genuinely changes the
cost picture - the blended-cost table in [routing.md](routing.md) is describing
models you may not be able to reach.

What to do about it, in order of preference:

1. **Check whether it's policy or plan.** If your admin disabled Opus rather than
   your plan excluding it, that's a conversation, not a constraint. The numbers in
   [MODELS.md](MODELS.md) come from GitHub's own docs and are worth showing:
   Opus 5 at $5/$25 is cheaper than GPT-5.5 at $5/$30, so blocking Anthropic
   models does not automatically reduce spend.

2. **Reorder the review roles to the best Claude model you do have.** If Sonnet 5
   is available, that is your reviewer - merit 4.0, and cheaper than GPT-5.4.
   Make it explicit in `policy.json` instead of leaving it to substitution:

   ```json
   "review": {
     "copilot": ["Claude Sonnet 5", "GPT-5.3-Codex"]
   }
   ```

3. **Use Claude Code for reviews instead.** Claude Code bills through your Claude
   subscription, not Copilot, so an org restriction on Copilot models does not
   apply to it. If your best reviewer is blocked in Copilot but available in Claude
   Code, that is the obvious split: implement in Copilot, review in Claude Code.
   The agents are the same on both sides, which is the point of the kit.

4. **Widen the cheap tier instead of the premium one.** If you cannot spend on
   review, spend less elsewhere so the budget exists: `log-triager` and
   `repo-scout` cut context before it reaches an expensive model, and that saves
   more than any model substitution.

## Keeping it current

Availability drifts as your admin changes policy and as models are added and
retired. `set-availability.ps1` records the date, and the build notes when a
profile has never been recorded. Re-check when:

- The build reports a substitution you didn't expect.
- An agent visibly runs on the wrong model.
- The refresh workflow opens a PR adding models - a new model in the docs is not
  necessarily one your org lets you pick.
