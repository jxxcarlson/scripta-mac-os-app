module MarkdownRender exposing (LinkKind(..), classifyLink, render)

{-| Render extended-Markdown source to the shared `Render.RenderOutput` shape.
Math is emitted as `<math-text>` custom elements (handled by the existing KaTeX
wiring in index.html). Headings carry slug ids so the TOC can scroll to them.
-}

import Html exposing (Html)
import Html.Attributes exposing (id, style)
import Html.Events
import Json.Decode as D
import Markdown.Block as Block exposing (Block(..))
import Markdown.Inline as Inline exposing (Inline(..))
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


type LinkKind
    = Web
    | Anchor
    | Navigate
    | External


{-| Classify a markdown link href. Relative `.md`/`.scripta` targets and bare
folders navigate in-app; other relative targets (pdf, images, …) open externally.
-}
classifyLink : String -> LinkKind
classifyLink url =
    if
        String.startsWith "http://" url
            || String.startsWith "https://" url
            || String.startsWith "mailto:" url
    then
        Web

    else if String.startsWith "#" url then
        Anchor

    else if isDocTarget url then
        Navigate

    else
        External


{-| A relative target is a navigable document if it ends in `.md`/`.scripta`,
or has no file extension in its last path segment (treated as a folder).
-}
isDocTarget : String -> Bool
isDocTarget url =
    let
        lower =
            String.toLower url

        lastSeg =
            url |> String.split "/" |> List.reverse |> List.head |> Maybe.withDefault url
    in
    String.endsWith ".md" lower
        || String.endsWith ".scripta" lower
        || not (String.contains "." lastSeg)


{-| Render markdown inlines, intercepting Link inlines so file/web links open
externally instead of navigating the webview. Recurses with itself so links
nested inside emphasis are also intercepted.
-}
inlineRenderer : Inline i -> Html Render.RenderMsg
inlineRenderer inline =
    case inline of
        Link url _ inlines ->
            let
                children =
                    List.map inlineRenderer inlines
            in
            case classifyLink url of
                Web ->
                    Html.a [ Html.Attributes.href url, onClickPreventDefault (Render.OpenUrl url) ] children

                Navigate ->
                    Html.a [ Html.Attributes.href url, onClickPreventDefault (Render.NavigateToFile url) ] children

                External ->
                    Html.a [ Html.Attributes.href url, onClickPreventDefault (Render.OpenLocalFile url) ] children

                Anchor ->
                    Html.a [ Html.Attributes.href url ] children

        _ ->
            Inline.defaultHtml (Just inlineRenderer) inline


onClickPreventDefault : Render.RenderMsg -> Html.Attribute Render.RenderMsg
onClickPreventDefault msg =
    Html.Events.preventDefaultOn "click" (D.succeed ( msg, True ))


{-| Render one markdown block. Headings get an `h1..h6` with a slug `id`
(matching `ToC.headingId`); everything else defers to `Block.defaultHtml`.
-}
markdownBlockToHtmlIndexed : Int -> Block b i -> List (Html Render.RenderMsg)
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
                (List.map inlineRenderer inlines)
            ]

        _ ->
            Block.defaultHtml (Just markdownBlockToHtml) (Just inlineRenderer) block


markdownBlockToHtml : Block b i -> List (Html Render.RenderMsg)
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
