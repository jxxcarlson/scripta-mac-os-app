# Extended-Markdown Rendering + Active TOC Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render extended-Markdown (`.md`) files in the preview — including `$…$`/`$$…$$` math — with an active table of contents whose entries scroll to and highlight the target heading, matching the Scripta reader TOC.

**Architecture:** Frontend-only, additive. Vendor v4's self-contained `elm-markdown/` library; add a thin `MarkdownRender` module returning the existing `Render.RenderOutput` shape; add a `Language.Markdown` branch to the two `View` functions that already dispatch on `Language.Scripta`. Math flows through the existing `math-text`/KaTeX wiring; TOC clicks route through the existing `Render.ScrollTo → GotRenderMsg → scrollAndHighlight` path.

**Tech Stack:** Elm 0.19.1, vendored `elm-markdown` (8 modules, no new deps), `elm-explorations/test` (incl. `Test.Html.*`), Tauri 2 shell (unchanged).

Spec: `docs/superpowers/specs/2026-06-18-markdown-rendering-design.md`

---

## File Structure

- **Create** `frontend/elm-markdown/` — 8 vendored modules (verbatim copy from v4).
- **Modify** `frontend/elm.json` — add `"elm-markdown"` to `source-directories`.
- **Create** `frontend/src/MarkdownRender.elm` — parse + body render (heading slug ids) + active TOC walker. Returns `Render.RenderOutput`.
- **Create** `frontend/tests/MarkdownRenderTest.elm` — unit tests.
- **Modify** `frontend/src/View.elm` — `Language.Markdown` branch in `previewBody` (`:357`) and `readerView` (`:101`).

No changes to Rust, `index.html`, or `Main.elm` (the `Render.ScrollTo` handler already exists at `Main.elm:187`).

---

## Task 1: Vendor the elm-markdown library

**Files:**
- Create: `frontend/elm-markdown/Markdown.elm`, `frontend/elm-markdown/Markdown/{Config,Block,InlineParser,Inline,TableOfContents,Helpers,Entity}.elm`
- Modify: `frontend/elm.json:3-6` (source-directories)

- [ ] **Step 1: Copy the 8 vendored modules**

```bash
cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer/frontend"
cp -R "/Users/carlson/dev/elm-work/scripta/scripta-app-v4/frontend/elm-markdown" ./elm-markdown
ls elm-markdown elm-markdown/Markdown
```

Expected: `Markdown.elm` at top level and `Config.elm Block.elm InlineParser.elm Inline.elm TableOfContents.elm Helpers.elm Entity.elm` under `Markdown/`. If `cp` brought extra files (e.g. a stray `elm-stuff`), remove them so only the 8 `.elm` modules remain.

- [ ] **Step 2: Register the source directory**

Edit `frontend/elm.json` `source-directories` to add `"elm-markdown"`:

```json
    "source-directories": [
        "src",
        "scripta-compiler",
        "elm-markdown"
    ],
```

- [ ] **Step 3: Verify the library compiles against the app's deps**

Run:
```bash
cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer/frontend"
elm make elm-markdown/Markdown/TableOfContents.elm --output=/dev/null && elm make elm-markdown/Markdown.elm --output=/dev/null
```
Expected: both compile with `Success!` (no missing-package or import errors). `TableOfContents.elm` transitively pulls in `Block`, `Inline`, `InlineParser`, `Config`, `Helpers`, `Entity`, confirming the whole library type-checks with the existing `elm.json` dependencies. If `elm` reports a missing package, STOP — the spec's "no new deps" assumption is wrong and needs revisiting.

- [ ] **Step 4: Commit**

```bash
cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer"
git add frontend/elm-markdown frontend/elm.json
git commit -m "feat: vendor elm-markdown library for markdown rendering"
```

---

## Task 2: MarkdownRender — body rendering with heading slug ids

**Files:**
- Create: `frontend/src/MarkdownRender.elm`
- Test: `frontend/tests/MarkdownRenderTest.elm`

This task implements `render` with body rendering only; the TOC stays `[]` until Task 3.

- [ ] **Step 1: Write the failing test**

Create `frontend/tests/MarkdownRenderTest.elm`:

```elm
module MarkdownRenderTest exposing (suite)

import Expect
import Html
import MarkdownRender
import Render
import Test exposing (Test, describe, test)
import Test.Html.Event as Event
import Test.Html.Query as Query
import Test.Html.Selector as Selector


suite : Test
suite =
    describe "MarkdownRender"
        [ test "renders a level-1 heading as an h1 carrying a slug id" <|
            \_ ->
                MarkdownRender.render "# Hello World"
                    |> .body
                    |> Html.div []
                    |> Query.fromHtml
                    |> Query.find [ Selector.tag "h1" ]
                    |> Query.has [ Selector.id "hello-world" ]
        ]
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer/frontend" && elm-test tests/MarkdownRenderTest.elm
```
Expected: FAIL — compile error, `MarkdownRender` module does not exist yet.

- [ ] **Step 3: Create the MarkdownRender module (body only)**

Create `frontend/src/MarkdownRender.elm`:

```elm
module MarkdownRender exposing (render)

{-| Render extended-Markdown source to the shared `Render.RenderOutput` shape.
Math is emitted as `<math-text>` custom elements (handled by the existing KaTeX
wiring in index.html). Headings carry slug ids so the TOC can scroll to them.
-}

import Html exposing (Html)
import Html.Attributes exposing (id, style)
import Markdown.Block as Block exposing (Block(..))
import Markdown.Inline as Inline
import Markdown.TableOfContents as ToC
import Render


render : String -> Render.RenderOutput
render source =
    let
        blocks =
            Block.parse Nothing source

        body =
            List.indexedMap markdownBlockToHtmlIndexed blocks
                |> List.concat
    in
    { title = Html.text ""
    , body =
        [ Html.div
            [ style "padding-left" "1em", style "padding-right" "1em" ]
            body
        ]
    , toc = []
    }


{-| Render one markdown block. Headings get an `h1..h6` with a slug `id`
(matching `ToC.headingId`); everything else defers to `Block.defaultHtml`.
The output is statically typed `Html msg` (no event handlers), so it unifies
with `Html Render.RenderMsg` at the call site.
-}
markdownBlockToHtmlIndexed : Int -> Block b i -> List (Html msg)
markdownBlockToHtmlIndexed index block =
    case block of
        Heading _ lvl inlines ->
            let
                headingText =
                    Inline.extractText inlines

                idAttr =
                    id (ToC.headingId headingText)

                topMargin =
                    if index == 0 then
                        style "margin-top" "0"

                    else
                        style "margin-top" "1em"

                hElement =
                    case lvl of
                        1 ->
                            Html.h1

                        2 ->
                            Html.h2

                        3 ->
                            Html.h3

                        4 ->
                            Html.h4

                        5 ->
                            Html.h5

                        _ ->
                            Html.h6
            in
            [ hElement [ idAttr, topMargin ] (List.map Inline.toHtml inlines) ]

        _ ->
            Block.defaultHtml (Just markdownBlockToHtml) Nothing block


markdownBlockToHtml : Block b i -> List (Html msg)
markdownBlockToHtml block =
    markdownBlockToHtmlIndexed 1 block
```

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer/frontend" && elm-test tests/MarkdownRenderTest.elm
```
Expected: PASS (1 test).

- [ ] **Step 5: Commit**

```bash
cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer"
git add frontend/src/MarkdownRender.elm frontend/tests/MarkdownRenderTest.elm
git commit -m "feat: render markdown body with heading slug ids"
```

---

## Task 3: MarkdownRender — active TOC

**Files:**
- Modify: `frontend/src/MarkdownRender.elm`
- Test: `frontend/tests/MarkdownRenderTest.elm`

Build the TOC with `ToC.fromBlocks`, gate it on `ToC.size > 1`, and render a custom walker whose entries emit `Render.ScrollTo (slug)` on click (instead of v4's native `<a href="#slug">`), so clicks route through the same port path as the Scripta reader TOC.

- [ ] **Step 1: Write the failing tests**

Add these three tests to the `describe "MarkdownRender"` list in `frontend/tests/MarkdownRenderTest.elm` (after the existing test):

```elm
        , test "builds a TOC when there is more than one heading" <|
            \_ ->
                MarkdownRender.render "# One\n\n# Two"
                    |> .toc
                    |> List.isEmpty
                    |> Expect.equal False
        , test "omits the TOC when there is at most one heading" <|
            \_ ->
                MarkdownRender.render "# Only\n\nsome body text"
                    |> .toc
                    |> List.isEmpty
                    |> Expect.equal True
        , test "a TOC entry click produces ScrollTo with the heading slug" <|
            \_ ->
                MarkdownRender.render "# Hello World\n\n# Second"
                    |> .toc
                    |> Html.div []
                    |> Query.fromHtml
                    |> Query.findAll [ Selector.tag "span" ]
                    |> Query.index 0
                    |> Event.simulate Event.click
                    |> Event.expect (Render.ScrollTo "hello-world")
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:
```bash
cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer/frontend" && elm-test tests/MarkdownRenderTest.elm
```
Expected: 2 FAIL — "builds a TOC…" (toc is currently always `[]`, so `List.isEmpty` is `True`, not `False`) and "a TOC entry click…" (no `span` to find). "omits the TOC…" passes trivially. (If the click test reports a compile error about `Query.index`, it is `Test.Html.Query.index : Int -> Multiple msg -> Single msg`.)

- [ ] **Step 3: Add the TOC builder and walker**

In `frontend/src/MarkdownRender.elm`, update the imports and `render`, and add the walker.

Change the import line for `TableOfContents` to expose the `ToCItem(..)` constructor, and add `Html.Events`:

```elm
import Html.Events
import Markdown.TableOfContents as ToC exposing (ToCItem(..))
```

Replace the `let … in` body of `render` with:

```elm
    let
        blocks =
            Block.parse Nothing source

        tocItems =
            ToC.fromBlocks blocks

        toc =
            if ToC.size tocItems > 1 then
                tocHtml tocItems

            else
                []

        body =
            List.indexedMap markdownBlockToHtmlIndexed blocks
                |> List.concat
    in
    { title = Html.text ""
    , body =
        [ Html.div
            [ style "padding-left" "1em", style "padding-right" "1em" ]
            body
        ]
    , toc = toc
    }
```

Add the walker functions (at the end of the module):

```elm
{-| Render the TOC tree. Each entry is a clickable `span` that emits
`Render.ScrollTo slug` — routed through `GotRenderMsg` to the
`scrollAndHighlight` port (same path as the Scripta reader TOC).
-}
tocHtml : List ToCItem -> List (Html Render.RenderMsg)
tocHtml items =
    [ Html.ul [ style "list-style" "none", style "padding-left" "0", style "margin" "0" ]
        (List.map tocItemView items)
    ]


tocItemView : ToCItem -> Html Render.RenderMsg
tocItemView (Item _ str kids) =
    let
        link =
            Html.span
                [ Html.Events.onClick (Render.ScrollTo (ToC.headingId str))
                , style "cursor" "pointer"
                , style "color" "#2563eb"
                ]
                [ Html.text str ]
    in
    if List.isEmpty kids then
        Html.li [] [ link ]

    else
        Html.li []
            [ link
            , Html.ul [ style "list-style" "none", style "padding-left" "1em", style "margin" "0" ]
                (List.map tocItemView kids)
            ]
```

- [ ] **Step 4: Run the tests to verify they pass**

Run:
```bash
cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer/frontend" && elm-test tests/MarkdownRenderTest.elm
```
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer"
git add frontend/src/MarkdownRender.elm frontend/tests/MarkdownRenderTest.elm
git commit -m "feat: active TOC for markdown (ScrollTo on click)"
```

---

## Task 4: Wire markdown into View

**Files:**
- Modify: `frontend/src/View.elm:357-372` (`previewBody`), `frontend/src/View.elm:101-149` (`readerView`)

Add a `Language.Markdown` branch to each. `previewBody` renders body only (no TOC column in split view, matching Scripta). `readerView` renders body plus a TOC column, reusing the existing column markup and the "non-empty TOC → show column" rule.

- [ ] **Step 1: Add the import**

Ensure `frontend/src/View.elm` imports `MarkdownRender`. Add near the other module imports:

```elm
import MarkdownRender
```

- [ ] **Step 2: Add the Markdown branch to `previewBody`**

In `previewBody` (`:357`), insert a branch BEFORE the catch-all `( Just lang, _ )` branch so markdown is handled before "not yet supported":

```elm
        ( Just Language.Markdown, _ ) ->
            MarkdownRender.render model.content
                |> .body
                |> List.map (Html.map (\_ -> NoOpFromRender))
```

The resulting `previewBody` reads:

```elm
previewBody : Model -> List (Html Msg)
previewBody model =
    case ( model.language, model.parsedDoc ) of
        ( Just Language.Scripta, Just doc ) ->
            let
                out =
                    Render.renderDocument model.isLight model.contentWidth doc
            in
            (out.title :: out.body)
                |> List.map (Html.map (\_ -> NoOpFromRender))

        ( Just Language.Markdown, _ ) ->
            MarkdownRender.render model.content
                |> .body
                |> List.map (Html.map (\_ -> NoOpFromRender))

        ( Just lang, _ ) ->
            [ Html.text (Language.label lang ++ " rendering is not yet supported.") ]

        ( Nothing, _ ) ->
            [ Html.text "Open a .scripta file." ]
```

- [ ] **Step 3: Add the Markdown branch to `readerView`**

In `readerView` (`:101`), the `( bodyContent, tocCols )` case currently has a `( Just Language.Scripta, Just doc )` branch and a `_` fallback. Add a `Language.Markdown` branch between them that mirrors the Scripta branch's structure (body mapped to `NoOpFromRender`; TOC column mapped via `GotRenderMsg`, shown only when the TOC is non-empty). Use the SAME column `div` attributes as the Scripta branch (width 220px, left border, padding, overflow):

```elm
                        ( Just Language.Markdown, _ ) ->
                            let
                                out =
                                    MarkdownRender.render model.content

                                bodyHtml =
                                    out.body
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
```

Place this branch immediately after the existing `( Just Language.Scripta, Just doc ) -> … ( bodyHtml, tocCol )` branch and before the `_ -> ( previewBody model, [] )` fallback.

- [ ] **Step 4: Verify the frontend builds and all tests pass**

Run:
```bash
cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer/frontend" && elm make src/Main.elm --output=/dev/null && elm-test
```
Expected: `Success!` from `elm make`, and all elm-test suites pass (including the 4 `MarkdownRender` tests).

- [ ] **Step 5: Manual verification**

Build and run the app (`make build` then launch, or the project's dev-run), open a vault containing a `.md` file with: multiple `#`/`##` headings, an inline `$a^2+b^2=c^2$`, and a display `$$\int_0^1 x\,dx$$`. Verify:
- The markdown body renders (previously showed "Markdown rendering is not yet supported.").
- Math renders via KaTeX.
- In Reader mode, a TOC column appears (when ≥2 headings) listing the headings.
- Clicking a TOC entry smooth-scrolls to the heading and briefly highlights it (`.toc-sync-highlight`).

- [ ] **Step 6: Commit**

```bash
cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer"
git add frontend/src/View.elm
git commit -m "feat: render markdown files in preview + reader-mode active TOC"
```

---

## After All Tasks

- Dispatch a final code review over the full diff (vendored library excluded from style nitpicks — it is a verbatim third-party copy).
- Then use superpowers:finishing-a-development-branch to complete the work.

## Notes / Known Limitation

Markdown headings use slug ids (`hello-world`), not Scripta's line-keyed `N-I`/`e-N.T` ids, so Ctrl-S left→right cursor sync (`index.html:250`) cannot locate markdown blocks — expected and documented in the spec. TOC navigation works fully.
