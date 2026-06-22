# kbase rename + UI batch — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Seven UI changes: charcoal terminal background, a "K" app icon, a TOC that abuts the rendered text with a draggable divider plus hideable tree/TOC, off-white backgrounds, an app rename to "kbase", and a no-autocorrect / wider new-file-name field.

**Architecture:** Mostly CSS/JS in `index.html` and view changes in `View.elm`. The largest item (TOC + hideable tree/TOC) adds two session-only Model booleans, two toggle Msgs, and shared `renderedAndToc`/`renderTocColumns`/`treeCols` helpers used by all three layout views, plus a `localStorage`-persisted render/TOC drag handle mirroring the editor-split one.

**Tech Stack:** Elm 0.19, elm-test, plain JS/CSS in `index.html`, Tauri 2 (`tauri.conf.json`), an SVG icon regenerated via `make icon` (rsvg-convert).

## Global Constraints

- Run Elm checks from `frontend/`: `npx elm make src/Main.elm --output=/dev/null`, `npx elm-test`. Existing suite (131 tests) must stay green.
- elm-format conventions apply.
- Colors (verbatim): terminal bg `#333333`; light whites `--app-bg`/`--panel-bg`/`--cm-bg`/`--cm-tooltip-bg` → `#eeeeee`; `--chat-prompt-bg` → `#e0e0e0`; icon "K" `#1d3a8a`. Dark theme is NOT changed.
- Tree/TOC visibility is session-only (not persisted): `treeVisible` default `True`, `tocVisible` default `False`. The render/TOC divider *position* persists to `localStorage.renderTocSplit`.
- `renderedTextId` = `"__RENDERED_TEXT__"`; it must remain a container that wraps the rendered body blocks (the sync code does `getElementById('__RENDERED_TEXT__').querySelectorAll('[id]')`).
- Rename keeps identifier `io.scripta.viewer`; only product name / window title / dock / `.app` become `kbase`; the inner binary stays `mac-scripta-viewer`.

---

### Task 1: Charcoal terminal background

**Files:** Modify `frontend/index.html` (the `new Terminal({…})` call ~`:242`).

- [ ] **Step 1: Add the theme background**

Replace:

```js
          const term = new Terminal({ convertEol: false, fontFamily: 'ui-monospace, monospace', fontSize: 13 });
```

with:

```js
          const term = new Terminal({ convertEol: false, fontFamily: 'ui-monospace, monospace', fontSize: 13, theme: { background: '#333333' } });
```

- [ ] **Step 2: Verify**

Run: `cd frontend && npx elm-test` → 131 pass (no Elm change, sanity only). The HTML change has no compile step.

- [ ] **Step 3: Commit**

```bash
git add frontend/index.html
git commit -m "style: charcoal #333333 terminal background"
```

Note: verified visually after install.

---

### Task 2: Off-white backgrounds + visible chat bubble

**Files:** Modify `frontend/index.html` (light `:root` block, ~`:30-72`).

- [ ] **Step 1: Change the four whites and the chat bubble**

In the `:root { … }` block, make these five edits (each var line is unique):

- `--app-bg: #ffffff;` → `--app-bg: #eeeeee;`
- `--panel-bg: #ffffff;` → `--panel-bg: #eeeeee;`
- `--cm-bg: #ffffff;` → `--cm-bg: #eeeeee;`
- `--cm-tooltip-bg: #ffffff;` → `--cm-tooltip-bg: #eeeeee;`
- `--chat-prompt-bg: #eeeeee;` → `--chat-prompt-bg: #e0e0e0;`

Do NOT change the `[data-theme="dark"]` block.

- [ ] **Step 2: Verify**

Run: `cd frontend && npx elm-test` → 131 pass.

- [ ] **Step 3: Commit**

```bash
git add frontend/index.html
git commit -m "style: off-white #eeeeee backgrounds; chat bubble to #e0e0e0"
```

---

### Task 3: new-file-name input — no autocorrect + wider

**Files:** Modify `frontend/src/View.elm` (the new-file-name `Html.input`, ~`:134-143`).

- [ ] **Step 1: Update the input attributes**

Replace:

```elm
                , Html.input
                    [ Html.Attributes.placeholder "new-file-name"
                    , Html.Attributes.value model.newName
                    , onInput SetNewName
                    , style "width" "150px"
                    , Html.Attributes.attribute "autocapitalize" "off"
                    , Html.Attributes.attribute "autocorrect" "off"
                    , Html.Attributes.spellcheck False
                    ]
                    []
```

with:

```elm
                , Html.input
                    [ Html.Attributes.placeholder "new-file-name"
                    , Html.Attributes.value model.newName
                    , onInput SetNewName
                    , style "width" "300px"
                    , style "min-width" "150px"
                    , Html.Attributes.attribute "autocapitalize" "off"
                    , Html.Attributes.attribute "autocorrect" "off"
                    , Html.Attributes.attribute "autocomplete" "off"
                    , Html.Attributes.spellcheck False
                    ]
                    []
```

- [ ] **Step 2: Verify compiles + tests**

Run: `cd frontend && npx elm make src/Main.elm --output=/dev/null` → "Success!".
Run: `cd frontend && npx elm-test` → 131 pass.

- [ ] **Step 3: Commit**

```bash
git add frontend/src/View.elm
git commit -m "feat: new-file-name field wider (300/min 150) + autocomplete off"
```

---

### Task 4: Rename the app to "kbase"

**Files:** Modify `src-tauri/tauri.conf.json`, `frontend/index.html`, `Makefile`.

- [ ] **Step 1: tauri.conf.json — productName + window title**

In `src-tauri/tauri.conf.json`:
- `"productName": "Scripta",` → `"productName": "kbase",`
- In the window config, `"title": "Scripta",` → `"title": "kbase",` (the line `{ "title": "Scripta", "width": 1200, "height": 800 }` becomes `{ "title": "kbase", "width": 1200, "height": 800 }`).
- Leave `"identifier": "io.scripta.viewer"` unchanged.

- [ ] **Step 2: index.html — document title**

In `frontend/index.html`, replace `<title>Scripta</title>` with `<title>kbase</title>`.

- [ ] **Step 3: Makefile — install target**

In `Makefile`, update the `install` recipe and its comment:
- comment `# this is what makes a double-clicked /Applications/Scripta.app reflect new code.` → `…/Applications/kbase.app…`
- `@osascript -e 'tell application "Scripta" to quit' 2>/dev/null || true` → `… "kbase" to quit …`
- `@rm -rf "/Applications/Scripta.app"` → `@rm -rf "/Applications/kbase.app"`
- `@ditto "src-tauri/target/release/bundle/macos/Scripta.app" "/Applications/Scripta.app"` → `@ditto "src-tauri/target/release/bundle/macos/kbase.app" "/Applications/kbase.app"`
- `@echo "Installed Scripta.app -> /Applications"` → `@echo "Installed kbase.app -> /Applications"`

- [ ] **Step 4: Verify config is valid JSON + tests**

Run: `cd src-tauri && python3 -m json.tool tauri.conf.json >/dev/null && echo "json ok"` → `json ok`.
Run: `cd frontend && npx elm-test` → 131 pass.

- [ ] **Step 5: Commit**

```bash
git add src-tauri/tauri.conf.json frontend/index.html Makefile
git commit -m "chore: rename app to kbase (productName/title/dock; Makefile)"
```

Note: a full `make install` (which renames the bundle to `kbase.app`) is exercised in the final manual verification, not here.

---

### Task 5: App icon — pen → capital "K"

**Files:** Modify `src-tauri/icons/icon.svg`; regenerate committed icon assets with `make icon`.

- [ ] **Step 1: Replace the pen glyph with a "K"**

In `src-tauri/icons/icon.svg`, replace the entire pen group — the
`<g transform="rotate(40 50 50)" …> … </g>` element (all of its child
`<line>`/`<path>`/`<circle>` elements) — with a single centered letter:

```svg
    <text x="50" y="50" text-anchor="middle" dominant-baseline="central" font-family="Helvetica, Arial, sans-serif" font-weight="700" font-size="64" fill="#1d3a8a">K</text>
```

Keep the surrounding `<rect … fill="#d6e8fb"/>` background and the
`<g clip-path="url(#r)">` wrapper (the `<text>` goes inside the clip group in
place of the old pen `<g>`).

- [ ] **Step 2: Regenerate the icon set**

Run: `make icon`
Expected: completes without error; updates `src-tauri/icons/icon.png`, `icon.icns`, `32x32.png`, `128x128.png`, `128x128@2x.png` (and the iconset temp is removed).

- [ ] **Step 3: Sanity-check the SVG renders**

Run: `rsvg-convert -w 64 -h 64 src-tauri/icons/icon.svg -o /tmp/k-check.png && echo "rendered $(ls -la /tmp/k-check.png | awk '{print $5}') bytes"`
Expected: a non-zero byte count (the SVG is valid and renders).

- [ ] **Step 4: Commit**

```bash
git add src-tauri/icons/icon.svg src-tauri/icons/icon.png src-tauri/icons/icon.icns src-tauri/icons/32x32.png src-tauri/icons/128x128.png src-tauri/icons/128x128@2x.png
git commit -m "feat: app icon shows a capital K instead of a pen"
```

Note: the visible icon updates after `make install` (final verification).

---

### Task 6: TOC at right margin + hideable tree/TOC (Elm)

Adds the state, toggles, shared render/TOC helpers, and the view refactor. The render/TOC divider renders here (defaulting to 540px via the CSS fallback); Task 7 makes it draggable.

**Files:**
- Modify: `frontend/src/Types.elm` (Model ~`:37`; Msg ~ after `ToggledSettings`)
- Modify: `frontend/src/Main.elm` (`init` record ~`:65`; `update`)
- Modify: `frontend/src/View.elm` (`threePaneRow` ~`:62-83`, `readerView` ~`:151-226`, `imageView`; toolbar; new helpers)

**Interfaces:**
- Produces: Model fields `treeVisible : Bool`, `tocVisible : Bool`; Msgs `ToggledTree`, `ToggledToc`; helpers `renderedAndToc : Model -> ( List (Html Msg), List (Html Msg) )`, `renderTocColumns : Model -> List (Html Msg)`, `treeCols : Model -> List (Html Msg)`; handle element id `toc-split-handle` and CSS var `--render-toc-split` (consumed by Task 7).

- [ ] **Step 1: Model fields (`Types.elm`)**

Add after `, readerMode : Bool`:

```elm
    , readerMode : Bool
    , treeVisible : Bool
    , tocVisible : Bool
```

- [ ] **Step 2: Msgs (`Types.elm`)**

Add after `| ToggledSettings`:

```elm
    | ToggledSettings
    | ToggledTree
    | ToggledToc
```

- [ ] **Step 3: init (`Main.elm`)**

Add after `, readerMode = flags.readerMode`:

```elm
        , readerMode = flags.readerMode
        , treeVisible = True
        , tocVisible = False
```

- [ ] **Step 4: update branches (`Main.elm`)**

Add these two branches to the `update` case expression (place them next to `ToggledReaderMode`/`ToggledTheme`):

```elm
        ToggledTree ->
            ( { model | treeVisible = not model.treeVisible }, Cmd.none )

        ToggledToc ->
            ( { model | tocVisible = not model.tocVisible }, Cmd.none )
```

- [ ] **Step 5: Add the shared helpers (`View.elm`)**

Add these three helpers (e.g. just above `previewBody`):

```elm
treeCols : Model -> List (Html Msg)
treeCols model =
    if model.treeVisible then
        [ treeColumn model ]

    else
        []


{-| The rendered body and the TOC for the current document. -}
renderedAndToc : Model -> ( List (Html Msg), List (Html Msg) )
renderedAndToc model =
    case ( model.language, model.parsedDoc ) of
        ( Just Language.Scripta, Just doc ) ->
            let
                out =
                    Render.renderDocument model.isLight model.contentWidth doc
            in
            ( (out.title :: out.body) |> List.map (Html.map (\_ -> NoOpFromRender))
            , out.toc |> List.map (Html.map GotRenderMsg)
            )

        ( Just Language.Markdown, _ ) ->
            let
                out =
                    MarkdownRender.render model.content
            in
            ( out.body |> List.map (Html.map GotRenderMsg)
            , out.toc |> List.map (Html.map GotRenderMsg)
            )

        _ ->
            ( previewBody model, [] )


{-| The rendered-text column, plus a draggable divider and the TOC column when
the TOC is shown. The render column keeps id=renderedTextId wrapping the body. -}
renderTocColumns : Model -> List (Html Msg)
renderTocColumns model =
    let
        ( bodyHtml, tocHtml ) =
            renderedAndToc model

        showToc =
            model.tocVisible && not (List.isEmpty tocHtml)

        renderColumn =
            div
                ([ Html.Attributes.id Editor.renderedTextId
                 , style "padding" "16px"
                 , style "overflow" "auto"
                 ]
                    ++ (if showToc then
                            [ style "flex" "0 0 auto", style "width" "var(--render-toc-split, 540px)" ]

                        else
                            [ style "flex" "1" ]
                       )
                )
                [ div [ style "max-width" "5.5in" ] bodyHtml ]
    in
    renderColumn
        :: (if showToc then
                [ div
                    [ Html.Attributes.id "toc-split-handle"
                    , style "flex" "0 0 auto"
                    , style "width" "6px"
                    , style "cursor" "col-resize"
                    , style "background" "var(--border)"
                    ]
                    []
                , div
                    [ style "flex" "1"
                    , style "border-left" "1px solid var(--border)"
                    , style "padding" "16px"
                    , style "overflow" "auto"
                    ]
                    tocHtml
                ]

            else
                []
           )
```

- [ ] **Step 6: Refactor `threePaneRow` (`View.elm`)**

Replace the whole `threePaneRow` definition:

```elm
        threePaneRow =
            div [ style "display" "flex", style "flex" "1", style "min-height" "0" ]
                [ treeColumn model
                , Html.node "codemirror-editor"
                    [ Html.Attributes.attribute "text" model.loadedContent
                    , Html.Attributes.attribute "fill-parent" ""
                    , Html.Events.on "text-change" (D.map EditorChanged Editor.textChangeDecoder)
                    , style "flex" "0 0 auto"
                    , style "width" "var(--editor-split, 50%)"
                    , style "border-right" "1px solid var(--border)"
                    ]
                    []
                , div
                    [ Html.Attributes.id "editor-split-handle"
                    , style "flex" "0 0 auto"
                    , style "width" "6px"
                    , style "cursor" "col-resize"
                    , style "background" "var(--border)"
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

with:

```elm
        threePaneRow =
            div [ style "display" "flex", style "flex" "1", style "min-height" "0" ]
                (treeCols model
                    ++ [ Html.node "codemirror-editor"
                            [ Html.Attributes.attribute "text" model.loadedContent
                            , Html.Attributes.attribute "fill-parent" ""
                            , Html.Events.on "text-change" (D.map EditorChanged Editor.textChangeDecoder)
                            , style "flex" "0 0 auto"
                            , style "width" "var(--editor-split, 50%)"
                            , style "border-right" "1px solid var(--border)"
                            ]
                            []
                       , div
                            [ Html.Attributes.id "editor-split-handle"
                            , style "flex" "0 0 auto"
                            , style "width" "6px"
                            , style "cursor" "col-resize"
                            , style "background" "var(--border)"
                            ]
                            []
                       ]
                    ++ renderTocColumns model
                )
```

- [ ] **Step 7: Refactor `readerView` (`View.elm`)**

Replace the entire `readerView` definition (the `let ( bodyContent, tocCols ) = … in div [ … ] ([ treeColumn model, … ] ++ tocCols)` block) with:

```elm
        readerView =
            div [ style "display" "flex", style "flex" "1", style "min-height" "0" ]
                (treeCols model ++ renderTocColumns model)
```

- [ ] **Step 8: Refactor `imageView` (`View.elm`)**

Replace `imageView`:

```elm
imageView : Model -> Html Msg
imageView model =
    div [ style "display" "flex", style "flex" "1", style "min-height" "0" ]
        [ treeColumn model
        , div [ style "flex" "1", style "padding" "16px", style "overflow" "auto" ]
            [ imagePane model.imageSrc ]
        ]
```

with:

```elm
imageView : Model -> Html Msg
imageView model =
    div [ style "display" "flex", style "flex" "1", style "min-height" "0" ]
        (treeCols model
            ++ [ div [ style "flex" "1", style "padding" "16px", style "overflow" "auto" ]
                    [ imagePane model.imageSrc ]
               ]
        )
```

- [ ] **Step 9: Toolbar toggle buttons (`View.elm`)**

In the toolbar, insert two buttons immediately before the Settings button. Replace:

```elm
                , button [ onClick ToggledSettings ] [ text "⚙ Settings" ]
```

with:

```elm
                , button [ onClick ToggledTree ]
                    [ text
                        (if model.treeVisible then
                            "Hide Tree"

                         else
                            "Show Tree"
                        )
                    ]
                , button [ onClick ToggledToc ]
                    [ text
                        (if model.tocVisible then
                            "Hide TOC"

                         else
                            "Show TOC"
                        )
                    ]
                , button [ onClick ToggledSettings ] [ text "⚙ Settings" ]
```

- [ ] **Step 10: Verify compiles + tests**

Run: `cd frontend && npx elm make src/Main.elm --output=/dev/null` → "Success!".
Run: `cd frontend && npx elm-test` → 131 pass.

- [ ] **Step 11: Commit**

```bash
git add frontend/src/Types.elm frontend/src/Main.elm frontend/src/View.elm
git commit -m "feat: hideable tree/TOC; TOC abuts rendered text in both views"
```

Note: the `previewBody` helper remains (used by `renderedAndToc`'s fallback). After this task the TOC renders at the 540px CSS default; Task 7 adds dragging.

---

### Task 7: Draggable render/TOC divider (JS)

**Files:** Modify `frontend/index.html` (`:root` rule ~`:74`; new IIFE after the editor-split IIFE ~`:400`).

**Interfaces:** Consumes the `#toc-split-handle` element and `id=__RENDERED_TEXT__` render column from Task 6; sets CSS var `--render-toc-split`.

- [ ] **Step 1: Add the CSS var**

Change the `:root` rule:

```css
      :root { --terminal-height: 280px; --terminal-split: 50%; --editor-split: 50%; }
```

to:

```css
      :root { --terminal-height: 280px; --terminal-split: 50%; --editor-split: 50%; --render-toc-split: 540px; }
```

- [ ] **Step 2: Add the drag handler IIFE**

In `frontend/index.html`, immediately after the editor-split IIFE's closing
`})();`, insert:

```javascript

      // --- Vertical divider between the rendered text (left) and the TOC (right). ---
      (function () {
        var renderLeft = 0;
        function applyRenderTocSplit(px, persist) {
          var el = document.getElementById('__RENDERED_TEXT__');
          var left = el ? el.getBoundingClientRect().left : 0;
          var maxW = Math.max(300, window.innerWidth - left - 160);
          var w = Math.max(300, Math.min(maxW, px));
          document.documentElement.style.setProperty('--render-toc-split', w + 'px');
          if (persist) { try { localStorage.setItem('renderTocSplit', w); } catch (e) {} }
          return w;
        }
        var saved = parseInt(lsGet('renderTocSplit'), 10);
        if (!isNaN(saved)) applyRenderTocSplit(saved, true);
        var dragging = false;
        document.addEventListener('pointerdown', function (e) {
          if (e.target && e.target.id === 'toc-split-handle') {
            var el = document.getElementById('__RENDERED_TEXT__');
            renderLeft = el ? el.getBoundingClientRect().left : 0;
            dragging = true;
            e.preventDefault();
          }
        });
        document.addEventListener('pointermove', function (e) {
          if (!dragging) return;
          applyRenderTocSplit(e.clientX - renderLeft, false);
        });
        document.addEventListener('pointerup', function (e) {
          if (!dragging) return;
          dragging = false;
          applyRenderTocSplit(e.clientX - renderLeft, true);
        });
        window.addEventListener('resize', function () {
          var s = parseInt(lsGet('renderTocSplit'), 10);
          if (!isNaN(s)) applyRenderTocSplit(s, true);
        });
      })();
```

(`lsGet` is the existing localStorage helper.)

- [ ] **Step 3: Verify**

Run: `cd frontend && npx elm-test` → 131 pass (no Elm change).

- [ ] **Step 4: Commit**

```bash
git add frontend/index.html
git commit -m "feat: draggable, persisted divider between rendered text and TOC"
```

---

## Manual verification (after all tasks — `make install`)

`make install` now builds `/Applications/kbase.app`. Quit any old Scripta first; the old `/Applications/Scripta.app` can be deleted. Launch kbase:

1. Window title and dock name read **kbase**; the app icon shows a **K** on the light-blue square.
2. Terminal panes have a charcoal `#333333` background.
3. App/editor/panel backgrounds are off-white `#eeeeee`; the chat "You" bubble (`#e0e0e0`) is still visible.
4. Toolbar has **Hide/Show Tree** and **Show/Hide TOC** buttons. TOC is hidden by default; tree shown by default. Showing the TOC (standard or reader view) places it right at the rendered text's right margin; the divider between text and TOC drags and persists across relaunch; hiding the tree widens the content. Left/right and TOC-click sync still work.
5. The new-file-name field is ~twice as wide, shrinks no smaller than 150px when the toolbar is tight, and does not autocorrect.

---

## Self-Review notes

- **Spec coverage:** item 1 → Task 1; item 4 → Task 2; items 6+7 → Task 3; item 5 → Task 4; item 2 → Task 5; item 3 (state/toggles/layout) → Task 6, (drag handle) → Task 7. All mapped.
- **Type consistency:** `treeVisible`/`tocVisible`, `ToggledTree`/`ToggledToc`, `renderedAndToc`/`renderTocColumns`/`treeCols`, id `toc-split-handle`, var `--render-toc-split`, key `renderTocSplit`, and `id=__RENDERED_TEXT__` are used identically across Tasks 6 and 7.
- **Sync invariant preserved:** `renderTocColumns` keeps `id=renderedTextId` on the scrollable render column wrapping the body, so `getElementById('__RENDERED_TEXT__').querySelectorAll('[id]')` still finds the body blocks.
- **Every task leaves the repo compiling:** Task 6 lands all Elm changes together (new Msgs handled, helpers defined, views consistent); Task 7 only adds JS. After Task 6 the TOC renders at the 540px CSS default (works, not yet draggable).
- **Tests:** all changes are CSS/SVG/JS/view-typed, so verified by compile + the manual checklist; the existing 131 tests must remain green.
