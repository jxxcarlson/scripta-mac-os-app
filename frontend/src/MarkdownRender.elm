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
