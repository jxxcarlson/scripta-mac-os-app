# Editor sizing + TOC-in-all-modes layout fix — Design

Date: 2026-06-22

Fix the content layout so the editor/render divider works reliably and the
editor can't hog the width, and make the TOC available in Both, Editor, and
Reader modes (resizable). Keeps both draggable dividers.

## Problems being fixed
1. **Stuck divider / editor hogs:** the editor is `flex 0 1 auto`, so when the
   saved `--editor-split` is large the editor flex-shrinks to fill the space and
   the divider stops responding; render/TOC get crushed.
2. **Stale saved split never clamped:** the divider IIFEs run before
   `Elm.Main.init` (index.html), so `applyEditorSplit(saved)` measures the
   editor at `left=0` (not in DOM) and never reserves room for the tree.
3. **No TOC in Editor mode.**

## Target layout (per mode, TOC toggled on)
```
Both:    [tree] [ editor │ rendered-text │ TOC ]
Editor:  [tree] [ editor              │ TOC ]
Reader:  [tree] [ rendered-text │ TOC ]
```
`--editor-split` = the editor's right edge (the divider just right of the
editor) in BOTH Both and Editor modes. `--render-toc-split` = the rendered-text
column width (Both/Reader). The hidden editor stays mounted in Reader
(`display:none`).

## Constants (tunable)
- Editor hard cap: `max-width: 700px`.
- Editor-split clamp reserve: `360px` (room for render+TOC to the editor's right).
- Render/TOC-split clamp reserve: `160px` (room for TOC), min render `300px`.

## Feature A — `contentRow` (`frontend/src/View.elm`)

Replace the current `contentRow` `let` bindings and final assembly. Key changes:
`showToc` no longer requires `showRender`; the editor is rigid with a max-width;
a new `showEdHandle`; the editor-split handle appears in Editor mode (between
editor and TOC); the TOC handle only between render and TOC.

```elm
contentRow : Model -> Html Msg
contentRow model =
    let
        ( bodyHtml, tocHtml ) =
            renderedAndToc model

        showRender =
            model.viewMode == ViewBoth || model.viewMode == ViewReader

        showToc =
            model.tocVisible && not (List.isEmpty tocHtml)

        showEdHandle =
            (model.viewMode == ViewBoth)
                || (model.viewMode == ViewEditor && showToc)

        editorSized =
            [ style "flex" "0 0 auto"
            , style "width" "var(--editor-split, 50%)"
            , style "min-width" "0"
            , style "max-width" "700px"
            , style "border-right" "1px solid var(--border)"
            ]

        editorStyles =
            case model.viewMode of
                ViewReader ->
                    [ style "display" "none" ]

                ViewBoth ->
                    editorSized

                ViewEditor ->
                    if showToc then
                        editorSized

                    else
                        [ style "flex" "1 1 auto", style "min-width" "0" ]

        treeKeyed =
            if model.treeVisible then
                [ ( "tree", treeColumn model ) ]

            else
                []

        editorKeyed =
            ( "editor"
            , Html.node "codemirror-editor"
                ([ Html.Attributes.attribute "text" model.loadedContent
                 , Html.Attributes.attribute "fill-parent" ""
                 , Html.Events.on "text-change" (D.map EditorChanged Editor.textChangeDecoder)
                 ]
                    ++ editorStyles
                )
                []
            )

        handle id_ =
            div
                [ Html.Attributes.id id_
                , style "flex" "0 0 auto"
                , style "width" "6px"
                , style "cursor" "col-resize"
                , style "background" "var(--border)"
                ]
                []

        editorHandleKeyed =
            if showEdHandle then
                [ ( "ed-handle", handle "editor-split-handle" ) ]

            else
                []

        renderKeyed =
            if showRender then
                [ ( "render"
                  , div
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
                  )
                ]

            else
                []

        tocHandleKeyed =
            if showRender && showToc then
                [ ( "toc-handle", handle "toc-split-handle" ) ]

            else
                []

        tocKeyed =
            if showToc then
                [ ( "toc"
                  , div
                        [ style "flex" "1"
                        , style "border-left" "1px solid var(--border)"
                        , style "padding" "16px"
                        , style "overflow" "auto"
                        ]
                        tocHtml
                  )
                ]

            else
                []
    in
    Html.Keyed.node "div"
        [ style "display" "flex", style "flex" "1", style "min-height" "0" ]
        (treeKeyed
            ++ [ editorKeyed ]
            ++ editorHandleKeyed
            ++ renderKeyed
            ++ tocHandleKeyed
            ++ tocKeyed
        )
```

### Per-mode result (verifies the assembly)
- Both + TOC: `tree | editor(var) | ed-handle | render(var) | toc-handle | toc`.
- Both, no TOC: `tree | editor(var) | ed-handle | render(flex 1)`.
- Editor + TOC: `tree | editor(var) | ed-handle | toc` (ed-handle = editor↔TOC; `--editor-split`).
- Editor, no TOC: `tree | editor(flex 1 fills)`.
- Reader + TOC: `tree | editor(display:none) | render(var) | toc-handle | toc`.
- Reader, no TOC: `tree | editor(display:none) | render(flex 1)`.

## Feature B — divider clamps + re-clamp on load (`frontend/index.html`)

In the **editor-split IIFE**:
- Change the clamp reserve from `200` to `360`:
  `var maxW = Math.max(200, window.innerWidth - left - 360);`
- Change the initial apply to run AFTER Elm renders (so `left` is correct):
  replace `if (!isNaN(saved)) applyEditorSplit(saved, true);` with
  `if (!isNaN(saved)) requestAnimationFrame(function () { applyEditorSplit(saved, true); });`

In the **render-toc IIFE** (clamp reserve `160`/min `300` unchanged):
- Change the initial apply the same way:
  replace `if (!isNaN(saved)) applyRenderTocSplit(saved, true);` with
  `if (!isNaN(saved)) requestAnimationFrame(function () { applyRenderTocSplit(saved, true); });`

(The `requestAnimationFrame` fires after `Elm.Main.init`'s synchronous initial
render, so the editor / `__RENDERED_TEXT__` elements exist and the clamp reserves
room for the tree. This reduces a stale, too-wide saved value on launch.)

## Testing
- View + JS changes → verified by compile + manual; existing 135 Elm tests stay
  green.
- Manual: divider drags reliably in Both and Editor; editor never exceeds ~700px
  nor crushes render/TOC; on launch a previously-too-wide editor is reduced so
  render/TOC are visible; TOC toggles on/off in all three modes and is resizable.

## Out of scope
- Per-mode different reserves (uniform 360/160 for now).
- Resetting the user's saved `--editor-split` (the load re-clamp handles the
  too-wide case without discarding their preference).
