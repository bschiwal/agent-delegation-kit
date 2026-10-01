# Local session reviews

Everything in this folder except this README is gitignored.

Sessions save their after-action reviews here when you ask for one (the
installed delegation policy gives them this folder's path). On a machine that
can't push - a work clone - this is how lessons get back to the kit:

1. Ask for a review at the end of a session. It lands here as
   `<date>-<project>-<topic>.md`.
2. Every so often, copy the new files to your home machine.
3. At home, read each one before filing it. The reviews are written to keep
   clients, people and internal figures generic, but check: this repo is public.
4. File the cleaned reviews in `docs/feedback/` and ask a session to act on
   them, the same way as the reviews already there.

Changes to agent prompts and rules are made at home, never in a work clone. A
work clone changes only its `*.local.json` files and this folder.
