# Open & View Any Text or Image Document — Design Spec

**Date:** 2026-06-19
**Status:** Approved-with-changes (pending re-review)

## Goal

Let the app list, open, and view **any text file** and **common image files** in a vault — not
just `.scripta`/`.tex`/`.md`.

- A **text** file of any extension (`.txt`, `.csv`, `.json`, `.html`, …) appears in the file
  tree, opens in the editor, and — if it is not a renderable type — shows its source in the
  preview. Renderable types (Scripta, Markdown) are unchanged.
- An **image** file (`.jpg`, `.jpeg`, `.png`, `.gif`, `.webp`) appears in the tree and, when
  selected, is **displayed** (via an `<img>` tag) instead of edited — images are not editable, so
  there is no editor pane for them; the content area shows the image.
- Other **binary** files (e.g. `.pdf`) stay out of the tree (still reachable via markdown links →
  Preview).

This is the first of two sub-projects. The second (new-file placement into a `kbase/Inbox` vs.
the current folder, with no forced extension) is **out of scope here**. A separate deferred idea —
image *companion* `.md` files — is recorded in memory and not part of this work.

## Context

- The file tree is built by `list_workspace_impl` (`src-tauri/src/fs_commands.rs:77`), which
  includes every directory and every file passing `has_doc_ext` — extension ∈
  `{scripta, tex, md}` (`EXTS`, `fs_commands.rs:65`; `has_doc_ext`, `:67`).
- `read_file` reads a file as a UTF-8 string (fails on binary), so it is used for text only.
- `Language.fromPath` (`frontend/src/Language.elm:17`) maps `.scripta/.tex/.md` to languages and
  everything else → `Nothing`.
- `View.previewBody`/`readerView` (`frontend/src/View.elm`) render Scripta and Markdown; `view`
  shows a split editor+preview (`threePaneRow`) or `readerView`; `model.readerMode` toggles them.
- `ClickedTreeNode` (`Main.elm:171`) issues `read_file` for the clicked path and sets
  `language = Language.fromPath path`. `request`/`handleResponse`/`PendingOp` are the FS-bridge
  plumbing (`Main.elm:69`, `:432`; `Types.elm`).
- Decision (settled in brainstorming): no MIME types. Type is by extension; "is it text" is by a
  content sniff; nothing is stamped on disk.

## Architecture

- **Listing (Rust):** include a file if it sniffs as text **or** has an image extension; skip
  dotfiles/dot-dirs.
- **Type model (Elm):** add `PlainText` and `Image` to `Language`; unknown extensions → `PlainText`.
- **Text preview (Elm):** `PlainText` renders its source in a `<pre>`.
- **Image viewing (Elm + Rust):** a new `read_image` command returns a base64 `data:` URL;
  selecting an image stores it in the model and `view` shows it as an `<img>` (no editor).

## Components / Changes

### 1. `src-tauri/src/fs_commands.rs` — list text and image files

- `is_text_file(p: &Path) -> bool`: read up to the first 8192 bytes; `true` iff the chunk has
  **no NUL byte** (`0x00`); empty file → `true`; read error → `false`. (git-style binary test;
  NUL avoids UTF-8-boundary false negatives.)
- `is_image_ext(p: &Path) -> bool`: extension (case-insensitive) ∈
  `{jpg, jpeg, png, gif, webp}`.
- In `list_workspace_impl`, include a file when `is_text_file(p) || is_image_ext(p)`. **Skip
  dotfiles and dot-directories** (any entry whose name starts with `.`; do not descend into
  dot-dirs). Remove the now-unused `has_doc_ext`/`EXTS`; update the doc comment.
- `read_image(root: String, path: String) -> Result<String, String>` (`#[tauri::command]`,
  registered in `lib.rs`): read the file's bytes at `root.join(path)`, base64-encode, and return
  a data URL `data:<mime>;base64,<b64>` where `<mime>` is by extension
  (`png→image/png`, `jpg`/`jpeg→image/jpeg`, `gif→image/gif`, `webp→image/webp`). Add the
  `base64` crate to `src-tauri/Cargo.toml`.

### 2. `frontend/src/Language.elm` — `PlainText` + `Image`

- Add `PlainText` and `Image` to `type Language`.
- `fromPath`: `.scripta → Scripta`, `.tex → MiniLaTeX`, `.md → Markdown`,
  `.jpg/.jpeg/.png/.gif/.webp → Image`, **any other → `PlainText`**. (Still wrapped in `Just`;
  the "no document" state remains `model.language = Nothing` when there is no `selectedPath`.)
- `label`: `PlainText → "Plain text"`, `Image → "Image"`. `isSupported` left as-is (unused).

### 3. `frontend/src/Types.elm` + `frontend/src/Main.elm` — open images via data URL

- `Types.elm`: add `imageSrc : Maybe String` to `Model` (the data URL of the open image, else
  `Nothing`); add `PReadImage String` to `PendingOp`.
- `Main.elm` init: `imageSrc = Nothing`.
- `ClickedTreeNode path`: if `Language.fromPath path == Just Image`, issue
  `request (PReadImage path) "read_image" [ ("root", …), ("path", …) ] { model | selectedPath = Just path, language = Just Image }`
  (do **not** call `read_file` for images). Otherwise the existing `read_file` path, but also set
  `imageSrc = Nothing` (clear any previously shown image).
- `handleResponse`:
  - `PReadImage _`: decode the result as a string (the data URL) →
    `{ model | imageSrc = Just url, content = "", loadedContent = "", parsedDoc = Nothing }`;
    a decode error sets `model.error`.
  - The existing `PReadFile` branch additionally sets `imageSrc = Nothing` (defensive; the click
    path already cleared it).

### 4. `frontend/src/View.elm` — plain-text preview + image view

- **Image view:** in `view`, before the `readerMode` split, if `model.language == Just Image`
  render an image layout: the tree column plus a scrollable content pane containing
  `Html.img [ src (Maybe.withDefault "" model.imageSrc), style "max-width" "100%", style "height" "auto" ] []`
  (a placeholder/empty pane if `imageSrc` is `Nothing`). No editor, no Scripta/Markdown preview,
  regardless of `readerMode`.
- **Plain-text preview:** in `previewBody` and `readerView`'s document case, add a `PlainText`
  branch rendering `model.content` in a `<pre>`
  (`Html.pre [ style "white-space" "pre-wrap", style "font-family" "ui-monospace, monospace", style "margin" "0" ] [ Html.text model.content ]`).
- MiniLaTeX keeps its existing "not yet supported" message. Empty-state text
  `"Open a .scripta file."` → `"Open a document."`

## Data Flow

```
list_workspace → tree includes text files + image files (dotfiles/other-binary excluded)
  → click file:
       Image     → read_image → data URL → model.imageSrc → view shows <img> (no editor)
       text type → read_file  → content  → editor + preview (Scripta/Markdown render; PlainText → <pre>)
```

No new ports or subscriptions. `read_image` rides the existing FS bridge like every other command.

## Error Handling

- Sniff/read error during listing → file treated as non-text and skipped (fail-closed).
- `read_image` failure (unreadable/oversized) → `Err` → existing error banner.
- `PReadImage` decode failure → `model.error`.

## Testing

- **Rust** (tempdir tests, mirroring existing ones):
  - `is_text_file`: UTF-8 text → `true`; contains `\0` → `false`; empty → `true`.
  - `is_image_ext`: `png`/`jpg`/`jpeg`/`gif`/`webp` → `true`; `txt`/`pdf` → `false`.
  - `list_workspace_impl`: lists a `.txt` and a `.png`; excludes a binary `.bin` (NUL byte) and a
    `.pdf`; excludes a dotfile (`.DS_Store`) and a dot-dir (`.git/config`).
  - `read_image`: for a file written with a `.png` extension, the result begins with
    `data:image/png;base64,` (and decodes back to the original bytes).
- **Elm:**
  - `Language.fromPath`: `"a.txt" → Just PlainText`, `"b.json" → Just PlainText`,
    `"c.png" → Just Image`, `"d.JPG" → Just Image`, `"e.scripta" → Just Scripta`,
    `"f.md" → Just Markdown`.
  - `View` (Test.Html): a `PlainText` document's preview contains a `pre` with the content; an
    `Image` document (with `imageSrc` set) renders an `img` whose `src` is the data URL.
- **Manual:** open a vault with a `.txt`, `.json`, `.png`, and `.jpg` → text files list/open/show
  source; images list and display as `<img>` with no editor; `.pdf` and `.git`/`.DS_Store` are not
  listed; `.scripta`/`.md` still render normally.

## Out of Scope (next sub-project / deferred / YAGNI)

- New-file placement: `kbase/Inbox` vs. the current folder, filename verbatim (no forced
  `.scripta`). (Needs the kbase-detection rule settled.)
- **Image companion `.md` files** (deferred; recorded in memory `image-companion-files`).
- MiniLaTeX rendering; syntax highlighting for plain text.
- Editing/saving images; image zoom/pan; very-large-image handling beyond surfacing read errors.
- Any on-disk type tagging (UTI / xattr / MIME).
