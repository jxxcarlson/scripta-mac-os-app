# In-App Navigation for Doc & Folder Links — Design Spec

**Date:** 2026-06-19
**Status:** Approved (pending spec review)

## Goal

Clicking a relative Markdown link to another document or folder should **render that document
inside the viewer** (navigate), instead of opening it in an external app. Specifically:

- `[notes](black-hole-study-notes.md)`, `[x](sub/foo.scripta)` → open that doc **in-app**.
- `[folder](Bar/_index.md)` and bare-folder `[folder](Bar)` → open that folder's `_index.md` in-app.
- PDFs / images / other assets → continue to **open externally** (unchanged).
- `http(s)`/`mailto` → browser/mail; `#anchor` → native in-page (unchanged).

Relative targets resolve against the **directory of the document currently on screen**, computed
at click time, so the on-disk Markdown stays portable across machines (iCloud mounts at different
absolute paths). A **Back** control returns to the previously-viewed document.

This also adds relative-link **robustness** (decode `%20`/spaces, strip `<…>` wrappers) to both
the new navigation path and the existing open-externally path.

## Context (current state)

- **The "current document" is already tracked** as `model.selectedPath : Maybe String`
  (vault-relative). Opening a doc via the tree (`ClickedTreeNode`, `Main.elm`) sets it and reads
  the file; the renderer uses `model.content`.
- **Relative resolution against the current doc already works for external opens.** Markdown links
  are intercepted in `MarkdownRender.inlineRenderer`; `classifyLink` returns `Web | Anchor |
  LocalFile`; `LocalFile` → `Render.OpenLocalFile target` → `Main` issues `open_path {root, doc =
  selectedPath, target}` → Rust `resolve_link_target(root, doc, target)` resolves
  `parent(root/doc)/target`, canonicalizes, confines to the vault, and `open`s it.
- **There is no in-app navigation**: today a `.md`/`.scripta` link is also classified `LocalFile`
  and opens in the default app, not in the viewer. There is no navigation history.
- `resolve_link_target` does **not** clean the target (no `<…>` strip, no percent-decode), so
  links with spaces/`%20`/angle brackets fail today.
- `Render.RenderMsg` already has variants incl. `OpenUrl`/`OpenLocalFile`; `Main`'s `GotRenderMsg`
  handles `ScrollTo`, `OpenUrl`, `OpenLocalFile`, and a `_ -> (model, Cmd.none)` catch-all.
- The toolbar (`View.elm`) holds the Reader / Parse / Dark buttons. `request`/`handleResponse`/
  `PendingOp` are the FS-bridge plumbing.
- Rust commands live in `fs_commands.rs`, registered in `lib.rs` `generate_handler![…]`.
  `Cargo.toml` has `base64`; **`percent-encoding` is not yet a dependency**.

## Architecture

Add a Rust resolver that turns a clicked relative target into the **vault-relative path of the
doc to open** (handling folders, cleaning, normalization, confinement). Elm classifies a link as
*navigate* vs *external*, and for *navigate* it round-trips through that resolver, then opens the
returned path via the normal read-and-render flow while maintaining a history stack for Back.

### 1. Rust: `clean_target` (shared) + `resolve_doc_link`

`clean_target(target: &str) -> String` (shared helper, also used by `resolve_link_target`):
- trim; if wrapped in `<…>`, strip the brackets; percent-decode (`%20`→space, etc.) via the
  `percent-encoding` crate (add to `Cargo.toml`).

`resolve_doc_link(root: String, doc: String, target: String) -> Result<String, String>`
(`#[tauri::command]`, registered in `lib.rs`):
- `t = clean_target(&target)`.
- `base = parent(root.join(doc))`; `candidate = base.join(t)`.
- `canon = candidate.canonicalize()` (resolves `.`/`..`/symlinks; errors if missing).
- If `canon.is_dir()`, set `canon = canon.join("_index.md")` and re-`canonicalize()`.
- Confine: `canon` must start with `root.canonicalize()` (reject `..`-escapes → `Err`).
- Require `canon` to be a file (exists).
- Return the path **relative to the canonical root**, `/`-joined (vault-relative) — suitable for
  `read_file` and `selectedPath`.

`resolve_link_target` (external opens): apply `clean_target` to its `target` before joining, so
PDF/image links with spaces/`%20`/`<…>` resolve too. (No other behavior change.)

> Implementation note for the plan: check what `elm-markdown` already does with `<…>` targets
> and `%20` before adding stripping/decoding, to avoid double-processing. The cleaning is on the
> Rust side regardless; if the parser already strips/decodes, `clean_target` becomes a no-op for
> those and remains correct.

### 2. Elm: classification (`MarkdownRender`)

Extend `classifyLink` to a richer result and route links accordingly. A relative target is a
**Navigate** target if it ends in `.md` or `.scripta` (case-insensitive), **or has no file
extension** (treated as a folder). Any other relative target (a non-doc extension such as `.pdf`,
`.png`, `.tex`, …) is **External** (today's `LocalFile`). `http(s)/mailto` → Web; `#…` → Anchor.

`inlineRenderer`'s `Link` case emits:
- Navigate → `Render.NavigateToFile url`
- External → `Render.OpenLocalFile url` (existing)
- Web → `Render.OpenUrl url` (existing)
- Anchor → native `<a href>` (existing)

Add a `LinkKind` constructor for the navigate case (e.g. `Navigate`), keeping `Web`/`Anchor`, and
renaming/keeping the external case clearly.

### 3. Elm: messages, model, navigation + history

- `Render.elm`: add `NavigateToFile String` to `RenderMsg`. (Distinct from the existing
  Scripta-slug `NavigateToDocument`.)
- `Types.elm`: add `history : List String` to `Model` (stack of previously-viewed vault-relative
  doc paths); add a `PendingOp` for the resolve round-trip (e.g. `PResolveDocLink`); add
  `ClickedBack` to `Msg`.
- `Main.elm`:
  - **`openDoc : String -> Model -> ( Model, Cmd Msg )`** — the shared "open this vault-relative
    path" helper: push the current `selectedPath` (if `Just`) onto `history`, set `selectedPath`
    and `language` for the new path, and issue `read_image` (if `Language.Image`) or `read_file`
    (else) — i.e. the existing `ClickedTreeNode` logic, now history-aware.
  - **`openDocNoPush : String -> Model -> ( Model, Cmd Msg )`** — same, but does not push history
    (used by Back).
  - `ClickedTreeNode path` → `openDoc path model`.
  - `GotRenderMsg (Render.NavigateToFile target)` → `request PResolveDocLink "resolve_doc_link"
    [ root, doc = selectedPath, target ] model` (no-op if `vaultRoot`/`selectedPath` absent).
  - `handleResponse PResolveDocLink` → decode the result `String` (vault-relative path) →
    `openDoc path model`; decode error → `model.error`.
  - `ClickedBack` → pop `history`: if non-empty, `openDocNoPush prev { model | history = rest }`;
    if empty, no-op.
  - Clear `history` on vault open/change (where `selectedPath` is reset to `Nothing`).
- `View.elm`: add a **Back** button to the toolbar — `button [ onClick ClickedBack, disabled (List.isEmpty model.history) ] [ text "← Back" ]`.

## Data Flow

```
doc/folder link click
  → NavigateToFile target
  → resolve_doc_link (root, selectedPath, target)         [Rust: clean → resolve → folder→_index → confine]
  → vault-relative path
  → openDoc path: push selectedPath→history; selectedPath := path; read_file → render

PDF/image link click
  → OpenLocalFile target → open_path (root, selectedPath, target)   [now clean_target-aware]

Back button
  → ClickedBack → pop history → openDocNoPush prev
```

## Error Handling

- `resolve_doc_link`: missing target, not a file (after folder→`_index.md`), or path escaping the
  vault → `Err(String)` → existing error banner (via `handleResponse` `Err` arm).
- `read_file` failure on the resolved path → existing error banner.
- Back with empty history → no-op (button is disabled in that state anyway).

## Testing

- **Rust** (tempdir tests, mirroring existing `fs_commands` tests):
  - `clean_target`: `"<a b.pdf>"` → `"a b.pdf"`; `"a%20b.pdf"` → `"a b.pdf"`; `"plain.md"` unchanged.
  - `resolve_doc_link`: sibling `foo.md`; `../Other/foo.md`; a **bare folder** → its `_index.md`;
    `Bar/_index.md` explicit; a target with a space / `%20`; a `<…>`-wrapped target; a
    `..`-escape → `Err`; a missing target → `Err`; a folder with no `_index.md` → `Err`.
  - `resolve_link_target`: a `<…>`/`%20` target now resolves (regression-style test).
- **Elm:**
  - `MarkdownRender.classifyLink`: `"a.md"`/`"a.scripta"`/`"Sub"` (no ext) → Navigate;
    `"a.pdf"`/`"a.png"` → External; `"https://e.com"`/`"mailto:x"` → Web; `"#s"` → Anchor.
  - `Test.Html`: `[x](foo.md)` click emits `Render.NavigateToFile "foo.md"`; `[x](a.pdf)` emits
    `Render.OpenLocalFile "a.pdf"`.
  - History logic if extracted to a pure helper (push/pop) — unit test it; otherwise covered by
    compile + manual (since `update` is not exported).
- **Manual:** from `Black_Holes/_index.md`, click `[notes](black-hole-study-notes.md)` → renders
  in-app; inside it click the bekenstein PDF link → opens in Preview; **Back** → returns to
  `_index.md`; click a folder link → its `_index.md` renders; a link with spaces/`%20` resolves.

## Out of Scope (YAGNI)

- Forward button; breadcrumb trail; persisting history across launches.
- Scripta's own internal links (the separate slug-based `NavigateToDocument`).
- Editing semantics changes — a navigated-to doc opens exactly like a tree-opened one (editable,
  same Reader/split behavior).
- Navigating to targets outside the opened vault (the tree is vault-rooted; such links error).
