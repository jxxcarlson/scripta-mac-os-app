# AI Agent ("administer kbase") — Decision: use Claude Code, don't build one

**Date:** 2026-06-20
**Status:** Decided — no implementation.

## Decision

Sub-project #4 of the AI-terminal effort ("the AI administers kbase" — an in-app agent with
tool/shell access to the vault) is **not being built.** Agentic kbase work is done by running
**Claude Code** (`claude`) in one of the app's **shell tabs** (the terminal panel, sub-project #2).

## Rationale

The user already administers kbase with Claude Code and is satisfied with its operation and safety.
That setup is:

- **Skills** in `<kbase>/.claude/skills/`: `kbase-file` (triage `Inbox/`, confirm-as-batch, move,
  then sync) and `kbase-sync` (reconcile `_index.md` files against disk).
- **superpowers** — a global Claude Code plugin (`~/.claude/plugins/…/superpowers/`), not in the vault.
- **Safety = Claude Code's permission model** (approve-before-acting on edits/commands), wrapping
  those skills. The skills are capabilities; Claude Code is the gatekeeper.

A from-scratch Anthropic tool-loop agent would introduce a **new, unproven safety model** and would
**not** reuse the user's skills/superpowers — the opposite of "use what I already trust." Since the
terminal panel already gives a real shell rooted at the vault, the agent the user wants is one
command away (`claude`), with zero new code or new attack surface.

## How it works in the app

- Terminal panel (#2) spawns `$SHELL` with cwd = the opened vault root. If the vault is kbase, a
  Shell tab starts in kbase → run `claude` to get the trusted agent (skills + superpowers + prompts).
- **Tab 1** (the in-app direct-Anthropic chat, #3) is for **general, stateless Q&A only** — no tools,
  no vault access by design. Quick questions/explanations/drafting; the agentic work is the shell's.

## Status of the AI-terminal effort

- #1 Secure key storage + provider config — done.
- #2 Terminal panel + working shells — done (also delivers the agent path).
- #3 AI chat in Tab 1 (Anthropic, non-streaming) — done (general Q&A).
- #4 In-app agent — **dropped** in favor of running Claude Code in a shell.
