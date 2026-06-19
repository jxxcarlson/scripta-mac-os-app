# Markdown File Links — Open Externally Design Spec

**Date:** 2026-06-19
**Status:** Approved (pending spec review)

## Goal

Make links in rendered markdown actionable. Clicking a link in a `.md` document:

- **Local file link** (relative target, e.g. `[III_The_Rose.pdf](III_The_Rose.pdf)`) — resolves
  the target relative to the directory of the document being viewed and opens it with the macOS
  default app for that file type (PDFs → Preview, etc.).
- **Web link** (`http://`, `https://`, `mailto:`) — opens in the default browser / mail client.
- **In-page anchor** (`#heading`) — left as a native anchor (unchanged).

This turns the app into a usable knowledge-base viewer where `_index.md` files link to sibling
assets. No Swift rewrite is needed; it fits the existing Tauri 2 + Elm structure.

## Context

- Markdown links currently render through `Markdown.Block.defaultHtml` as inert
  `<a href="…">` (`elm-markdown/Markdown/Inline.elm:129`). In the Tauri webview a relative or
  web href would try to navigate the whole app — broken. So no markdown link is usable today.
- `Markdown.Block.defaultHtml` accepts a **custom inline renderer** as its second argument
  (`elm-markdown/Markdown/Block.elm:1425`), and `Markdown.Inline.defaultHtml`
  (`Inline.elm:102`) threads a custom transformer recursively through `Link`/`Emphasis`
  children. `Markdown.Inline` exposes `Inline(..)` and `defaultHtml`, so a self-referential
  custom renderer can intercept `Link` inlines (including links nested in emphasis).
- The app already shells out to native binaries via `std::process::Command` (the `latexmk`
  call, `fs_commands.rs:374`) and registers `#[tauri::command]` functions in
  `lib.rs:17` (`generate_handler![…]`). Custom commands are invoked from Elm through the
  generic FS bridge (`FileOps.send rid op args` → JS `invoke(op, args)` → `fsResponse`), so
  **no new ports, plugins, or capability entries are required** (the existing `read_file`
  etc. use exactly this path).
- The app knows the open document's location: `model.vaultRoot` (workspace root) and
  `model.selectedPath` (the document's vault-relative path). Existing FS commands already take
  the workspace `root` as an argument and confine paths to it.
- `Main.update`'s `GotRenderMsg` handler (`Main.elm:185`) currently handles `Render.ScrollTo`
  and has a `_ -> ( model, Cmd.none )` catch-all (`Main.elm:190`).

## Architecture

Intercept `Link` inlines in the markdown renderer, classify the href in Elm, dispatch a
`Render.RenderMsg`, and route it through the existing Elm→JS→Rust command bridge to a small
Rust command that resolves the path (confined to the vault) and runs `open`.

```
click link in rendered markdown
  → onClick (preventDefault) → Render.OpenUrl url | Render.OpenLocalFile target
  → Html.map GotRenderMsg (markdown body)
  → Main.update GotRenderMsg
      OpenUrl url        → FileOps.send rid "open_url"  { url }
      OpenLocalFile tgt  → FileOps.send rid "open_path" { root = vaultRoot, doc = selectedPath, target = tgt }
  → Rust open_url / open_path  →  std::process::Command "open"
  → errors return via fsResponse → existing error banner
```

### Alternatives considered

- **JS click-delegate** on the rendered container — fewer Elm changes, but it must be fed the
  current document's directory out-of-band and is not unit-testable. Rejected.
- **Swift rewrite** — unnecessary; the current stack does this natively. Rejected.

## Components / Changes

1. **`frontend/src/Render.elm`** — add two variants to `RenderMsg`:
   `OpenUrl String` and `OpenLocalFile String`. (Scripta's `eventToMsg` does not produce them;
   they are emitted only by the markdown renderer.)

2. **`frontend/src/MarkdownRender.elm`**
   - Add `type LinkKind = Web | LocalFile | Anchor` and
     `classifyLink : String -> LinkKind`:
     - starts with `http://`, `https://`, or `mailto:` → `Web`
     - starts with `#` → `Anchor`
     - otherwise → `LocalFile`
   - Add a recursive custom inline renderer `inlineRenderer : Inline i -> Html Render.RenderMsg`:
     - `Link url _ inlines` → an `<a href=url>` whose click is intercepted with
       `Html.Events.preventDefaultOn "click"` returning the classified message:
       `Web → OpenUrl url`, `LocalFile → OpenLocalFile url`, `Anchor → no interception`
       (render a plain native `a [ href url ]`). Children rendered via `List.map inlineRenderer`.
     - any other inline → `Inline.defaultHtml (Just inlineRenderer) inline` (recurses with the
       custom renderer so links inside emphasis are also intercepted).
   - Use `inlineRenderer` in place of the current inline rendering: pass `Just inlineRenderer`
     as the second argument to `Block.defaultHtml` (currently `Nothing`), and use
     `List.map inlineRenderer inlines` for heading content (currently `Inline.toHtml`).
   - The body's element type becomes `Html Render.RenderMsg` carrying real messages (it was
     effectively phantom before).

3. **`frontend/src/View.elm`** — in BOTH the `previewBody` and `readerView` markdown branches,
   map the body through `Html.map GotRenderMsg` instead of `Html.map (\_ -> NoOpFromRender)`,
   so link clicks dispatch. (Non-link content yields `RenderNoOp`, which the `Main`
   `GotRenderMsg` catch-all ignores.)

4. **`frontend/src/Main.elm`** — add two branches to the `GotRenderMsg` case (before the
   `_ ->` catch-all):
   - `Render.OpenUrl url` → issue an FS request for `"open_url"` with `{ url }`.
   - `Render.OpenLocalFile target` → if `model.vaultRoot` and `model.selectedPath` are present,
     issue an FS request for `"open_path"` with `{ root, doc = selectedPath, target }`;
     otherwise no-op. Use the existing request-issuing helper (the one that bumps
     `nextRequestId` and records the pending op). Add a `POpenExternal` variant to
     `PendingOp` (`Types.elm`) for both requests; its response handler ignores a successful
     result and, on error, sets `model.error` (so failures surface in the existing error
     banner). Confirm the `fsResponse` dispatch routes `POpenExternal` errors to the banner
     the same way other ops do.

5. **`src-tauri/src/fs_commands.rs`** — two commands plus a resolver helper:
   - `resolve_link_target(root, doc, target) -> Result<PathBuf, String>`: compute
     `parent(root.join(doc)).join(target)`, canonicalize, verify the canonical path is inside
     the canonical `root` (reject `../` escapes), and verify it exists. Mirrors the existing
     path-confinement used by `read_file`/`write_file`.
   - `open_path(root, doc, target) -> Result<(), String>`: `resolve_link_target` then
     `std::process::Command::new("open").arg(abs).spawn()` (default app for the type).
   - `open_url(url) -> Result<(), String>`: validate the scheme is `http`/`https`/`mailto`
     (reject anything else), then `std::process::Command::new("open").arg(url).spawn()`.
   Register `open_path` and `open_url` in `lib.rs:17`.

## Error Handling

- Missing target, path escaping the vault, or a non-allowed URL scheme → the Rust command
  returns `Err(String)` → `fsResponse` carries the error → surfaced via the existing error
  banner (the same path as other failed FS ops).
- No document open (`selectedPath = Nothing`) → the `OpenLocalFile` branch is a no-op.
- `open` spawn failure (rare) → `Err` → error banner.

## Testing

- **Rust** (mirror the existing `fs_commands` tests, which use `tempfile` dirs):
  - `resolve_link_target` resolves a sibling file next to the doc.
  - resolves relative to a doc that lives in a **subdirectory** (target is relative to the
    doc's dir, not the vault root).
  - **rejects** a `../`-escaping target (error, not a path outside the vault).
  - errors on a target that does not exist.
  - `open_url` rejects a non-http/https/mailto scheme (e.g. `file:` or `javascript:`).
  - (The `open` spawn itself is a side effect and is not unit-tested.)
- **Elm**:
  - `classifyLink` unit tests: `"https://e.com" → Web`, `"mailto:a@b.c" → Web`,
    `"#sec" → Anchor`, `"III_The_Rose.pdf" → LocalFile`, `"sub/dir/file.pdf" → LocalFile`.
  - `Test.Html` tests on `MarkdownRender.render`: `[x](a.pdf)` produces an `<a>` whose
    simulated click yields `Render.OpenLocalFile "a.pdf"`; `[x](https://e.com)` yields
    `Render.OpenUrl "https://e.com"`.
- **Manual**: in an `_index.md` with a PDF link, click it → opens in Preview; a web link →
  default browser; a link to a missing file → error banner.

## Out of Scope (YAGNI)

- In-app navigation to other `.md`/`.scripta` documents (per the chosen behavior, those open
  with their default app like any other local file).
- Links in the Scripta renderer (it has its own `RenderMsg` link handling).
- Reveal-in-Finder, or forcing a specific app (e.g. always Preview) regardless of file type.
