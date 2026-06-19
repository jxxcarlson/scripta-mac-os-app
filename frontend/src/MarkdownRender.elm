module MarkdownRender exposing (render)

{-| Render extended-Markdown source to the shared `Render.RenderOutput` shape.
Math is emitted as `<math-text>` custom elements (handled by the existing KaTeX
wiring in index.html). Headings carry slug ids so the TOC can scroll to them.
-}

import Html exposing (Html)
import Html.Attributes exposing (id, style)
import Html.Events
import Markdown.Block as Block exposing (Block(..))
import Markdown.Inline as Inline
import Markdown.TableOfContents as ToC exposing (ToCItem(..))
import Render


render : String -> Render.RenderOutput
render source =
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
            [ style "padding-left" "1em"
            , style "padding-right" "1em"

            -- Match Scripta's body leading (Render/Block.elm uses line-height 1.5).
            , style "line-height" "1.5"
            ]
            body
        ]
    , toc = toc
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

                -- Match Scripta's section sizing/weight (Render/OrdinaryBlock.elm
                -- renderSection): level 1 → h2, 2 → h3, 3 → h4, deeper → h5, with
                -- the default (non-bold) section font-weight.
                hElement =
                    case lvl of
                        1 ->
                            Html.h2

                        2 ->
                            Html.h3

                        3 ->
                            Html.h4

                        _ ->
                            Html.h5
            in
            [ hElement
                [ idAttr, topMargin, style "font-weight" "normal" ]
                (List.map Inline.toHtml inlines)
            ]

        _ ->
            Block.defaultHtml (Just markdownBlockToHtml) Nothing block


markdownBlockToHtml : Block b i -> List (Html msg)
markdownBlockToHtml block =
    -- Nested blocks are never the document's first element, so index 1
    -- (not 0) — they always get the normal top margin.
    markdownBlockToHtmlIndexed 1 block


{-| Render the TOC tree. Each entry is a clickable `span` that emits
`Render.ScrollTo slug` — routed through `GotRenderMsg` to the
`scrollAndHighlight` port (same path as the Scripta reader TOC).
-}
ulStyle : String -> List (Html.Attribute msg)
ulStyle paddingLeft =
    [ style "list-style" "none", style "padding-left" paddingLeft, style "margin" "0" ]


tocHtml : List ToCItem -> List (Html Render.RenderMsg)
tocHtml items =
    [ Html.ul (ulStyle "0")
        (List.map tocItemView items)
    ]


tocItemView : ToCItem -> Html Render.RenderMsg
tocItemView (Item _ str kids) =
    let
        link =
            Html.span
                [ Html.Events.onClick (Render.ScrollTo (ToC.headingId str))
                , style "cursor" "pointer"
                , style "color" "var(--link)"
                ]
                [ Html.text str ]
    in
    if List.isEmpty kids then
        Html.li [] [ link ]

    else
        Html.li []
            [ link
            , Html.ul (ulStyle "1em")
                (List.map tocItemView kids)
            ]
