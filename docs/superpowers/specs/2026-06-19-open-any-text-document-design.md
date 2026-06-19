# Open & View Any Text Document — Design Spec

**Date:** 2026-06-19
**Status:** Approved (pending spec review)

## Goal

Let the app list, open, and view **any text file** in a vault — not just `.scripta`/`.tex`/`.md`.
A text file of any extension (`.txt`, `.csv`, `.json`, `.html`, …) appears in the file tree,
opens in the editor, and — if it is not a renderable type — shows its source in the preview.
Renderable types (Scripta, Markdown) are unchanged. Binary files (images, PDFs) stay out of the
tree (they remain reachable via markdown links → Preview).

This is the first of two sub-projects. The second (new-file placement into a `kbase/Inbox` vs.
the current folder, with no forced extension) is **out of scope here**.

## Context

- The file tree is built by `list_workspace_impl` (`src-tauri/src/fs_commands.rs:77`), which
  includes every directory and every file passing `has_doc_ext` — extension ∈
  `{scripta, tex, md}` (`EXTS`, `fs_commands.rs:65`; `has_doc_ext`, `:67`). Files of any other
  extension never appear and cannot be opened.
- `read_file` (`fs_commands.rs`) already reads a file as a UTF-8 string, so reading is not
  extension-limited — only the *listing* is.
- `Language.fromPath` (`frontend/src/Language.elm:17`) maps `.scripta → Scripta`,
  `.tex → MiniLaTeX`, `.md → Markdown`, and everything else → `Nothing`.
- `View.previewBody` (`frontend/src/View.elm`) renders Scripta and Markdown; any other
  `Just lang` shows "<Language> rendering is not yet supported."; `Nothing` (no document open)
  shows "Open a .scripta file."
- The editor pane already displays the loaded content of any opened file, so opening a plain
  text file already "works" once it is listed and selected — the gaps are (a) listing and
  (b) a useful preview for non-renderable text.
- Decision (settled in brainstorming): no MIME types. Type is decided by extension; "is it
  text" is decided by a content sniff. Nothing is stamped onto files on disk.

## Architecture

Three small, independent changes — one Rust (listing), two Elm (type model, preview):

1. **Listing by content sniff (Rust).** Replace the extension allowlist with a text test.
2. **`PlainText` language (Elm).** Unknown extensions become `PlainText` rather than unrecognized.
3. **Plain-text preview (Elm).** `PlainText` renders its source in a `<pre>`.

## Components / Changes

### 1. `src-tauri/src/fs_commands.rs` — list any text file

- Add `is_text_file(p: &Path) -> bool`: open the file, read up to the first 8192 bytes, and
  return `true` iff that chunk contains **no NUL byte** (`0x00`). An empty file is text. A read
  error returns `false` (skip it). This is the standard git-style binary heuristic; the NUL test
  avoids UTF-8-boundary false negatives that a `from_utf8` check on a truncated chunk would hit.
- In `list_workspace_impl`, replace the `!has_doc_ext(p)` filter for files with `!is_text_file(p)`.
- **Skip dotfiles and dot-directories**: skip any entry whose file name starts with `.` (and
  prune traversal into dot-directories). Without this, switching from the extension filter would
  surface `.git/…`, `.DS_Store`, etc. (For directories: do not descend into a dir whose name
  starts with `.`, and do not list it.)
- `has_doc_ext`/`EXTS` become unused; remove them (and update the `list_workspace_impl` doc
  comment to say "every directory and every text file").

Performance note: this reads up to 8 KB per file when listing a workspace. For the expected
vault sizes this is negligible; the read is capped so large files are not fully read.

### 2. `frontend/src/Language.elm` — `PlainText`

- Add `PlainText` to `type Language`.
- `fromPath`: `.scripta → Just Scripta`, `.tex → Just MiniLaTeX`, `.md → Just Markdown`,
  **any other extension (or no extension) → `Just PlainText`**. (It no longer returns `Nothing`
  for a path; the "no document" state is still represented by `model.language = Nothing` when
  there is no `selectedPath`.)
- `label PlainText = "Plain text"`.
- `isSupported` is unused (confirmed earlier) and is left as-is.

### 3. `frontend/src/View.elm` — plain-text preview

- In both `previewBody` and `readerView`'s document case, add a `PlainText` branch that renders
  the document's source (`model.content`) inside a `<pre>` with preserved whitespace and a
  monospace font, e.g. `Html.pre [ style "white-space" "pre-wrap", style "font-family" "ui-monospace, monospace", style "margin" "0" ] [ Html.text model.content ]`.
- MiniLaTeX keeps its existing "not yet supported" message (out of scope).
- Change the no-document empty state text from `"Open a .scripta file."` to `"Open a document."`

## Data Flow

```
list_workspace  →  Entry list now includes any text file (dotfiles/binary excluded)
  → file tree  → click → read_file (UTF-8 content) → editor shows content
  → View: Scripta/Markdown render; PlainText → <pre> source; MiniLaTeX → "not yet supported"
```

No new commands, ports, or messages. `read_file`, the watcher, and selection are unchanged.

## Error Handling

- A file that cannot be read during the sniff is treated as non-text (skipped from listing) —
  fail-closed, no error surfaced.
- Opening a listed text file uses the existing `read_file` path; a read failure surfaces via the
  existing error banner (unchanged).

## Testing

- **Rust** (mirror existing `fs_commands` tempdir tests):
  - `is_text_file`: a UTF-8 text file → `true`; a file containing a `\0` byte → `false`; an
    empty file → `true`.
  - `list_workspace_impl`: a `.txt` file is listed; a binary file (containing `\0`) is not; a
    dotfile (e.g. `.DS_Store`) and a dot-directory (e.g. `.git/config`) are not listed.
- **Elm:**
  - `Language.fromPath`: `"notes.txt" → Just PlainText`, `"data.json" → Just PlainText`,
    `"a.scripta" → Just Scripta`, `"b.md" → Just Markdown` (regression guard).
  - `View` (Test.Html): for a `PlainText` document, the preview contains a `pre` whose text is
    the document content.
- **Manual:** open a vault containing a `.txt` and a `.json` → both list, open, and show their
  source in the preview; a `.png` is not listed; `.git`/`.DS_Store` are not listed; a `.scripta`
  and a `.md` still render as before.

## Out of Scope (next sub-project / YAGNI)

- New-file placement: `kbase/Inbox` when in the kbase KB vs. the current folder, and using the
  typed filename verbatim (no forced `.scripta`). (Still needs the kbase-detection rule settled.)
- MiniLaTeX rendering.
- Syntax highlighting for plain-text / other formats in the preview.
- Any on-disk type tagging (UTI / xattr / MIME).
