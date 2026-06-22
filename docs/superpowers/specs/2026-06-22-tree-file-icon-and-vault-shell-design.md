# File-tree file icon + `<Vault>` agent shell — Design

Date: 2026-06-22

Two independent features in the Elm + Tauri app (`frontend/`, `src-tauri/`):

1. Replace the `-` prefix on file-tree file names with a small solid dark-blue
   file icon.
2. Rename the Shell 1 terminal tab to the vault folder name and, when that shell
   opens, automatically `cd` into the vault and launch a configurable CLI agent.

---

## Feature 1 — File icon in the tree

### Current state
- `nodeView` (`frontend/src/View.elm:395`) renders a `FileNode` as a flex row:
  `span [...] [ text "-" ]` (the prefix, `:416`) followed by `span [...] [ text r.name ]`.
- Folders use an SVG `folderIcon` (`:313`). Nesting is via nested `<ul>` with
  `padding-left:12px`. The row uses `display:flex; align-items:flex-start`.

### Design
- Add a `fileIcon : Html msg` helper next to `folderIcon`: a ~13px SVG of a
  **solid (filled) file glyph** — a rounded-ish rectangle with a folded
  top-right corner — `fill` = dark blue `#3b6ea5`, sized/styled to match
  `folderIcon` (`width "13" height "13" viewBox "0 0 16 16"`, with
  `vertical-align: middle; margin-right: 5px;`).
- In the `FileNode` branch, replace `span [ ... ] [ text "-" ]` with
  `span [ ... ] [ fileIcon ]`. Keep the existing wrapping `span` attributes
  (`flex "0 0 auto"`, `margin-right "5px"`).
- **Position unchanged:** the icon stays at the normal nested (child) indent,
  slightly left of the enclosing folder's name. No alignment-to-folder-name
  change.
- **Hanging indent:** already provided by the flex layout — the name lives in a
  `span [ style "flex" "1 1 auto" ]` flex item, so wrapped lines align under the
  title's first character, not under the icon. No change required.

### Testing
- A `View` test asserting a `FileNode` row no longer contains the literal `-`
  text and contains an `svg` element. (Folder rows already contain an svg, so
  scope the assertion to a file node.)

---

## Feature 2 — `<Vault>` shell that launches the agent

### Decisions captured
- The agent command is an **explicit, overridable setting**, pre-populated from a
  provider→CLI mapping based on the active provider.
- Only **Shell 1** is renamed and auto-runs the agent; Shell 2 stays a plain
  shell; Scratch is unchanged.
- On open, Shell 1 runs `cd '<vault>' && <agent>`.
- The in-app **Reload** keeps Shell 1's state (its pty persists; the agent is
  **not** relaunched). The agent launches only when the pty first opens.

### A. Agent setting (`frontend/src/AiConfig.elm`)
- Add field `agentCommand : String` to the `AiConfig` record (empty string means
  "use the provider default").
- `agentDefault : String -> String` — provider→CLI map:
  `"anthropic" -> "claude"`, `"openai" -> "codex"`, `"gemini" -> "gemini"`,
  `_ -> "claude"` (fallback).
- `effectiveAgentCommand : AiConfig -> String` —
  `if String.trim cfg.agentCommand == "" then agentDefault cfg.activeProvider
  else String.trim cfg.agentCommand`.
- `setAgentCommand : String -> AiConfig -> AiConfig`.
- `init` sets `agentCommand = ""`.
- `encode` adds `( "agentCommand", E.string cfg.agentCommand )`.
- `decoder` reads it backward-compatibly:
  `D.oneOf [ D.field "agentCommand" D.string, D.succeed "" ]`.
  (Update the decoder from `map3` to `map4`, preserving the existing fields.)
- Export the new functions from the module.

### B. Settings UI + update (`frontend/src/View.elm`, `frontend/src/Main.elm`, `frontend/src/Types.elm`)
- New `Msg`: `SetAgentCommand String` (`Types.elm`).
- In `settingsOverlay` (`View.elm:516`), add an "Agent command" labeled text
  `input`: `value` = `AiConfig.effectiveAgentCommand model.aiConfig`,
  `onInput SetAgentCommand`, with `autocapitalize/autocorrect/spellcheck`
  disabled (mirroring the `new-file-name` input). Place it near the
  provider/model controls.
  - Binding `value` to the effective command means the field always shows a
    concrete agent: it pre-fills with the active provider's default (e.g.
    `claude`) when no override is stored, and if the user clears the field it
    snaps back to that default. This is intended — there is always an agent to
    launch. Switching the active provider updates the shown default when no
    override is set.
- In `update` (`Main.elm`), handle `SetAgentCommand s`:
  `let cfg = AiConfig.setAgentCommand s model.aiConfig in
  ( { model | aiConfig = cfg }, FileOps.saveAiConfig (AiConfig.encode cfg) )`
  — same persistence pattern as `SetActiveProvider`/`SetProviderModel`
  (`Main.elm:560-569`).

### C. Shell 1 tab label (`frontend/src/View.elm`)
- `rightTabs` (`:615`) is a static `[ ("shell1","Shell 1"), ("shell2","Shell 2"),
  ("scratch","Scratch") ]`, consumed by `terminalTabBar` (`:620`) →
  `terminalTabButton` (`:632`).
- Compute Shell 1's label dynamically from the vault: a helper
  `shellTabLabel : Model -> String -> String -> String` (args: model, tabId,
  default) returning, for `tabId == "shell1"`,
  `model.vaultRoot |> Maybe.map PathUtil.basename |> Maybe.withDefault "Shell 1"`,
  and the static default otherwise.
- `terminalTabBar` maps over `rightTabs` and passes the computed label into
  `terminalTabButton`. (Adjust `terminalTabButton` to take the resolved label
  rather than reading it from the tuple, or compute inside it from `model`.)

### D. Auto-run the agent on Shell 1 open

**Rust (`src-tauri/src/terminal.rs`):**
- `terminal_open` gains a parameter `init_cmd: String`.
- After the session is created and stored (writer available), if
  `!init_cmd.is_empty()`, write `init_cmd + "\n"` to the pty writer (then flush).
  Writing after spawn is safe — the tty buffers it until the shell reads it.
  Use the stored writer (or write before inserting into the map; either way write
  exactly once).

**JS (`frontend/index.html`, `terminal-pane` element):**
- In `_openOrResize`, on the open branch, read
  `this.getAttribute('init-cmd') || ''` and pass it as `initCmd` in the
  `invoke('terminal_open', { id, cwd, cols, rows, initCmd })` call.
- `init_cmd` is consumed only on open (not on resize), so it runs exactly once
  per pty.

**Elm (`frontend/src/View.elm` `terminalPane`):**
- `terminalPane` (`:806`) currently sets `term-id` and `cwd`. For `termId ==
  "shell1"` and a present vault, also set attribute `init-cmd` =
  `"cd '" ++ vault ++ "' && " ++ AiConfig.effectiveAgentCommand model.aiConfig`.
  For other tabs, or no vault, omit `init-cmd` (or set `""`).
  - The vault path is wrapped in single quotes because the iCloud vault path
    contains spaces. (Single-quoting is sufficient here; a path containing a
    literal single quote is not handled and is out of scope.)
  - `terminalPane` needs access to `model.aiConfig` and `model.vaultRoot` (it
    already takes `model`).

### Testing
- Pure-function unit tests (`frontend/tests/`):
  - `AiConfig.agentDefault` for each provider + fallback.
  - `AiConfig.effectiveAgentCommand`: empty `agentCommand` → provider default;
    non-empty → trimmed override; whitespace-only → provider default.
  - `AiConfig` encode/decode round-trip includes `agentCommand`; decoding JSON
    without the field yields `""`.
- The tab-label basename logic is covered by existing `PathUtil.basename` tests;
  add a focused test if the `shellTabLabel` helper is pure and exported.
- The Rust `init_cmd` write and the JS attribute wiring are verified manually
  (open the terminal → Shell 1 tab shows the vault name and runs
  `cd '<vault>' && <agent>`).

### Out of scope
- Relaunching the agent on in-app Reload (explicitly: Reload keeps Shell 1
  state).
- Per-provider distinct agent overrides (single overridable command; its default
  tracks the active provider).
- Shell-quoting paths that contain single quotes.
