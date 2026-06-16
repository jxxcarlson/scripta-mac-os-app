# Reader-Mode TOC, Tree Retention, 4.5″ Width, App Icon, Search Spacing — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** In reader mode keep the file tree, cap the rendered text at 4.5 inches, and add an active TOC column (click → center-scroll + pale-blue highlight); give the app a fountain-pen-nib icon; add a 1 mm gap above the search box.

**Architecture:** TOC clicks flow through a new `GotRenderMsg` Msg into a `scrollAndHighlight` port (JS centers the target and toggles a `.toc-sync-highlight` class). The reader layout reuses an extracted `treeColumn` helper and renders the document once, feeding `out.body` to a 4.5″-capped pane and `out.toc` to a right-hand column. The icon is an SVG rasterized by a `make icon` target into the macOS icon set.

**Tech Stack:** Elm 0.19.1, ports + JS/CSS in `index.html`, Tauri 2 bundle, `rsvg-convert`/`sips`/`iconutil` for icons.

---

## Reference (current state — verified)

- `frontend/src/Types.elm`: imports `Dict, Json.Decode as D, Language, SaveState, Scripta, Set, Workspace` (NOT `Render`). `Msg` includes `NoOpFromRender`, `ToggledReaderMode`, etc. exposed via `Types exposing (Model, Msg(..), PendingOp(..), Pane(..))`.
- `frontend/src/Render.elm`: `module Render exposing (RenderMsg(..), RenderOutput, options, compile, renderDocument, parse)`. `RenderMsg = ScrollTo String | ScrollToWithReturn {...} | ExpandImage String | NavigateToDocument String | HighlightId String | RenderNoOp`. `RenderOutput = { title : Html RenderMsg, body : List (Html RenderMsg), toc : List (Html RenderMsg) }`. `renderDocument : Bool -> Int -> Scripta.Document -> RenderOutput`. Render imports only `Html` and `Scripta` (so `Types`/`Main` importing `Render` creates no cycle).
- `frontend/src/FileOps.elm`: `port module FileOps exposing ( FsResponse, fsRequest, fsResponse, fileChanged, openFile, scrollToElement, saveOpenFolders, requestOpenFolders, gotOpenFolders, saveReaderMode, saveLastVault, encodeRequest, responseDecoder, resultOf, send )`. Last port declared is `port saveLastVault : String -> Cmd msg`.
- `frontend/src/Main.elm`: imports `Render` (line ~12). `update` is a `case msg of` with explicit branches and NO `_ ->` wildcard; `NoOpFromRender ->` exists (~line 181). Render messages are not otherwise handled.
- `frontend/src/View.elm` (current — includes reader toolbar from prior work): imports `Editor, Html exposing (Html, button, div, li, span, text, ul), Html.Attributes exposing (style), Html.Events exposing (onClick, onInput), Json.Decode as D, Language, Render, SaveState, Set exposing (Set), Svg, Svg.Attributes as SA, Types exposing (Model, Msg(..)), Workspace exposing (Node(..))`. `view` (lines 18–103) defines `threePaneRow` (tree `div` at lines 23–50 | `codemirror-editor` | rendered `div#__RENDERED_TEXT__` calling `previewBody model`), `toolbar`, `readerView` (preview-only, lines 86–93), `body = if model.readerMode then readerView else threePaneRow`, ending `div [...] (conflictBanner model ++ [ toolbar, body ])`. `previewBody : Model -> List (Html Msg)` (lines 251–267) renders `(out.title :: out.body) |> List.map (Html.map (\_ -> NoOpFromRender))`. `searchBox` (lines 172–183) has `style "margin-bottom" "8px"`. `Editor.renderedTextId = "__RENDERED_TEXT__"`. Qualified `Html.Attributes.id` is already used (line 59), so qualified access works despite the narrow `exposing (style)`.
- `frontend/index.html`: Elm init + `app.ports.*` handlers; the last one is `app.ports.saveLastVault.subscribe(...)`. Below it is the Ctrl-S `lrSync` block. `<style>` has a `.lr-sync-highlight { background-color:#fff2a8; transition: background-color .2s ease; border-radius:2px; }` rule (added just after `button:hover` rules).
- `src-tauri/tauri.conf.json`: `"bundle": { "active": true, "targets": "app", "icon": [] }`. `src-tauri/icons/icon.png` is a 32×32 placeholder.
- `Makefile`: `.PHONY: elm dev build test test-elm test-rust`; `build:` runs `npx tauri build`; `test:` runs `test-elm` (`elm-test`) + `test-rust` (`cargo test`). Tools present: `rsvg-convert`, `sips`, `iconutil`.

**Path note:** repo root has a space — always quote. End commit messages with:
`Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`

**Testing note:** This work is view + ports + assets; there is no new pure logic to unit-test. Verification is `elm make` success, `elm-test`/`cargo test` staying green (no regressions), and the manual GUI checklist in Task 5. This matches the accepted approach of the prior reader-mode plan.

---

## File structure

```
frontend/
├── src/
│   ├── Types.elm        # + import Render; GotRenderMsg Render.RenderMsg
│   ├── FileOps.elm      # + scrollAndHighlight port
│   ├── Main.elm         # + GotRenderMsg handler
│   └── View.elm         # treeColumn helper; 3-col reader layout; TOC map; 1mm search gap
│   └── index.html       # .toc-sync-highlight CSS + scrollAndHighlight handler
src-tauri/
├── icons/icon.svg       # NEW artwork (+ generated icon set)
└── tauri.conf.json      # icon references
Makefile                 # + icon target
```

---

### Task 1: Elm wiring — render-message carrier + scroll/highlight port

**Files:**
- Modify: `frontend/src/Types.elm`
- Modify: `frontend/src/FileOps.elm`
- Modify: `frontend/src/Main.elm`

- [ ] **Step 1: Types.elm — import Render**

Add to the import list (after `import Language`):
```elm
import Render
```

- [ ] **Step 2: Types.elm — add the Msg constructor**

In `type Msg`, add (e.g. after `| NoOpFromRender`):
```elm
    | GotRenderMsg Render.RenderMsg
```

- [ ] **Step 3: FileOps.elm — declare the port**

Add `scrollAndHighlight` to the `exposing ( ... )` list (next to `scrollToElement`):
```elm
    , scrollToElement, scrollAndHighlight
```
(Replace the existing `, scrollToElement` line with the line above.) Then declare the port after `port saveLastVault : String -> Cmd msg`:
```elm


port scrollAndHighlight : String -> Cmd msg
```

- [ ] **Step 4: Main.elm — handle GotRenderMsg**

Add this branch to `update` (place it right after the `NoOpFromRender ->` branch):
```elm
        GotRenderMsg renderMsg ->
            case renderMsg of
                Render.ScrollTo id ->
                    ( model, FileOps.scrollAndHighlight id )

                _ ->
                    ( model, Cmd.none )
```

- [ ] **Step 5: Verify build + tests**

Run: `cd frontend && elm make src/Main.elm --output=dist/elm.js 2>&1 | tail -20`
Expected: `Success!`. (`GotRenderMsg` is handled but not yet produced — fine.)
Run: `cd frontend && elm-test 2>&1 | tail -6`
Expected: 38 passed.

- [ ] **Step 6: Commit**

```bash
git add frontend/src/Types.elm frontend/src/FileOps.elm frontend/src/Main.elm
git commit -m "feat: GotRenderMsg + scrollAndHighlight port for active TOC

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: index.html — pale-blue highlight CSS + scrollAndHighlight handler

**Files:**
- Modify: `frontend/index.html`

- [ ] **Step 1: Add the `.toc-sync-highlight` CSS**

In the `<style>` block, directly after the existing `.lr-sync-highlight { ... }` rule, add:
```css
      .toc-sync-highlight {
        background-color: #cfe6fb;
        transition: background-color 0.2s ease;
        border-radius: 2px;
      }
```

- [ ] **Step 2: Add the port handler**

Immediately after the `app.ports.saveLastVault.subscribe(...)` handler block, add:
```javascript
      app.ports.scrollAndHighlight.subscribe((id) => {
        const el = document.getElementById(id);
        if (!el) return;
        el.scrollIntoView({ block: 'center', behavior: 'smooth' });
        document.querySelectorAll('.toc-sync-highlight').forEach((n) => {
          n.classList.remove('toc-sync-highlight');
        });
        el.classList.add('toc-sync-highlight');
      });
```

- [ ] **Step 3: Verify wiring**

Run: `grep -n "toc-sync-highlight\|scrollAndHighlight" frontend/index.html`
Expected: the CSS rule and the port handler both present.

- [ ] **Step 4: Build sanity**

Run: `cd frontend && elm make src/Main.elm --output=dist/elm.js 2>&1 | tail -3`
Expected: `Success!`.

- [ ] **Step 5: Commit**

```bash
git add frontend/index.html
git commit -m "feat: scrollAndHighlight handler + pale-blue .toc-sync-highlight

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: View.elm — shared tree column, 3-column reader layout, TOC, 1 mm search gap

**Files:**
- Modify: `frontend/src/View.elm`

- [ ] **Step 1: Extract `treeColumn` helper**

Add this top-level function just above `view` (it is the existing tree `div`, lines 23–50, verbatim):
```elm
treeColumn : Model -> Html Msg
treeColumn model =
    div [ style "width" "260px", style "border-right" "1px solid #ddd", style "padding" "8px", style "overflow" "auto" ]
        (button [ onClick ClickedOpenVault ] [ text "Open Vault" ]
            :: errorBanner model
            ++ [ searchBox model
               , fileTree model
               , div [ style "font-size" "12px", style "color" "#666", style "margin-top" "6px" ]
                    [ text (saveLabel model.saveState.saveStatus) ]
               , div [ style "margin-top" "8px" ]
                    [ Html.input
                        [ Html.Attributes.placeholder "new-file-name"
                        , Html.Attributes.value model.newName
                        , onInput SetNewName
                        , style "width" "150px"
                        ]
                        []
                    , button [ onClick ClickedNewFile ] [ text "New" ]
                    , button [ onClick ClickedRename ] [ text "Rename" ]
                    ]
               , div [ style "margin-top" "4px" ]
                    [ button [ onClick ClickedDeleteSelected ] [ text "Delete" ]
                    , button [ onClick ClickedChangeVault ] [ text "Change Vault" ]
                    ]
               , div [ style "margin-top" "4px" ]
                    [ button [ onClick ClickedExportHtml ] [ text "Export HTML" ]
                    , button [ onClick ClickedExportLatex ] [ text "Export LaTeX" ]
                    ]
               ]
        )
```

- [ ] **Step 2: Use `treeColumn` in `threePaneRow`**

In `view`, replace the entire tree `div` (current lines 23–50, the first child of `threePaneRow`) with a single line so `threePaneRow` reads:
```elm
        threePaneRow =
            div [ style "display" "flex", style "flex" "1", style "min-height" "0" ]
                [ treeColumn model
                , Html.node "codemirror-editor"
                    [ Html.Attributes.attribute "text" model.loadedContent
                    , Html.Events.on "text-change" (D.map EditorChanged Editor.textChangeDecoder)
                    , style "flex" "1"
                    , style "border-right" "1px solid #ddd"
                    ]
                    []
                , div
                    [ Html.Attributes.id Editor.renderedTextId
                    , style "flex" "1"
                    , style "padding" "16px"
                    , style "overflow" "auto"
                    ]
                    (previewBody model)
                ]
```

- [ ] **Step 3: Replace `readerView` with the 3-column layout**

Replace the current `readerView` let-binding (lines 86–93) with:
```elm
        readerView =
            let
                ( bodyContent, tocCols ) =
                    case ( model.language, model.parsedDoc ) of
                        ( Just Language.Scripta, Just doc ) ->
                            let
                                out =
                                    Render.renderDocument model.isLight model.contentWidth doc

                                bodyHtml =
                                    (out.title :: out.body)
                                        |> List.map (Html.map (\_ -> NoOpFromRender))

                                tocCol =
                                    if List.isEmpty out.toc then
                                        []

                                    else
                                        [ div
                                            [ style "width" "220px"
                                            , style "flex" "0 0 auto"
                                            , style "border-left" "1px solid #ddd"
                                            , style "padding" "16px"
                                            , style "overflow" "auto"
                                            ]
                                            (List.map (Html.map GotRenderMsg) out.toc)
                                        ]
                            in
                            ( bodyHtml, tocCol )

                        _ ->
                            ( previewBody model, [] )
            in
            div [ style "display" "flex", style "flex" "1", style "min-height" "0" ]
                ([ treeColumn model
                 , div
                    [ style "flex" "1"
                    , style "padding" "16px"
                    , style "overflow" "auto"
                    ]
                    [ div
                        [ Html.Attributes.id Editor.renderedTextId
                        , style "max-width" "4.5in"
                        ]
                        bodyContent
                    ]
                 ]
                    ++ tocCols
                )
```

- [ ] **Step 4: Add the 1 mm gap above the search box**

In `searchBox` (lines 172–183), add a `margin-top` style. Change:
```elm
        , style "margin-bottom" "8px"
        ]
        []
```
to:
```elm
        , style "margin-bottom" "8px"
        , style "margin-top" "1mm"
        ]
        []
```

- [ ] **Step 5: Verify build + tests**

Run: `cd frontend && elm make src/Main.elm --output=dist/elm.js 2>&1 | tail -20`
Expected: `Success!`.
Run: `cd frontend && elm-test 2>&1 | tail -6`
Expected: 38 passed.

- [ ] **Step 6: Commit**

```bash
git add frontend/src/View.elm
git commit -m "feat: reader-mode keeps tree, caps text at 4.5in, adds active TOC column; 1mm search gap

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: App icon — fountain-pen-nib SVG + generation + Tauri references

**Files:**
- Create: `src-tauri/icons/icon.svg`
- Modify: `Makefile`
- Modify: `src-tauri/tauri.conf.json`

- [ ] **Step 1: Create the SVG artwork** — `src-tauri/icons/icon.svg`:

```xml
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" width="1024" height="1024">
  <defs>
    <clipPath id="r"><rect x="2" y="2" width="96" height="96" rx="22"/></clipPath>
  </defs>
  <rect x="2" y="2" width="96" height="96" rx="22" fill="#d6e8fb"/>
  <g clip-path="url(#r)">
    <g transform="rotate(40 50 50)" fill="none" stroke="#1d3a8a" stroke-width="2.4" stroke-linejoin="round" stroke-linecap="round">
      <line x1="38" y1="22" x2="38" y2="-34"/>
      <line x1="62" y1="22" x2="62" y2="-34"/>
      <path d="M34,30 C34,22 66,22 66,30 L66,38 C66,40 34,40 34,38 Z"/>
      <line x1="34" y1="34" x2="66" y2="34"/>
      <path d="M50,94 C42,79 32,61 30,46 C29,40 38,36 50,36 C62,36 71,40 70,46 C68,61 58,79 50,94 Z"/>
      <circle cx="50" cy="50" r="4.5"/>
      <line x1="50" y1="54.5" x2="50" y2="92"/>
    </g>
  </g>
</svg>
```

- [ ] **Step 2: Add the `icon` target to the Makefile**

Add `icon` to the `.PHONY` line:
```makefile
.PHONY: elm dev build test test-elm test-rust icon
```
Then add this target (rasterizes the SVG → 1024 master → `.icns` + the PNG sizes Tauri references):
```makefile
icon:
	cd src-tauri/icons && \
	rsvg-convert -w 1024 -h 1024 icon.svg -o icon.png && \
	rm -rf icon.iconset && mkdir icon.iconset && \
	sips -z 16 16     icon.png --out icon.iconset/icon_16x16.png && \
	sips -z 32 32     icon.png --out icon.iconset/icon_16x16@2x.png && \
	sips -z 32 32     icon.png --out icon.iconset/icon_32x32.png && \
	sips -z 64 64     icon.png --out icon.iconset/icon_32x32@2x.png && \
	sips -z 128 128   icon.png --out icon.iconset/icon_128x128.png && \
	sips -z 256 256   icon.png --out icon.iconset/icon_128x128@2x.png && \
	sips -z 256 256   icon.png --out icon.iconset/icon_256x256.png && \
	sips -z 512 512   icon.png --out icon.iconset/icon_256x256@2x.png && \
	sips -z 512 512   icon.png --out icon.iconset/icon_512x512.png && \
	cp icon.png icon.iconset/icon_512x512@2x.png && \
	iconutil -c icns icon.iconset -o icon.icns && \
	sips -z 32 32   icon.png --out 32x32.png && \
	sips -z 128 128 icon.png --out 128x128.png && \
	sips -z 256 256 icon.png --out 128x128@2x.png && \
	rm -rf icon.iconset
```
(Indent the recipe lines with TABS, not spaces.)

- [ ] **Step 3: Generate the icon set**

Run: `cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer" && make icon 2>&1 | tail -5`
Then: `ls -1 src-tauri/icons`
Expected: `icon.svg icon.png icon.icns 32x32.png 128x128.png 128x128@2x.png` all present.

- [ ] **Step 4: Reference the icons in tauri.conf.json**

In `src-tauri/tauri.conf.json`, replace `"icon": []` with:
```json
    "icon": [
      "icons/32x32.png",
      "icons/128x128.png",
      "icons/128x128@2x.png",
      "icons/icon.icns"
    ]
```

- [ ] **Step 5: Commit**

```bash
git add src-tauri/icons/icon.svg src-tauri/icons/icon.png src-tauri/icons/icon.icns src-tauri/icons/32x32.png src-tauri/icons/128x128.png "src-tauri/icons/128x128@2x.png" Makefile src-tauri/tauri.conf.json
git commit -m "feat: fountain-pen-nib app icon (SVG + generated set, make icon target)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Build, reinstall, manual verification

**Files:** none (build + manual).

- [ ] **Step 1: Full automated suite**

Run: `cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer" && make test 2>&1 | tail -15`
Expected: elm-test (38) and cargo test (13) pass.

- [ ] **Step 2: Build + reinstall**

```bash
cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer"
make build 2>&1 | tail -6
SRC="src-tauri/target/release/bundle/macos/Mac Scripta Viewer.app"
DEST="/Applications/Mac Scripta Viewer.app"
rm -rf "$DEST" && ditto "$SRC" "$DEST"
```

- [ ] **Step 3: Manual verification (GUI — user runs these)**

1. **Reader mode layout:** open a `.scripta` doc, click **Reader** → file tree stays on the left, rendered text sits next to it capped at ~4.5 in wide, and (if the doc has sections) a TOC column appears on the right. Click **Exit Reader** → three panes return.
2. **Active TOC:** click a TOC entry → the matching heading scrolls to the vertical center of the rendered pane and flashes pale blue.
3. **No-TOC document:** open a doc with no sections in reader mode → no empty TOC column.
4. **Icon:** the app shows the fountain-pen-nib icon in Finder and the Dock; it stays legible at small size.
5. **Search gap:** a ~1 mm space sits above the document search box in the tree column.

- [ ] **Step 4: Commit any fixes** found during manual testing (none if all good).

---

## Self-review notes (coverage map)

- Reader keeps tree → Task 3 (`treeColumn` reused in `readerView`).
- Rendered text ≤ 4.5 in → Task 3 (inner `div` `max-width:4.5in`).
- Active TOC (render `out.toc`, click → center + pale-blue highlight) → Task 1 (`GotRenderMsg` + `scrollAndHighlight`), Task 2 (handler + `.toc-sync-highlight` `#cfe6fb`), Task 3 (`Html.map GotRenderMsg out.toc`, layout B order tree|doc|TOC, omit when empty).
- App icon (pale blue + dark-blue nib outline + body) → Task 4 (SVG, `make icon`, tauri refs).
- 1 mm above search box → Task 3 Step 4 (`margin-top:1mm`).

## Out of scope

- Making rendered *body* clicks active (only TOC clicks are wired).
- TOC scroll-spy / auto-highlighting the current section while scrolling.
- Windows/Linux icon formats (macOS `.app` only).
