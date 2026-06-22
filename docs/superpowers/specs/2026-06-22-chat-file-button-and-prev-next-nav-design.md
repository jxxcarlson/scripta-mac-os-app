# Chat "File" button + Prev/Next navigation — Design

Date: 2026-06-22

Two independent features in the Elm + Tauri frontend (`frontend/`):

1. A per-reply **File** button (plus a title text field) on AI chat replies that
   writes the reply to `<Vault>/Inbox/<title>`.
2. Rename the **Back** nav button to **Prev**, add a **Next** button (forward
   navigation), and bind `Cmd+[` / `Cmd+]` as shortcuts.

---

## Part 1 — "File" button on AI chat replies

### Goal

Each assistant reply currently shows a `Copy` button. Add, in the same header
row, a small title text field and a `File` button. Clicking `File` creates a
file in `<Vault>/Inbox` whose name is the typed title and whose contents are the
reply text. The created file then opens and is revealed in the tree (same UX as
the existing "New" button).

Header row layout for an assistant reply:

```
Assistant   [Copy]  [ title… ]  [File]

<reply markdown renders below>
```

### State (`Types.elm` Model)

Add:

```elm
chatFileTitles : Dict Int String
```

Per-reply title drafts keyed by the reply's index in `chatMessages`.
`ChatMessage` has no id; `chatMessages` is append-only, so the list index is a
stable key. Requires `import Dict exposing (Dict)` in Types.elm.

### Messages (`Types.elm`)

```elm
| ChatFileTitleInput Int String   -- user typed in reply n's title field
| ClickedChatFile Int String      -- File clicked for reply n; String = reply content
```

### View (`View.elm`)

- `chatMessageView` currently takes only a `ChatMessage`. Change its signature to
  also receive the index and the current title draft, and change the call site
  to use `List.indexedMap` (passing `model.chatFileTitles` lookups through).
- For assistant replies only, the header row gains, after the `Copy` button:
  - an `input` (`onInput (ChatFileTitleInput n)`, `value` = draft for index `n`),
    placeholder `"title…"`, small styling consistent with the Copy button.
  - a `File` button: `onClick (ClickedChatFile n m.content)`, `disabled` when the
    trimmed title draft is empty.

### Update (`Main.elm`)

- `ChatFileTitleInput n s` → `{ model | chatFileTitles = Dict.insert n s model.chatFileTitles }`, `Cmd.none`.
- `ClickedChatFile n content`:
  1. No `vaultRoot` → no-op (same guard as `ClickedNewFile`).
  2. `title = String.trim (Dict.get n model.chatFileTitles |> Maybe.withDefault "")`; empty → no-op.
  3. `name = if title has no extension then title ++ ".md" else title`.
     ("Has an extension" = the basename contains a `.`.)
  4. Build path `Inbox/<name>` and invoke `create_file` exactly like
     `ClickedNewFile`, but with `content` = the reply text instead of `""`.
     Use `PathUtil.kbaseRoot root` when available (path `Inbox/<name>`, root =
     kroot); otherwise fall back to `PathUtil.siblingPath model.selectedPath name`
     with root = `root` — mirroring `ClickedNewFile`.
  5. Clear that reply's draft: `Dict.remove n model.chatFileTitles`.
  6. Reuse `request (PCreateFile path) …`. The existing `PCreateFile` completion
     handler already opens the new file, expands ancestor folders, and relists
     the tree — satisfying "open the new file" with no new completion code.

### Edge cases

- Blank/whitespace title → File button disabled and update is a no-op.
- No `vaultRoot` → no-op.
- Overwrite of an existing `Inbox/<name>` is handled by `create_file` the same
  way the "New" button already handles it (no new behavior introduced here).

---

## Part 2 — Prev / Next navigation + keyboard shortcuts

### Goal

Rename `← Back` to `← Prev`, add a `Next →` button that is the inverse of Prev,
and add `Cmd+[` (Prev) and `Cmd+]` (Next) keyboard shortcuts.

### State (`Types.elm` Model)

Existing: `history : List String` (back stack).
Add: `future : List String` (forward stack). Initialize to `[]` wherever the
Model is constructed/reset.

### Messages (`Types.elm`)

- Rename `ClickedBack` → `ClickedPrev`.
- Add `ClickedNext`.

### Buttons (`View.elm`)

- The current `← Back` button → label `← Prev`, msg `ClickedPrev`, `disabled`
  when `history` is empty (unchanged guard).
- New `Next →` button next to it, msg `ClickedNext`, `disabled` when `future`
  is empty.

### Navigation logic (`Main.elm`)

Let `current = model.selectedPath`.

- **`ClickedPrev`:** pop `prev :: rest` from `history`; push `current` (if `Just`)
  onto `future`; `openDocNoPush prev { model | history = rest, future = <current> :: future }`.
  Empty `history` → no-op.
- **`ClickedNext`:** pop `next :: rest` from `future`; push `current` (if `Just`)
  onto `history`; `openDocNoPush next { model | future = rest, history = <current> :: history }`.
  Empty `future` → no-op.
- **Opening a new doc** (`openDoc`, used by tree clicks / new file creation):
  clear `future` so Next never resurrects a stale branch — standard browser
  back/forward semantics. `openDoc` already pushes current onto `history`; add
  `future = []` to the model it builds.

### Keyboard shortcuts (`Main.elm` `subscriptions`)

There is currently no global key subscription. Add
`Browser.Events.onKeyDown keyDecoder` where `keyDecoder` reads `metaKey` and
`key`:

- `metaKey == True && key == "["` → `ClickedPrev`
- `metaKey == True && key == "]"` → `ClickedNext`
- otherwise the decoder fails (no message).

Both shortcuts are global (active even when the editor or chat textarea is
focused). `Cmd+[` / `Cmd+]` are not text-input keys, so this does not interfere
with typing. The empty-stack guards in the update handlers make the shortcuts
no-ops when there's nothing to navigate to.

Requires `import Browser.Events` in Main.elm.

---

## Testing

The project has an existing `frontend/tests/` suite (elm-test). Add/extend tests
where the logic is pure and testable:

- Filename derivation for Part 1 (extension-append rule): a small pure helper
  (e.g. in `PathUtil` or a local helper) so it can be unit-tested:
  `"notes" → "notes.md"`, `"notes.scripta" → "notes.scripta"`, `"a.b.md" → "a.b.md"`.
- Prev/Next stack transitions: factor the history/future stack manipulation into
  pure functions if practical, and test the round-trip (open A, open B, Prev →
  A with future=[B], Next → B with history=[A], open C clears future).

View wiring (buttons, inputs, subscriptions) is verified by compilation and
manual run; keep pure logic in testable helpers.
