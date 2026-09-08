---
name: session-handoff
description: Assess context health and manage clean-session continuity. Use when the user mentions a handoff, a fresh or new session, continuing work elsewhere, context bloat/fullness/percentage, compaction, clearing, rewinding or summarizing, or picking up prior work. Also use after repeated corrections or failed approaches when session history may be distracting. Do not use for unrelated technical uses of the word "context". A context concern alone calls for an assessment, not automatically writing a handoff.
license: MIT
---

# Session Handoff

Optimize for reasoning quality rather than maximum session lifespan.

## Core principle

Transfer the minimum sufficient **state**, not the entire old **context**.

The repository, Git state, current files, and verification results are ground truth. Conversation
history and handoff files are briefings that may contain stale assumptions.

## 1. Assess the transition

A context concern is a request for a recommendation, not permission to write a file. Say which of
these applies and why, then act.

### Continue normally

Prefer this when the current task is coherent, relevant history is still helpful, and context
pressure is not materially affecting the work.

Never estimate context pressure. Run `/context` and read the number.

### Rewind / summarize part of the conversation

Prefer `/rewind` when only part of the conversation is noisy or obsolete and preserving either the
earlier or the later portion in full would be useful. Use the summarize options in the rewind menu
rather than summarizing by hand when that matches the situation better.

### Compact

Prefer `/compact` when the same coherent task or implementation phase is continuing and most of the
accumulated reasoning is still useful.

When recommending compaction, hand the user a focused command rather than a bare `/compact`:

`/compact Preserve the current objective and acceptance criteria, important implementation decisions, materially changed files and symbols, unresolved issues, tests or commands already run and their results, and exact next steps. Discard exploratory chatter and superseded approaches unless repeating them would cause meaningful wasted work.`

Compaction is not lossless. Detail that exists only in the conversation can be dropped by the
summarizer without warning.

### Clear

Prefer `/clear` when switching to unrelated work and no task state needs to carry forward.

If the same issue has required more than two corrections, or the same approach has failed twice,
strongly consider clearing and restarting with a better prompt that incorporates what was learned. A
session that has been wrong three times is usually being steered by its own wrong turns.

### Fresh-session handoff

Strongly prefer a fresh-session handoff when:

- the user explicitly wants clean context while preserving task continuity;
- repeated corrections or failed approaches have polluted the conversation;
- important assumptions changed during the session;
- substantial irrelevant exploration has accumulated;
- a major work phase is ending while related work remains;
- the model appears distracted or confused by earlier context.

Do not use a hard context-percentage cutoff. Fullness is a signal, not the criterion. A 70% session
on one coherent task is healthier than a 30% session that has changed its mind three times.

For large exploratory reads or investigations, use subagents so their detailed exploration does not
expand the main session's context.

## 2. Prepare an outgoing handoff

Only create or update a handoff file when the user intends to continue in a fresh session or
explicitly asks for one.

Inspect, as relevant:

- repository root and current branch;
- `git status`;
- staged and unstaged changed-file summaries;
- relevant diffs;
- files and symbols central to the current work;
- available build / test / typecheck / lint results relevant to the work.

Do not blindly summarize the conversation. Reconcile the session's understanding against the actual
repository. Where they conflict, record the repository state and note the discrepancy.

Do not make unrelated code changes in order to prepare a handoff.

## 3. Write the handoff artifact

Write it where the repository already keeps handoffs:

`docs/HANDOFF-<date>-<slug>.md`

Then register it in `.claude/state.conf` at the repository root:

```
HANDOFF=docs/HANDOFF-2026-01-31-payment-retries.md
CHECK=npm test
CHECK_SAFE=yes
```

**That pointer, not the filename or its date, decides which document is current.** If this repo has
the bundled `SessionStart` hook installed, the next session is told the registered handoff before it
types anything, so it never has to be told the file exists, and it is warned when a newer
state-shaped document exists alongside it. Without the hook the pointer still works: it is the one
place a human or a session can look to learn which document is live.

`CHECK_SAFE=yes` is only the repository's half of the permission to run `CHECK` at session start. The
machine must also list this repository's path in `~/.claude/session-state-allow`. Do not tell the user
the check will run at session start unless you have confirmed that line exists.

Keep the handoff concise and self-contained. Reference paths, symbols, commits, and commands instead
of pasting large code blocks or diffs. Never copy secrets, credentials, tokens, or sensitive
environment values into a handoff.

Use this structure:

```
# Handoff

## Objective
What is being built, fixed, or investigated, including the acceptance criteria.

## Completed
What has been implemented, and what exists as a result.
Clearly distinguish implementation from verification.

## Decisions and Rationale
Only decisions the next session needs in order to avoid rediscovery or
architectural regression.

## Relevant / Changed Files
Important paths and symbols, each with a short note on why it matters.

## Remaining Work
Concrete unfinished steps, ordered when sequence matters.

## Known Issues / Open Questions
Failing tests, uncertainty, blockers, suspected problems, unresolved decisions.

## Rejected / Superseded Approaches
Only approaches whose repetition would materially waste time, with a one-line
reason each.

## Verification State
Name the commands already run, the repository's registered CHECK= first.
Name them; do not transcribe the numbers they printed. Never imply that
unrun verification has passed.

## Completion Verification
The commands or observable behaviour that will show the work is done.

## Recommended Next Action
The single best starting action for the fresh session.
```

### The start prompt

The handoff is not delivered until a ready-to-paste start prompt has been printed in the chat, as the
last thing this skill outputs. Write it in second person: re-ground on the registered handoff and the
registered check, verify the handoff's claims against the repository, then take the first unfinished
step.

**Do not restate a standing rule the fresh session already loads by itself.** Before putting any rule
in the prompt, check whether it is reachable from the files that load unprompted: global
instructions, the project `CLAUDE.md` and whatever it imports, and whatever those name in turn. Grep
for it rather than assuming.

- **Already loading: leave it out.** A rule in the prompt as well as in the repo is a second copy
  that drifts, and the prompt copy is the one nobody maintains.
- **Not loading: fix the repo, do not paste it.** A rule that has to be carried by hand is a rule in
  the wrong place. Move it into the file that loads, then leave it out of the prompt.

What survives this check is usually two sentences. The check earns its keep in the other direction
too: it is how you find the rule that is genuinely missing, and the fix for that one is the
repository, not the prompt.

## 3b. Nothing the user decided may live only in the conversation

Run this before declaring the handoff ready. It is a separate pass with its own output, not the
re-read in the next section.

1. **List every decision the user made this session, in their own words.** A number they set, a rule
   they changed, a thing they tabled, a thing they said stays, a yes or no to a proposal. Scan the
   whole conversation, including mid-turn messages and one-word answers.
2. **For each one, name the file that carries it and grep to prove it is there.** The file must be
   one the next session loads or reads on its own: the state file, a decision register, a settings
   file, the project `CLAUDE.md`, a memory file. A rule that lives in a gitignored file, or in a file
   that loads only when something invokes it, counts only if a loading file points at it.
3. **Anything found only in the conversation gets written now, into the file that owns it**, and the
   grep is run again. The handoff is not ready until every decision greps positive.
4. **Put the table in the chat**: decision, file, found or written-just-now.

The user reads that table. They do not read a claim that everything was recorded. A session that
judges its own handoff will pass itself; the grep will not.

After writing the file, re-read it and check it against the current repository and Git state before
declaring the handoff ready.

## 4. Pick up work in a fresh session

When continuing from a handoff:

1. Confirm the current repository or worktree, and the branch.
2. Read the applicable `CLAUDE.md`, rules, and project instructions.
3. Read the handoff named by `.claude/state.conf`.
4. Inspect `git status` and the relevant staged and unstaged diffs.
5. Inspect the files and symbols the handoff references.
6. Verify material handoff claims against the repository before relying on them.
7. Identify contradictions, stale assumptions, or missing information.

Then give a brief re-grounding summary: what is already complete, what remains, any discrepancy or
uncertainty found, and the recommended next action. Unless the user asked only for a review, continue
from the next unfinished step.

## 5. Keep durable knowledge separate

A handoff is temporary workstream state, not permanent documentation.

If a handoff contains a durable architecture rule, a recurring command, or a stable project
convention, promote it to the project documentation, `CLAUDE.md`, a rule file, a test, or an ADR.

Remove or replace stale handoffs so a later session does not mistake obsolete state for current
truth, and point `HANDOFF=` at the replacement in the same change. A handoff nobody retired is the
most expensive kind of stale: it reads as current.
