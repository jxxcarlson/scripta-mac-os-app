# Reader-Mode TOC, Tree Retention, 4.5″ Width, App Icon, Search-Box Spacing — Design Spec

**Date:** 2026-06-16

## Goal

Polish the reader experience and app presentation:

1. **Reader mode keeps the file tree** and caps the rendered text pane at **4.5 inches** wide.
2. **Reader mode adds an active Table of Contents column.** Clicking a TOC item scrolls the
   target rendered element to vertical center and highlights it in **pale blue**.
3. **App icon:** a stylized fountain-pen-nib outline drawing — dark-blue line art on a pale-blue
   rounded square, with the pen body running off the top-right edge.
4. A **1 mm gap** above the document search box in the file-tree column.

## Current state (verified)

- `frontend/src/View.elm`: `view` builds `threePaneRow` (tree `div` 260px | `codemirror-editor` |
  rendered `div#__RENDERED_TEXT__`). Reader mode (`model.readerMode`) currently swaps the whole
  three-pane row for a preview-only `readerView`. `previewBody model` renders `out.title :: out.body`
  and maps **all** render events to `NoOpFromRender` (clicks swallowed). `searchBox` (View.elm:172)
  is an `Html.input` with `margin-bottom:8px`, placed just under the "Open Vault" button.
- `frontend/src/Render.elm`: `RenderOutput = { title, body, toc }`; `toc : List (Html RenderMsg)`
  is produced (compiler `withTOC True`) but **never displayed**. `RenderMsg` includes
  `ScrollTo String` (TOC/heading clicks emit `Scripta.ClickedId id → ScrollTo id`).
- `frontend/src/Editor.elm`: `renderedTextId = "__RENDERED_TEXT__"`.
- `frontend/src/FileOps.elm`: has `scrollToElement : String -> Cmd msg` (wired in `index.html`
  to `scrollIntoView({block:'start'})`) but it is **unused from Elm**. The Ctrl-S left-to-right
  sync in `index.html` already implements center-scroll + a `.lr-sync-highlight` (yellow) class.
- `frontend/src/Types.elm`: `Msg` has `NoOpFromRender`; no render-message carrier.
- `src-tauri/tauri.conf.json`: `"bundle": { "targets": "app", "icon": [] }` — no custom icon.
  `src-tauri/icons/icon.png` is a 32×32 placeholder. Tooling available: `rsvg-convert`, `magick`,
  `sips`, `iconutil`.
- `Makefile`: has `elm`, `build`, `test` targets (build runs `make elm` via Tauri `beforeBuildCommand`).

## Design

### 1. Shared tree column + reader layout (View.elm)

- Extract the existing left tree `div` (the 260px column built inside `threePaneRow`) into a
  `treeColumn : Model -> Html Msg` helper. `threePaneRow` uses it; reader mode reuses it verbatim
  so the tree (incl. search box, buttons) is identical in both modes.
- Reader layout (left→right), matching the approved **layout B**:
  ```
  [ toolbar: Exit Reader ]
  [ treeColumn (260px) | rendered pane (max-width 4.5in) | tocColumn (~220px) ]
  ```
  - **Rendered pane:** a flex row whose child is a container `div#__RENDERED_TEXT__` with
    `max-width: 4.5in`, `padding:16px`, `overflow:auto`, holding `previewBody model`. Document is
    left-aligned (hugs the tree); slack space falls between the document and the TOC. The id stays
    unique because only one of three-pane / reader is mounted at a time.
  - **Width approach:** CSS `max-width: 4.5in` on the pane container (CSS supports `in`). We do
    **not** change Scripta's `contentWidth`; this caps the pane literally as requested.
  - **TOC column** (`tocColumn`): far-right `div`, ~220px, `overflow:auto`, left border, padded.
    Contents = the rendered TOC (see §2). When `out.toc` is empty, the column is **omitted entirely**
    (not rendered) — no empty chrome.

### 2. Active Table of Contents

- **Display:** render `out.toc` into `tocColumn`. Since `previewBody` currently discards `out`,
  add a small `previewParts : Model -> RenderOutput`-style accessor (or compute `out` once in `view`
  and pass `out.body`/`out.toc` to the respective columns) so both body and TOC come from one render.
- **Wire TOC clicks:** add `GotRenderMsg Render.RenderMsg` to `Msg`. Map the **TOC** html with
  `Html.map GotRenderMsg` (the body preview keeps mapping to `NoOpFromRender` for now — out of scope
  to make body clicks active).
- **Handle in `update`:** `GotRenderMsg (ScrollTo id) → ( model, FileOps.scrollAndHighlight id )`.
  Other `RenderMsg` variants (`ScrollToWithReturn`, `ExpandImage`, `NavigateToDocument`,
  `HighlightId`, `RenderNoOp`) → `( model, Cmd.none )` for this scope.
- **New port** `scrollAndHighlight : String -> Cmd msg` (FileOps.elm). JS (index.html):
  find `document.getElementById(id)`; `scrollIntoView({block:'center', behavior:'smooth'})`;
  clear any existing `.toc-sync-highlight`, then add it to the target.
- **Highlight style:** new CSS class `.toc-sync-highlight` with a **pale-blue** background
  (`#cfe6fb`) and the same `transition`/`border-radius` as `.lr-sync-highlight`. Distinct from the
  yellow Ctrl-S sync highlight, per the user's preference.

### 3. App icon (fountain-pen nib outline)

- Add `src-tauri/icons/icon.svg` — the approved artwork: pale-blue (`#d6e8fb`) rounded square,
  dark-blue (`#1d3a8a`) line art: nib + section/band + two body lines running up-right out of the
  frame (clipped to the rounded rect), nib group `rotate(40 50 50)`.
- Add a `make icon` target that rasterizes the SVG and regenerates the icon set:
  - `rsvg-convert -w 1024 -h 1024 icon.svg → icon-1024.png` (master).
  - Generate the macOS `.icns` via an `.iconset` (`sips -z` for each size + `iconutil -c icns`),
    plus the PNG sizes Tauri references (`32x32.png`, `128x128.png`, `128x128@2x.png`, `icon.png`).
  - Update `tauri.conf.json` `"icon"` to list the generated `.icns`/`.png` files.
- `make build` continues to bundle the `.app`; the custom icon now appears in Finder/Dock.

### 4. Search-box spacing (View.elm)

- Add `style "margin-top" "1mm"` to the `searchBox` input (CSS supports `mm`; 1 mm ≈ 3.78 px),
  producing a 1 mm gap above the search field.

## Files touched

- `frontend/src/Types.elm` — add `GotRenderMsg Render.RenderMsg` to `Msg`.
- `frontend/src/FileOps.elm` — add `scrollAndHighlight` port (+ export).
- `frontend/src/Main.elm` — handle `GotRenderMsg`.
- `frontend/src/View.elm` — `treeColumn` helper; reader layout (tree | 4.5in pane | TOC);
  TOC rendering + `Html.map GotRenderMsg`; `searchBox` 1 mm top margin.
- `frontend/index.html` — `.toc-sync-highlight` CSS; `scrollAndHighlight` port handler.
- `src-tauri/icons/icon.svg` — new artwork.
- `src-tauri/icons/*` (generated), `src-tauri/tauri.conf.json` — icon set + references.
- `Makefile` — `icon` target.

## Testing

- `elm-test` and `cargo test` stay green (no logic regressions). The work is view + ports + assets,
  so the bulk of verification is build + manual GUI.
- **Manual checklist:**
  1. Reader mode shows tree + rendered pane (≤4.5″) + TOC; Exit Reader returns to three-pane.
  2. Clicking a TOC entry centers the target in the rendered pane and flashes it pale blue.
  3. Document with no TOC: no empty TOC chrome.
  4. App icon (fountain pen) shows in Finder/Dock after build + reinstall, legible small.
  5. ~1 mm gap visible above the search box.

## Decisions / out of scope

- **Reuse vs new highlight:** TOC click uses a new **pale-blue** `.toc-sync-highlight` (distinct
  from the yellow Ctrl-S highlight).
- **Width:** CSS `max-width:4.5in` on the pane, not a Scripta `contentWidth` change.
- **Out of scope:** making rendered *body* clicks active; auto-highlighting the current section in
  the TOC while scrolling; Windows/Linux icon formats (macOS `.app` only); TOC scroll-spy.
