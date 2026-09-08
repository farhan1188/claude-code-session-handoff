# session-handoff

**Your Claude Code session gets worse long before it runs out of room. This decides what to do about it, and writes a handoff the next session finds by itself.**

[![skills.sh](https://skills.sh/b/farhan1188/claude-code-session-handoff)](https://skills.sh/farhan1188/claude-code-session-handoff)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

```
npx skills add farhan1188/claude-code-session-handoff
```

Two parts: an [Agent Skill](https://agentskills.io), which is one `SKILL.md` Claude loads when the
work matches, and one optional `SessionStart` hook, a 150-line bash script. The skill is
instructions; the hook is the only part that runs deterministically.

## The part that is not "write a HANDOFF.md"

Handoff advice is everywhere and it mostly fails for one boring reason: **the next session does not
know the handoff exists.** You write `HANDOFF.md`, open a fresh session, and it starts by reading the
wrong files, because nothing told it otherwise.

So the handoff gets registered in one line at `.claude/state.conf`:

```
HANDOFF=docs/HANDOFF-2026-01-31-payment-retries.md
CHECK=npm test
CHECK_SAFE=yes
```

**That pointer, not the filename or its date, decides which document is current.** The bundled
`SessionStart` hook reads it and prints the state before the fresh session has read anything:

```
== PROJECT STATE: acme-billing ==
(machine-derived at session start; prefer these over any number written in a document)
git      : main | last 24f8107 2026-01-31 add retry scheduler | 3 uncommitted
handoff  : docs/HANDOFF-2026-01-31-payment-retries.md (2026-01-31 18:04)
check    : `npm test`
           14 passing, 1 failing
```

You paste your prompt into a session that already knows where it is. And when the pointer is lying,
you are told:

```
handoff  : docs/HANDOFF-2026-01-31-payment-retries.md
           MISMATCH - 'docs/STATUS.md' is newer. One of them is lying; check before trusting either.
```

A stale handoff is the most expensive kind of stale, because it reads as current.

The second uncommon rule: **before the skill calls a handoff ready, it lists every decision you made
this session, names the file that carries each one, and greps to prove it is there.** Anything found
only in the chat gets written into the file that owns it, then greps again. You get a table:
decision, file, found or written-just-now.

That rule exists because of a specific failure. A session announced its handoff was complete. One
question, *is everything actually written down?*, found three decisions living only in the
conversation, including a rule the project's own config still contradicted. A session that judges
its own handoff will pass itself. A grep will not.

## The problem underneath

The session has been going an hour. It is at 40% context. The answers are getting worse: circling,
re-litigating a decision you already made, confidently repeating an approach that failed at message
30.

The context percentage gets the blame because it is the number on screen. It is usually not the
cause. What degrades a session is **accumulated wrong turns**: abandoned approaches still sitting in
the transcript, an assumption that changed at message 40 while message 10 still asserts the old one,
a file read before you refactored it. The model reasons over all of it and cannot tell which parts
you have discarded.

Five options, real trade-offs, no obvious default:

| Option | What it costs you |
| --- | --- |
| Keep going | Quality keeps sliding, and you will not notice the moment it gets expensive |
| `/rewind` | Throws away the good part with the bad if you cut in the wrong place |
| `/compact` | Not lossless. A summarizer decides what to drop, and conversation-only detail goes silently |
| `/clear` | Total amnesia. Everything you established this session is gone |
| Fresh session + handoff | Only as good as the handoff, and handoffs are usually written badly |

Most people pick by reflex: ride it until auto-compact fires, or clear and re-explain everything.

## What the skill does

**It assesses before it acts.** Ask about context, or say you want a fresh session, and it picks
among continue / rewind / compact / clear / handoff and says why. It reads the real number from
`/context` instead of estimating. It has no percentage cutoff on purpose: a 70% session on one
coherent task is healthier than a 30% session that has changed its mind three times. A context
question gets an assessment, not an automatic file.

When compaction is right, it hands you a targeted `/compact` command, naming what to preserve and
what to discard, rather than the bare one that lets the summarizer choose for you.

**When a handoff is right, it writes one that survives the transfer.** Not a summary of the
conversation. The conversation is a briefing that may be out of date; the repository is ground truth.
The skill reconciles the two against `git status`, real diffs, the files and symbols actually
touched, and what was verified versus only implemented. Where they disagree, the repository wins and
the disagreement is recorded.

## Install

**With the [skills](https://skills.sh) CLI.** Installs the skill only, not the hook:

```
npx skills add farhan1188/claude-code-session-handoff
```

**As a Claude Code plugin.** Gets you the skill *and* the session-start hook:

```
/plugin marketplace add farhan1188/claude-code-session-handoff
/plugin install session-handoff@session-handoff
```

**By hand:**

```bash
git clone https://github.com/farhan1188/claude-code-session-handoff
cp -r claude-code-session-handoff/skills/session-handoff ~/.claude/skills/
```

To wire the hook by hand, copy `scripts/session-state.sh` somewhere permanent and register it in
`~/.claude/settings.json`:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup|resume|compact",
        "hooks": [{ "type": "command", "command": "bash ~/.claude/tools/session-state.sh" }]
      }
    ]
  }
}
```

## Using it

Type `/session-handoff`, or just say what is happening: *"context is getting full"*, *"let's carry
this to a fresh session"*, *"we've gone in circles, start clean"*.

Opt a repository in by creating `.claude/state.conf` (copy `examples/state.conf`). **The hook prints
nothing in repositories that have not opted in**, so installing it does not add noise to unrelated
projects. To see what it would print here, and why it is silent if it is:

```bash
bash scripts/session-state.sh --selftest
```

`examples/HANDOFF-2026-01-31-payment-retries.md` is a filled-in handoff in the shape the skill writes.

## Running your check at session start, safely

`CHECK` is a command that lives in a file inside a repository, so a repository must never be able to
cause its own execution. Two independent switches are required, and one is outside the repo:

1. the repo's `.claude/state.conf` sets `CHECK_SAFE=yes`, and
2. the repo's path is listed in `~/.claude/session-state-allow` on your machine.

Cloning a hostile repo therefore does nothing: without step 2 the hook only prints the command it
would have run, and the line you would paste to allow it. This is the `direnv` model: the repo
proposes, only your machine allows. `export SESSION_STATE_NO_CHECK=1` disables it everywhere.

## How the handoff is shaped, and why

Ten sections, each preventing one specific way a fresh session wastes your time:

| Section | The waste it prevents |
| --- | --- |
| Objective | Optimizing for something adjacent to what you want |
| Completed | Re-doing work that exists, and trusting work nobody checked, since it separates implementation from verification |
| Decisions and Rationale | Re-deriving a decision, or quietly reversing an architectural one |
| Relevant / Changed Files | A blind survey of the repo before it can start |
| Remaining Work | Guessing the order of what is left |
| Known Issues / Open Questions | Rediscovering a blocker you already found |
| Rejected / Superseded Approaches | Walking back into the dead end you left an hour ago |
| Verification State | Believing tests passed when nobody ran them |
| Completion Verification | Not knowing when it is allowed to stop |
| Recommended Next Action | Spending its first five minutes deciding where to start |

Two constraints run through all of it. **Reference, do not paste**: paths, symbols, commits and
commands, never large blocks of code, because pasted code is a second copy that starts drifting
immediately. And **name commands, do not transcribe their numbers**: "the registered check was last
run after the webhook change" ages honestly, where "14 passing, 1 failing" will be wrong tomorrow and
still read as current.

The last thing the skill outputs is a ready-to-paste start prompt, deliberately short. Before putting
any standing rule in it, the skill greps to see whether the fresh session already loads that rule
from `CLAUDE.md` or a rule file. If it does, the prompt leaves it out, because a rule in both places is a
second copy, and the prompt copy is the one nobody maintains. If it does not, the fix is to move the
rule where it loads, not to paste it. What survives is usually two sentences.

## What it will not do

- **The skill is instructions, not enforcement.** Claude loads it and follows it; it can also skip a
  step. The hook is the deterministic half. Judge the two accordingly.
- It will not stop you filling a context window. It tells you what to do when you have.
- It will not make `/compact` lossless. Nothing can. Its answer is to tell you when a handoff beats a
  compaction.
- It will not write a handoff just because context is high. A context question gets an assessment.
- The hook is `bash`. On Windows that means Git Bash, which Claude Code already uses.

## Requirements

Claude Code for the plugin, the hook, and the `/context`, `/compact`, `/rewind` and `/clear` commands
the skill reasons about. The `SKILL.md` itself uses only [Agent Skills](https://agentskills.io) spec
fields, so it is portable to other tools that read the standard, minus those commands.

## License

MIT. See [LICENSE](LICENSE).
