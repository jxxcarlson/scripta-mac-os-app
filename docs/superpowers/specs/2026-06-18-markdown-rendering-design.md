# Extended-Markdown Rendering + Active TOC — Design Spec

**Date:** 2026-06-18
**Status:** Approved (pending spec review)

## Goal

Render extended-Markdown (`.md`) files in the Mac Scripta Viewer preview — including
`$…$`/`$$…$$` math — and provide an **active table of contents** whose entries scroll to
and highlight the target heading, matching the behavior of the existing Scripta reader TOC.

## Context

`.md` files are already wired end-to-end *except for rendering*:

- The Rust backend already lists `.md` files in the tree (`src-tauri/src/fs_commands.rs:74`,
  `:249` — recognized doc extensions are `scripta/tex/md`).
- `Language.fromPath` already maps `.md → Just Language.Markdown` (`frontend/src/Language.elm:17`).
- The `math-text` custom element (`frontend/index.html:97`) and the `scrollAndHighlight` port
  (`frontend/index.html:224`) are already present.
- `Language.isSupported` (`frontend/src/Language.elm:40`) is **defined but never called** —
  it gates nothing today, so it is out of scope.

The only thing blocking markdown is that `View.previewBody` and `View.readerView`
(`frontend/src/View.elm:357`, `:101`) dispatch on `Language.Scripta` only, and there is no
markdown renderer. This change is therefore **frontend-only and additive**.

## Architecture

Vendor v4's self-contained `elm-markdown/` library, add a thin `MarkdownRender` integration
module that returns the *existing* `Render.RenderOutput` shape, and add a `Language.Markdown`
branch to the two `View` functions that already dispatch on `Language.Scripta`.

No Rust changes. No `index.html` changes. No `Main.elm` changes (the `Render.ScrollTo`
handler already exists at `Main.elm:187`).

## Components

### 1. Vendored `frontend/elm-markdown/`

Copy v4's 8 modules verbatim from
`/Users/carlson/dev/elm-work/scripta/scripta-app-v4/frontend/elm-markdown/`:

```
Markdown.elm
Markdown/Config.elm
Markdown/Block.elm
Markdown/InlineParser.elm
Markdown/Inline.elm
Markdown/TableOfContents.elm
Markdown/Helpers.elm
Markdown/Entity.elm
```

These import only `Char`, `Dict` (elm/core), `Html`, `Html.Attributes` (elm/html),
`Regex` (elm/regex), `Result` (elm/core), `Url` (elm/url), and their own `Markdown.*`
modules — **all already present** in the Mac app's `elm.json`. No new dependencies.

Add `"elm-markdown"` to `source-directories` in `frontend/elm.json`.

**Math:** `Markdown/Inline.elm:122` emits `node "math-text" [ attribute "content" content,
attribute "display" "false" ]` for inline math; `Markdown/Block.elm:1578` emits the same with
`display "true"` for display math. These attribute names (`content`, `display`) are exactly
what the Mac app's `math-text` element observes (`index.html:98`), so math renders via the
existing KaTeX wiring with no extra work.

### 2. New `frontend/src/MarkdownRender.elm`

Exposes a single function returning the shared `Render.RenderOutput`:

```elm
render : String -> Render.RenderOutput
```

Behavior:

- `blocks = Markdown.Block.parse Nothing source`
- **body**: `List.indexedMap markdownBlockToHtmlIndexed blocks |> List.concat`, each mapped
  to `Render.RenderNoOp`, wrapped in a padded `div`. `markdownBlockToHtmlIndexed` is ported
  from v4's `Render.elm`: a `Heading` block renders as the matching `h1..h6` carrying
  `id (Markdown.TableOfContents.headingId headingText)` (slug, e.g. `"hello-world"`); all
  other blocks defer to `Markdown.Block.defaultHtml`.
- **active TOC**: `tocItems = Markdown.TableOfContents.fromBlocks blocks`; if
  `Markdown.TableOfContents.size tocItems > 1`, render a **custom TOC walker** (described
  below) producing `List (Html Render.RenderMsg)`; otherwise `[]`.

The custom TOC walker is the **one deliberate divergence from v4**. v4's `ToC.toHtml`
renders native `<a href="#slug">` anchors (instant browser scroll, no highlight). Instead,
`MarkdownRender` walks the `ToCItem` tree using the exposed accessors
(`ToC.level`, `ToC.heading`, `ToC.children`) and renders each entry as a clickable element
with `onClick (Render.ScrollTo (ToC.headingId (ToC.heading item)))`. This routes clicks
through the **same** `Render.ScrollTo → GotRenderMsg → FileOps.scrollAndHighlight` path the
Scripta reader TOC uses, giving identical smooth-scroll-to-center + `.toc-sync-highlight`
behavior. The walker recurses on `ToC.children` to preserve nesting.

`render` ignores theme/content-width (v4's markdown block rendering does not use them), so no
`isLight`/`contentWidth` parameters are needed. The reader view already wraps body in a
max-width container.

### 3. `frontend/src/View.elm`

Add a `( Just Language.Markdown, _ )` branch to both dispatch sites:

- **`previewBody`** (`:357`, split-editor view): render
  `MarkdownRender.render model.content` body only, mapped `\_ -> NoOpFromRender`. No TOC
  column in split view — this matches the Scripta path, which also shows no TOC column here.
- **`readerView`** (`:101`): render `MarkdownRender.render model.content`; produce
  `bodyHtml` mapped `\_ -> NoOpFromRender` and a `tocCol` mapped
  `List.map (Html.map GotRenderMsg)`, using the **same column markup/placement** (220px,
  left border, `:114`) and the **same `>1`-entry rule** as the Scripta branch
  (`out.toc` empty → no column). The markdown branch's "is there a TOC" test is whether
  `MarkdownRender.render`'s `toc` list is non-empty.

Both branches use live `model.content` (the field Scripta parsing also reads), so the preview
updates as the user edits.

## Data Flow

```
model.content (live editor text)
  → MarkdownRender.render            (parse + render in view; regex parser is sub-ms)
  → Render.RenderOutput { title, body, toc }
  → View renders body + (reader mode) TOC column
TOC entry click
  → Render.ScrollTo slug
  → GotRenderMsg (Main.elm:187)
  → FileOps.scrollAndHighlight slug
  → index.html: getElementById(slug).scrollIntoView({block:'center'}) + .toc-sync-highlight
```

Parsing happens in `view` on each render. Markdown's regex-based parser over typical document
sizes is sub-millisecond to low-millisecond, so no stored-blocks / incremental-parse machinery
is introduced (YAGNI). The Scripta incremental path (`model.parsedDoc`) is untouched and
remains Scripta-only.

## Error Handling

- Malformed markdown: `Markdown.Block.parse` is total (never fails) — unparseable constructs
  render as literal text. No error path needed.
- Math errors: handled by the existing `math-text` element (KaTeX `throwOnError: false`
  renders `.katex-error` spans and dispatches `katex-error` events) — unchanged.
- Empty / heading-poor document: `size <= 1` → no TOC column; body still renders.

## Testing

- **`elm-test` (`MarkdownRender`)**:
  - parsing `"# Hello World"` yields body HTML containing a heading with `id="hello-world"`.
  - a document with ≥2 headings yields a non-empty `toc`; a document with ≤1 heading yields
    an empty `toc`.
  - a TOC entry for heading "Hello World" carries `Render.ScrollTo "hello-world"`
    (verified via the rendered `onClick` decoder or by asserting on the walker's output
    structure).
- **`make build`**: confirms the vendored `elm-markdown/` compiles against the Mac app's
  existing dependencies (no missing packages).
- **Manual**: open a `.md` file containing inline `$a^2+b^2=c^2$`, display `$$\int_0^1 x\,dx$$`,
  and multiple headings. Verify math renders, the reader-mode TOC lists the headings, and
  clicking a TOC entry smooth-scrolls to and highlights the heading.

## Known Limitation (documented, not fixed)

Markdown headings use slug ids (`hello-world`), not Scripta's line-keyed `N-I` / `e-N.T` ids.
The Ctrl-S **left→right sync** (`index.html:250` `lrSync`) parses those line-keyed ids to map
the editor cursor line to a rendered element, so it **cannot locate markdown blocks** —
Ctrl-S is effectively a no-op for `.md`. This matches v4 ("Markdown emits no data-line markers
→ no RL sync"). TOC navigation works fully; only cursor-line LR sync is unavailable for `.md`.

## Out of Scope (YAGNI)

- MiniLaTeX rendering (separate language, separate effort).
- Markdown left→right / right→left cursor sync.
- Touching the unused `Language.isSupported`.
