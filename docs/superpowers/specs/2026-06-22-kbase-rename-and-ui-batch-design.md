# kbase rename + UI batch — Design

Date: 2026-06-22

Seven changes in the Elm + Tauri app:

1. Terminal panes get a charcoal `#333333` background.
2. App icon: replace the pen glyph with a large capital **K**.
3. TOC abuts the rendered text's right margin with a draggable render/TOC
   divider, in **both** the standard and reader views; the file tree and the TOC
   are hideable/revealable (tree visible by default, TOC hidden by default).
4. White backgrounds become off-white `#eeeeee`; the chat "You" bubble moves to
   `#e0e0e0` so it stays visible.
5. Rename the app to **kbase**.
6. The new-file-name input does no autocorrection.
7. The new-file-name input is twice as wide but can contract to its current
   width.

---

## 1. Terminal background → charcoal

**File:** `frontend/index.html` (the `new Terminal({…})` call ~`:242`).

Add a `theme` with a charcoal background:

```js
const term = new Terminal({ convertEol: false, fontFamily: 'ui-monospace, monospace', fontSize: 13, theme: { background: '#333333' } });
```

xterm's default light foreground stays readable on `#333333`. No other change.

---

## 2. App icon: pen → capital K

**Files:** `frontend/../src-tauri/icons/icon.svg`; regenerate with `make icon`
(`rsvg-convert` is installed at `/opt/homebrew/bin/rsvg-convert`).

In `src-tauri/icons/icon.svg`, keep the rounded-square background
(`<rect … fill="#d6e8fb"/>`) and the clip path, but **replace** the pen `<g
transform="rotate(40 50 50)" …>…</g>` group with a single large bold **K**:

```svg
  <text x="50" y="50" text-anchor="middle" dominant-baseline="central"
        font-family="Helvetica, Arial, sans-serif" font-weight="700"
        font-size="64" fill="#1d3a8a">K</text>
```

Then run `make icon` to regenerate `icon.png`, `icon.icns`, and the PNG sizes
(all committed). `make install` bundles the new icon.

---

## 3. TOC layout + hideable tree/TOC

### Current
- `threePaneRow` (standard view, `View.elm` ~`:62-83`): `treeColumn | editor (width var(--editor-split)) | #editor-split-handle | preview (flex 1, id=renderedTextId)`. **No TOC.**
- `readerView` (`View.elm` ~`:151-226`): `treeColumn | rendered-text (flex 1, padding, inner div#renderedTextId max-width 5.5in) | TOC (fixed 220px, border-left, far right)`.
- `imageView` also begins with `treeColumn`.
- `renderedTextId` = `"__RENDERED_TEXT__"`; the left/right + TOC sync code in
  `index.html` (~`:501-571`) calls `getElementById('__RENDERED_TEXT__')` and
  `.querySelectorAll('[id]')` on it, so it must remain a container that **wraps
  the rendered body blocks**.

### Design

**State (`Types.elm` Model):**
- `treeVisible : Bool` — default `True`.
- `tocVisible : Bool` — default `False`.
Session-only (not persisted): set in `init`; reset each launch.

**Messages (`Types.elm`):** `ToggledTree`, `ToggledToc`.

**Update (`Main.elm`):**
- `ToggledTree -> ( { model | treeVisible = not model.treeVisible }, Cmd.none )`
- `ToggledToc  -> ( { model | tocVisible  = not model.tocVisible  }, Cmd.none )`

**Toolbar (`View.elm`):** two buttons (place near `⚙ Settings`):
- Tree toggle: `onClick ToggledTree`, label `if model.treeVisible then "Hide Tree" else "Show Tree"`.
- TOC toggle: `onClick ToggledToc`, label `if model.tocVisible then "Hide TOC" else "Show TOC"`.

**Shared render/TOC content (`View.elm`):** add a helper returning both the body
and the TOC for the current document, replacing the inline duplication in
`readerView` and reusing the cases from `previewBody`:

```elm
renderedAndToc : Model -> ( List (Html Msg), List (Html Msg) )
```

- Scripta + parsedDoc: `out = Render.renderDocument …`; body = `(out.title :: out.body) |> List.map (Html.map (\_ -> NoOpFromRender))`; toc = `out.toc |> List.map (Html.map GotRenderMsg)`.
- Markdown: `out = MarkdownRender.render model.content`; body = `out.body |> List.map (Html.map GotRenderMsg)`; toc = `out.toc |> List.map (Html.map GotRenderMsg)`.
- Otherwise: body = `previewBody model`; toc = `[]`.

**Shared layout (`View.elm`):** a helper producing the render column and,
when the TOC is shown, the divider + TOC column:

```elm
renderTocColumns : Model -> List (Html Msg)
```

Let `( bodyHtml, tocHtml ) = renderedAndToc model` and
`showToc = model.tocVisible && not (List.isEmpty tocHtml)`. It returns:

- The render column (always): a scrollable container carrying `id renderedTextId`,
  `style "padding" "16px"`, `style "overflow" "auto"`, with
  `style "flex" "0 0 auto"` + `style "width" "var(--render-toc-split, 540px)"`
  when `showToc`, else `style "flex" "1"`. Inside it, a single wrapper
  `div [ style "max-width" "5.5in" ] bodyHtml` (so the body blocks stay
  descendants of `renderedTextId` for sync).
- When `showToc`, additionally:
  - a handle `div [ Html.Attributes.id "toc-split-handle", style "flex" "0 0 auto", style "width" "6px", style "cursor" "col-resize", style "background" "var(--border)" ] []`
  - a TOC column `div [ style "flex" "1", style "border-left" "1px solid var(--border)", style "padding" "16px", style "overflow" "auto" ] tocHtml`.

**Wiring the two views:**
- A tree helper: `treeCols model = if model.treeVisible then [ treeColumn model ] else []`.
- `threePaneRow` row children = `treeCols model ++ [ editor, editorSplitHandle ] ++ renderTocColumns model`
  (the editor element and the existing `#editor-split-handle` are factored out of the current inline list).
- `readerView` row children = `treeCols model ++ renderTocColumns model`.
- `imageView`: render `treeColumn` only when `model.treeVisible` (wrap with `treeCols model`).

**Drag handler (`index.html`):** add `--render-toc-split: 540px` to the `:root`
rule, and a new IIFE (mirroring the editor-split one) for `#toc-split-handle`:

- On `pointerdown` of `#toc-split-handle`: record the render column's left edge
  via `document.getElementById('__RENDERED_TEXT__').getBoundingClientRect().left`.
- On move/up: `applyRenderTocSplit(e.clientX - renderLeft, persist)`.
- `applyRenderTocSplit(px, persist)`: recompute `left` from
  `getElementById('__RENDERED_TEXT__')` (null-safe → 0); clamp
  `w = Math.max(300, Math.min(window.innerWidth - left - 160, px))`; set
  `--render-toc-split = w + 'px'`; persist to `localStorage.renderTocSplit`.
- On load: restore from `localStorage.renderTocSplit`; re-clamp on `window.resize`.

(The render/TOC split position persists in localStorage even though tree/TOC
*visibility* does not — same as the editor split.)

### Testing
- `renderedAndToc` is view-typed (returns `Html`), so it's verified by
  compilation + manual, not a unit test.
- Manual: toggle tree and TOC (TOC hidden by default); when TOC is shown it
  abuts the text's right edge and the render/TOC divider drags and persists, in
  both standard and reader views; left/right and TOC click-sync still work.

---

## 4. Off-white backgrounds + visible chat bubble

**File:** `frontend/index.html`, light `:root` block only (dark theme unchanged).

- `--app-bg`, `--panel-bg`, `--cm-bg`, `--cm-tooltip-bg`: `#ffffff` → `#eeeeee`.
- `--chat-prompt-bg`: `#eeeeee` → `#e0e0e0` (so the "You" bubble stays distinct
  from the now-off-white panel).

---

## 5. Rename the app to "kbase"

**Files:** `src-tauri/tauri.conf.json`, `frontend/index.html`, `Makefile`.

- `tauri.conf.json`: `"productName": "Scripta"` → `"kbase"`; the window
  `"title": "Scripta"` → `"kbase"`. **Keep** `"identifier": "io.scripta.viewer"`
  (changing it would orphan saved settings/Keychain). The bundle output becomes
  `kbase.app`; the inner binary stays `mac-scripta-viewer` (crate name).
- `index.html`: `<title>Scripta</title>` → `<title>kbase</title>`.
- `Makefile` `install` target: replace `Scripta.app` with `kbase.app` in the
  `rm -rf`, `ditto`, and echo lines, and change the osascript quit target from
  `"Scripta"` to `"kbase"`.

**Note:** after this lands, `make install` produces `/Applications/kbase.app`;
the old `/Applications/Scripta.app` remains until manually deleted, and the
currently-running Scripta must be quit by hand once (the new osascript targets
`kbase`).

---

## 6 & 7. new-file-name input: no autocorrect + wider

**File:** `frontend/src/View.elm`, the new-file-name `Html.input` (~`:134-143`).

It already has `autocapitalize="off"`, `autocorrect="off"`, `spellcheck False`.
Change:

- **#6:** add `Html.Attributes.attribute "autocomplete" "off"` (the missing
  attribute; macOS WebView honours the full set together).
- **#7:** change `style "width" "150px"` to `style "width" "300px"` and add
  `style "min-width" "150px"`. As a flex item in the wrapping toolbar it
  contracts toward 150px when space is tight, never below the old width.

### Testing
- Manual: the field is ~twice as wide, shrinks no smaller than 150px when the
  toolbar wraps, and does not autocorrect typed filenames.

---

## Out of scope
- Persisting tree/TOC visibility across launches (session-only by decision).
- Markdown→PDF export (deferred separately).
- Changing the bundle identifier or the inner binary name.
- Dark-theme color changes (item 4 is light-theme only).

## Global notes
- Colors: whites → `#eeeeee`; `--chat-prompt-bg` → `#e0e0e0`; terminal bg
  `#333333`; icon K `#1d3a8a`.
- The render/TOC divider persists to `localStorage.renderTocSplit`; tree/TOC
  visibility does not persist.
