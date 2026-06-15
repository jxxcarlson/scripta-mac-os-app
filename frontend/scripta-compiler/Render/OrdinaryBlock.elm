module Render.OrdinaryBlock exposing (render)

{-| Render ordinary (named) blocks to HTML.
-}

import Char
import Dict exposing (Dict)
import Either exposing (Either(..))
import Html exposing (Html)
import Html.Attributes as HA
import Html.Events as HE
import Json.Decode as Decode
import Render.Constants
import Render.Expression
import Render.Sizing
import Render.Utility exposing (blockIdAndStyle, idAttr)
import V3.Types exposing (Accumulator, CompilerParameters, Expr(..), Expression, ExpressionBlock, Msg(..), TermLoc, Theme(..))


{-| Render an ordinary block by name.
-}
render : CompilerParameters -> Accumulator -> String -> ExpressionBlock -> List (Html Msg) -> List (Html Msg)
render params acc name block children =
    case Dict.get name blockDict of
        Just renderer ->
            renderer params acc name block children

        Nothing ->
            renderDefault params acc name block children


{-| Dictionary of block renderers.
-}
blockDict : Dict String (CompilerParameters -> Accumulator -> String -> ExpressionBlock -> List (Html Msg) -> List (Html Msg))
blockDict =
    Dict.fromList
        [ ( "section", renderSection )
        , ( "subsection", renderSubsection )
        , ( "subsubsection", renderSubsubsection )
        , ( "item", renderItem )
        , ( "itemList", renderItemList )
        , ( "numbered", renderNumbered )
        , ( "numberedList", renderNumberedList )
        , ( "theorem", renderTheorem )
        , ( "lemma", renderTheorem )
        , ( "proposition", renderTheorem )
        , ( "corollary", renderTheorem )
        , ( "definition", renderTheorem )
        , ( "example", renderTheorem )
        , ( "remark", renderTheorem )
        , ( "note", renderTheorem )
        , ( "exercise", renderTheorem )
        , ( "problem", renderTheorem )
        , ( "question", renderTheorem )
        , ( "axiom", renderTheorem )
        , ( "proof", renderProof )
        , ( "indent", renderIndent )
        , ( "quotation", renderQuotation )
        , ( "quote", renderQuotation )
        , ( "center", renderCenter )
        , ( "abstract", renderAbstract )
        , ( "title", renderTitle )
        , ( "subtitle", renderSubtitle )
        , ( "author", renderAuthor )
        , ( "date", renderDate )
        , ( "contents", renderContents )
        , ( "index", renderIndexBlock )
        , ( "box", renderBox )
        , ( "comment", renderComment )
        , ( "hide", renderComment )
        , ( "document", renderDocument )
        , ( "collection", renderCollection )

        -- Tables and lists
        , ( "table", renderXTable )
        , ( "desc", renderDesc )

        -- Footnotes
        , ( "endnotes", renderEndnotes )

        -- New blocks
        , ( "paragraph", renderParagraph )

        -- Additional blocks from V2
        , ( "subheading", renderSubheading )
        , ( "sh", renderSubheading )
        , ( "compact", renderCompact )
        , ( "identity", renderIdentity )
        , ( "red", renderColorBlock "red" )
        , ( "red2", renderColorBlock "#c00" )
        , ( "blue", renderColorBlock "blue" )
        , ( "q", renderQuestion )
        , ( "a", renderAnswer )
        , ( "reveal", renderReveal )
        , ( "more", renderReveal )
        , ( "book", renderNothing )
        , ( "chapter", renderChapter )
        , ( "section*", renderUnnumberedSection )
        , ( "visibleBanner", renderVisibleBanner )
        , ( "banner", renderNothing )
        , ( "runninghead_", renderNothing )
        , ( "tags", renderNothing )
        , ( "type", renderNothing )
        , ( "setcounter", renderNothing )
        , ( "shiftandsetcounter", renderNothing )
        , ( "bibliography", renderBibliography )
        , ( "bibitem", renderBibitem )
        , ( "env", renderEnv )
        ]


{-| Default rendering for unknown block names.
-}
renderDefault : CompilerParameters -> Accumulator -> String -> ExpressionBlock -> List (Html Msg) -> List (Html Msg)
renderDefault params acc name block children =
    [ Html.div
        (blockIdAndStyle block
            ++ [ HA.style "margin-bottom" (Render.Sizing.paragraphSpacingPx params.sizing)
               , HA.style "margin-left" (Render.Sizing.marginLeftPx params.sizing)
               , HA.style "margin-right" (Render.Sizing.marginRightPx params.sizing)
               ]
            ++ Render.Utility.rlBlockSync block.meta
        )
        (Html.span [ HA.style "font-weight" "bold", HA.style "color" "blue" ]
            [ Html.text ("[" ++ name ++ "]") ]
            :: renderBody params acc block
            ++ children
        )
    ]


{-| Render block body content.
-}
renderBody : CompilerParameters -> Accumulator -> ExpressionBlock -> List (Html Msg)
renderBody params acc block =
    case block.body of
        Left _ ->
            []

        Right expressions ->
            Render.Expression.renderList params acc expressions



-- SECTION HEADINGS


{-| Render a numbered section heading.

    | section
    Introduction

    | section 2
    Background

The argument specifies heading level (1-3, default 1).

-}
renderSection : CompilerParameters -> Accumulator -> String -> ExpressionBlock -> List (Html Msg) -> List (Html Msg)
renderSection params acc _ block children =
    let
        level =
            Dict.get "level" block.properties |> Maybe.andThen String.toInt |> Maybe.withDefault 1

        tag =
            case level of
                1 ->
                    Html.h2

                2 ->
                    Html.h3

                3 ->
                    Html.h4

                _ ->
                    Html.h5

        -- Get number-to-level from accumulator's keyValueDict (set by title block)
        numberToLevel =
            Dict.get "number-to-level" acc.keyValueDict
                |> Maybe.andThen String.toInt
                |> Maybe.withDefault 0

        -- Get the section label (set by transformBlock in Acc.elm)
        sectionLabel =
            Dict.get "label" block.properties |> Maybe.withDefault ""

        -- Only show section number if level <= numberToLevel
        prefix =
            if level <= numberToLevel && sectionLabel /= "" then
                sectionLabel ++ ". "

            else
                ""

        -- Generate slug from heading text
        slug =
            getBlockText block |> toSlug
    in
    [ Html.div
        [ HA.id slug ]
        (tag
            (blockIdAndStyle block
                ++ [ HA.style "font-weight" "normal"
                   , HA.style "margin-top" "1.5em"
                   , if level > 2 then
                        HA.style "font-style" "italic"

                     else
                        HA.style "font-style" "normal"
                   , HA.style "margin-bottom" "0.5em"
                   ]
                ++ Render.Utility.rlBlockSync block.meta
            )
            (Html.text prefix :: renderBody params acc block)
            :: children
        )
    ]


{-| Render a subsection heading (level 2).

    | subsection
    Methods

-}
renderSubsection : CompilerParameters -> Accumulator -> String -> ExpressionBlock -> List (Html Msg) -> List (Html Msg)
renderSubsection params acc _ block children =
    let
        slug =
            getBlockText block |> toSlug
    in
    [ Html.div
        [ HA.id slug ]
        (Html.h3
            (blockIdAndStyle block ++ Render.Utility.rlBlockSync block.meta)
            (renderBody params acc block)
            :: children
        )
    ]


{-| Render a subsubsection heading (level 3).

    | subsubsection
    Details

-}
renderSubsubsection : CompilerParameters -> Accumulator -> String -> ExpressionBlock -> List (Html Msg) -> List (Html Msg)
renderSubsubsection params acc _ block children =
    let
        slug =
            getBlockText block |> toSlug
    in
    [ Html.div
        [ HA.id slug ]
        (Html.h4
            (blockIdAndStyle block ++ Render.Utility.rlBlockSync block.meta)
            (renderBody params acc block)
            :: children
        )
    ]



-- LIST ITEMS


{-| Render a single bullet list item.

    - First item
    - Second item

Uses flexbox so subsequent lines align with the first character after the bullet.

-}
renderItem : CompilerParameters -> Accumulator -> String -> ExpressionBlock -> List (Html Msg) -> List (Html Msg)
renderItem params acc _ block children =
    let
        -- Items with children don't need margin-bottom (last child provides it)
        marginBottom =
            if List.isEmpty children then
                Render.Sizing.itemSpacingPx params.sizing

            else
                "0px"

        -- Wrap children with margin-top to space them from parent content
        wrappedChildren =
            if List.isEmpty children then
                []

            else
                [ Html.div
                    [ HA.style "margin-top" (Render.Sizing.itemSpacingPx params.sizing) ]
                    children
                ]
    in
    [ Html.div
        (blockIdAndStyle block
            ++ [ HA.style "display" "flex"
               , HA.style "margin-left" "0px"
               , HA.style "margin-bottom" marginBottom
               ]
            ++ Render.Utility.rlBlockSync block.meta
        )
        [ Html.span
            [ HA.style "flex-shrink" "0"
            , HA.style "width" "1.5em"
            ]
            [ Html.text "•" ]
        , Html.div []
            (renderBody params acc block ++ wrappedChildren)
        ]
    ]


{-| Render a single numbered list item.

    . First item
    . Second item

Uses flexbox so subsequent lines align with the first character after the number.

-}
renderNumbered : CompilerParameters -> Accumulator -> String -> ExpressionBlock -> List (Html Msg) -> List (Html Msg)
renderNumbered params acc _ block children =
    let
        index =
            case Dict.get block.meta.id acc.numberedItemDict of
                Just info ->
                    formatListIndex info.level info.index

                Nothing ->
                    ""

        -- Items with children don't need margin-bottom (last child provides it)
        marginBottom =
            if List.isEmpty children then
                Render.Sizing.itemSpacingPx params.sizing

            else
                "0px"

        -- Wrap children with margin-top to space them from parent content
        wrappedChildren =
            if List.isEmpty children then
                []

            else
                [ Html.div
                    [ HA.style "margin-top" (Render.Sizing.itemSpacingPx params.sizing) ]
                    children
                ]
    in
    [ Html.div
        (blockIdAndStyle block
            ++ [ HA.style "display" "flex"
               , HA.style "margin-left" "0px"
               , HA.style "margin-bottom" marginBottom
               ]
            ++ Render.Utility.rlBlockSync block.meta
        )
        [ Html.span
            [ HA.style "flex-shrink" "0"
            , HA.style "width" "1.5em"
            ]
            [ Html.text index ]
        , Html.div []
            (renderBody params acc block ++ wrappedChildren)
        ]
    ]


{-| Render a bullet list (coalesced from consecutive "- " items).

    - First item
    - Second item
    - Third item

-}
renderItemList : CompilerParameters -> Accumulator -> String -> ExpressionBlock -> List (Html Msg) -> List (Html Msg)
renderItemList params acc _ block children =
    [ Html.ul
        (blockIdAndStyle block
            ++ [ HA.style "margin-left" "0px"
               , HA.style "padding-left" "1.5em"
               , HA.style "margin-bottom" (Render.Sizing.paragraphSpacingPx params.sizing)
               ]
            ++ Render.Utility.rlBlockSync block.meta
        )
        (renderListItems params acc BulletList block ++ children)
    ]


{-| Render a numbered list (coalesced from consecutive ". " items).

    . First item
    . Second item
    . Third item

-}
renderNumberedList : CompilerParameters -> Accumulator -> String -> ExpressionBlock -> List (Html Msg) -> List (Html Msg)
renderNumberedList params acc _ block children =
    [ Html.ol
        (blockIdAndStyle block
            ++ [ HA.style "margin-left" "0px"
               , HA.style "padding-left" "1.5em"
               , HA.style "margin-bottom" (Render.Sizing.paragraphSpacingPx params.sizing)
               , HA.style "list-style-type" "decimal"
               ]
            ++ Render.Utility.rlBlockSync block.meta
        )
        (renderListItems params acc NumberedList block ++ children)
    ]


{-| List type for rendering (bullet or numbered).
-}
type ListType
    = BulletList
    | NumberedList


{-| Render each ExprList in the body as a list item, handling nesting.
-}
renderListItems : CompilerParameters -> Accumulator -> ListType -> ExpressionBlock -> List (Html Msg)
renderListItems params acc listType block =
    case block.body of
        Right expressions ->
            renderNestedListItems params acc listType 0 expressions

        Left _ ->
            []


{-| Render a nested list of items. Items with higher indent become children of the preceding item.
The depth parameter tracks nesting level for numbering style (0 = top level).
-}
renderNestedListItems : CompilerParameters -> Accumulator -> ListType -> Int -> List Expression -> List (Html Msg)
renderNestedListItems params acc listType depth expressions =
    case expressions of
        [] ->
            []

        first :: rest ->
            let
                firstIndent =
                    getExprIndent first

                -- Collect children (items with indent > firstIndent) and remaining siblings
                ( children, siblings ) =
                    collectChildren firstIndent rest

                -- Render children as nested list if any
                nestedList =
                    if List.isEmpty children then
                        []

                    else
                        let
                            listTag =
                                case listType of
                                    BulletList ->
                                        Html.ul

                                    NumberedList ->
                                        Html.ol

                            -- For numbered lists, set list-style-type based on depth
                            listStyleType =
                                case listType of
                                    BulletList ->
                                        "disc"

                                    NumberedList ->
                                        case modBy 3 (depth + 1) of
                                            0 ->
                                                "decimal"

                                            1 ->
                                                "lower-alpha"

                                            _ ->
                                                "lower-roman"
                        in
                        [ listTag
                            [ HA.style "margin-left" "0px"
                            , HA.style "padding-left" "1.5em"
                            , HA.style "margin-top" "0px"
                            , HA.style "margin-bottom" "0px"
                            , HA.style "list-style-type" listStyleType
                            ]
                            (renderNestedListItems params acc listType (depth + 1) children)
                        ]

                -- Render the current item with its children
                renderedItem =
                    renderListItemWithChildren params acc first nestedList
            in
            renderedItem :: renderNestedListItems params acc listType depth siblings


{-| Collect consecutive items that are children (higher indent) of the current item.
Returns (children, remaining siblings).
-}
collectChildren : Int -> List Expression -> ( List Expression, List Expression )
collectChildren parentIndent items =
    let
        isChild expr =
            getExprIndent expr > parentIndent
    in
    case items of
        [] ->
            ( [], [] )

        first :: rest ->
            if isChild first then
                let
                    ( moreChildren, siblings ) =
                        collectChildren parentIndent rest
                in
                ( first :: moreChildren, siblings )

            else
                ( [], items )


{-| Get the indent from an expression (ExprList stores indent as first param).
-}
getExprIndent : Expression -> Int
getExprIndent expr =
    case expr of
        ExprList indent _ _ ->
            indent

        _ ->
            0


{-| Render a single list item with optional nested children.
-}
renderListItemWithChildren : CompilerParameters -> Accumulator -> Expression -> List (Html Msg) -> Html Msg
renderListItemWithChildren params acc expr children =
    case expr of
        ExprList _ innerExprs meta ->
            Html.li [ HA.id meta.id ]
                (Render.Expression.renderList params acc innerExprs ++ children)

        _ ->
            Html.li [] (Render.Expression.renderList params acc [ expr ] ++ children)


{-| Format a list index based on nesting level.

  - Level 0: 1. 2. 3. (numbers)
  - Level 1: a. b. c. (lowercase letters)
  - Level 2: i. ii. iii. (lowercase roman numerals)
  - Level 3+: cycles back to numbers

-}
formatListIndex : Int -> Int -> String
formatListIndex level index =
    case modBy 3 level of
        0 ->
            String.fromInt index ++ "."

        1 ->
            indexToLetter index ++ "."

        _ ->
            indexToRoman index ++ "."


{-| Convert 1-based index to lowercase letter (a, b, c, ..., z, aa, ab, ...).
-}
indexToLetter : Int -> String
indexToLetter n =
    if n <= 0 then
        ""

    else if n <= 26 then
        String.fromChar (Char.fromCode (96 + n))

    else
        indexToLetter ((n - 1) // 26)
            ++ indexToLetter
                (modBy 26 n
                    |> (\x ->
                            if x == 0 then
                                26

                            else
                                x
                       )
                )


{-| Convert 1-based index to lowercase roman numeral.
-}
indexToRoman : Int -> String
indexToRoman n =
    let
        numerals =
            [ ( 1000, "m" )
            , ( 900, "cm" )
            , ( 500, "d" )
            , ( 400, "cd" )
            , ( 100, "c" )
            , ( 90, "xc" )
            , ( 50, "l" )
            , ( 40, "xl" )
            , ( 10, "x" )
            , ( 9, "ix" )
            , ( 5, "v" )
            , ( 4, "iv" )
            , ( 1, "i" )
            ]

        convert num =
            if num <= 0 then
                ""

            else
                case List.filter (\( v, _ ) -> v <= num) numerals |> List.head of
                    Just ( value, symbol ) ->
                        symbol ++ convert (num - value)

                    Nothing ->
                        ""
    in
    convert n



-- THEOREM-LIKE ENVIRONMENTS


{-| Render theorem-like environments with automatic numbering.

    | theorem
    Every even number greater than 2 is the sum of two primes.

    | theorem
    | title:Goldbach's Conjecture
    Every even number greater than 2 is the sum of two primes.

Supported environments: theorem, lemma, proposition, corollary, definition,
example, remark, note, exercise, problem, question, axiom.

Properties:

  - title: Optional title (e.g., "Goldbach's Conjecture")

-}
renderTheorem : CompilerParameters -> Accumulator -> String -> ExpressionBlock -> List (Html Msg) -> List (Html Msg)
renderTheorem params acc name block children =
    let
        theoremTitle =
            String.toUpper (String.left 1 name) ++ String.dropLeft 1 name

        -- Get the number from block.properties["label"] (set by Acc.transformBlock)
        numberString =
            case Dict.get "label" block.properties of
                Just label_ ->
                    if label_ /= "" then
                        " " ++ label_

                    else
                        ""

                Nothing ->
                    ""

        -- User-provided title (e.g., "Goldbach's Conjecture")
        userLabel =
            Dict.get "title" block.properties |> Maybe.withDefault ""

        labelDisplay =
            if userLabel /= "" then
                " " ++ userLabel ++ ":"

            else
                ""
    in
    [ Html.div
        ([ HA.style "margin-top" "1em"
         , HA.style "margin-bottom" "1em"
         , HA.style "padding" "12px"
         , HA.style "border-left" "3px solid #ccc"
         , HA.style "background-color"
            (case params.theme of
                Light ->
                    "#f9f9f9"

                Dark ->
                    "#2a2a2a"
            )
         ]
            ++ blockIdAndStyle block
            ++ Render.Utility.rlBlockSync block.meta
        )
        [ Html.span
            [ HA.style "font-weight" "600"
            ]
            [ Html.text (theoremTitle ++ numberString ++ ".") ]
        , Html.span
            [ HA.style "margin-right" "0.5em"
            ]
            [ Html.text labelDisplay ]
        , Html.span
            [ HA.style "font-style" "italic" ]
            (renderBody params acc block ++ children)
        ]
    ]


{-| Render a proof block with "Proof." prefix and QED marker.

    | proof
    By contradiction, assume...

-}
renderProof : CompilerParameters -> Accumulator -> String -> ExpressionBlock -> List (Html Msg) -> List (Html Msg)
renderProof params acc _ block children =
    [ Html.div
        (blockIdAndStyle block
            ++ [ HA.style "margin-top" "0.5em"
               , HA.style "margin-bottom" "1em"
               ]
            ++ Render.Utility.rlBlockSync block.meta
        )
        (Html.span [ HA.style "font-style" "italic", HA.style "margin-right" "0.5em" ]
            [ Html.text "Proof." ]
            :: renderBody params acc block
            ++ children
            ++ [ Html.span [ HA.style "float" "right" ] [ Html.text "∎" ] ]
        )
    ]



-- FORMATTING BLOCKS


{-| Render indented content.

    | indent
    This paragraph is indented.

-}
renderIndent : CompilerParameters -> Accumulator -> String -> ExpressionBlock -> List (Html Msg) -> List (Html Msg)
renderIndent params acc _ block children =
    [ Html.div
        (blockIdAndStyle block
            ++ [ HA.style "margin-left" "2em"
               , HA.style "padding-right" "2em"
               , HA.style "margin-bottom" "1em"
               ]
            ++ Render.Utility.rlBlockSync block.meta
        )
        (renderBody params acc block ++ children)
    ]


renderParagraph : CompilerParameters -> Accumulator -> String -> ExpressionBlock -> List (Html Msg) -> List (Html Msg)
renderParagraph params acc _ block children =
    let
        paddingRightInEms =
            (Dict.get "padding-right" block.properties |> Maybe.withDefault "0") ++ "em"
    in
    [ Html.div
        (blockIdAndStyle block
            ++ [ HA.style "margin-left" "2em"
               , HA.style "margin-bottom" "1em"
               , HA.style "padding-right" paddingRightInEms
               ]
            ++ Render.Utility.rlBlockSync block.meta
        )
        (renderBody params acc block ++ children)
    ]


{-| Render a block quotation with left border.

    | quotation
    To be or not to be, that is the question.

Also available as `| quote`.

-}
renderQuotation : CompilerParameters -> Accumulator -> String -> ExpressionBlock -> List (Html Msg) -> List (Html Msg)
renderQuotation params acc _ block children =
    [ Html.blockquote
        (blockIdAndStyle block
            ++ [ HA.style "border-left" "3px solid #ccc"
               , HA.style "padding-left" "12px"
               , HA.style "margin-left" (Render.Sizing.indentWithDeltaPx 1 block.indent params.sizing)
               , HA.style "margin-right" (Render.Sizing.marginRightWithDeltaPx 1 block.indent params.sizing)
               , HA.style "margin-bottom" (Render.Sizing.paragraphSpacingPx params.sizing)
               , HA.style "font-style" "italic"
               ]
            ++ Render.Utility.rlBlockSync block.meta
        )
        (renderBody params acc block ++ children)
    ]


renderXTable : CompilerParameters -> Accumulator -> String -> ExpressionBlock -> List (Html Msg) -> List (Html Msg)
renderXTable params acc _ block _ =
    let
        columnWidths =
            Dict.get "widths" block.properties
                |> Maybe.withDefault ""
                |> String.split ","
                |> List.map String.trim
                |> List.filterMap String.toInt

        formats =
            Dict.get "format" block.properties
                |> Maybe.withDefault ""
                |> String.toList
                |> List.map (String.fromChar >> formatToTextAlign)

        captionText =
            Dict.get "caption" block.properties

        tableNumber =
            Dict.get "table" block.properties

        captionLine =
            case ( tableNumber, captionText ) of
                ( Just n, Just cap ) ->
                    Just ("Table " ++ n ++ ". " ++ cap)

                ( Just n, Nothing ) ->
                    Just ("Table " ++ n)

                ( Nothing, Just cap ) ->
                    Just cap

                ( Nothing, Nothing ) ->
                    Nothing
    in
    case block.body of
        Right rows ->
            [ Html.div
                (blockIdAndStyle block
                    ++ [ HA.style "margin" "1em 0"
                       , HA.style "display" "flex"
                       , HA.style "flex-direction" "column"
                       , HA.style "align-items" "center"
                       ]
                    ++ Render.Utility.rlBlockSync block.meta
                )
                (Html.table [ HA.style "border-collapse" "collapse" ]
                    [ Html.tbody [] (List.map (renderXTableRow params acc columnWidths formats) rows) ]
                    :: (case captionLine of
                            Just text ->
                                [ Html.div
                                    [ HA.style "margin-top" "8px"
                                    , HA.style "font-style" "italic"
                                    , HA.style "font-size" "0.9em"
                                    ]
                                    [ Html.text text ]
                                ]

                            Nothing ->
                                []
                       )
                )
            ]

        Left data ->
            [ Html.div [ idAttr block.meta.id ] [ Html.text data ] ]


renderXTableRow : CompilerParameters -> Accumulator -> List Int -> List String -> Expression -> Html Msg
renderXTableRow params acc widths formats row =
    case row of
        ExprList _ cells _ ->
            Html.tr [ HA.style "height" "20px" ]
                (List.indexedMap (renderXTableCell params acc widths formats) cells)

        _ ->
            Html.tr [] []


renderXTableCell : CompilerParameters -> Accumulator -> List Int -> List String -> Int -> Expression -> Html Msg
renderXTableCell params acc widths formats index cell =
    case cell of
        ExprList _ exprs _ ->
            let
                widthStyle =
                    List.drop index widths
                        |> List.head
                        |> Maybe.map (\w -> [ HA.style "width" (String.fromInt w ++ "px") ])
                        |> Maybe.withDefault []

                alignStyle =
                    List.drop index formats
                        |> List.head
                        |> Maybe.map (\a -> [ HA.style "text-align" a ])
                        |> Maybe.withDefault []
            in
            Html.td
                ([ HA.style "padding" "4px 8px" ] ++ widthStyle ++ alignStyle)
                (Render.Expression.renderList params acc exprs)

        _ ->
            Html.td [] []


{-| Render centered content.

    | center
    Centered text here.

-}
renderCenter : CompilerParameters -> Accumulator -> String -> ExpressionBlock -> List (Html Msg) -> List (Html Msg)
renderCenter params acc _ block children =
    [ Html.div
        (blockIdAndStyle block
            ++ [ HA.style "text-align" "center"
               ]
            ++ Render.Utility.rlBlockSync block.meta
        )
        (renderBody params acc block ++ children)
    ]


{-| Render an abstract with "Abstract" heading.

    | abstract
    This paper presents a new method for...

-}
renderAbstract : CompilerParameters -> Accumulator -> String -> ExpressionBlock -> List (Html Msg) -> List (Html Msg)
renderAbstract params acc _ block children =
    [ Html.div
        (blockIdAndStyle block
            ++ [ HA.style "margin" "1em 2em"
               , HA.style "font-size" "0.9em"
               ]
            ++ Render.Utility.rlBlockSync block.meta
        )
        (Html.div [ HA.style "font-weight" "bold", HA.style "margin-bottom" "0.5em" ]
            [ Html.text "Abstract" ]
            :: renderBody params acc block
            ++ children
        )
    ]



-- DOCUMENT METADATA


{-| Render the document title (centered h1).

    | title
    My Document Title

-}
renderTitle : CompilerParameters -> Accumulator -> String -> ExpressionBlock -> List (Html Msg) -> List (Html Msg)
renderTitle _ _ _ _ _ =
    []


{-| Render the document subtitle (centered, lighter h2).

    | subtitle
    A Comprehensive Guide

-}
renderSubtitle : CompilerParameters -> Accumulator -> String -> ExpressionBlock -> List (Html Msg) -> List (Html Msg)
renderSubtitle params acc _ block _ =
    [ Html.h2
        (blockIdAndStyle block
            ++ [ HA.style "text-align" "center"
               , HA.style "font-weight" "normal"
               , HA.style "margin-top" "0"
               ]
        )
        (renderBody params acc block)
    ]


{-| Render the document author (centered).

    | author
    John Doe

-}
renderAuthor : CompilerParameters -> Accumulator -> String -> ExpressionBlock -> List (Html Msg) -> List (Html Msg)
renderAuthor params acc _ block _ =
    [ Html.div
        (blockIdAndStyle block
            ++ [ HA.style "text-align" "center"
               , HA.style "margin-top" "0.5em"
               ]
        )
        (renderBody params acc block)
    ]


{-| Render the document date (centered, smaller).

    | date
    January 2024

-}
renderDate : CompilerParameters -> Accumulator -> String -> ExpressionBlock -> List (Html Msg) -> List (Html Msg)
renderDate params acc _ block _ =
    [ Html.div
        (blockIdAndStyle block
            ++ [ HA.style "text-align" "center"
               , HA.style "margin-top" "0.25em"
               , HA.style "font-size" "0.9em"
               , HA.style "color" "#666"
               ]
        )
        (renderBody params acc block)
    ]



-- SPECIAL BLOCKS


{-| Render a table of contents placeholder.

    | contents

The actual TOC is built by Render.TOC.

-}
renderContents : CompilerParameters -> Accumulator -> String -> ExpressionBlock -> List (Html Msg) -> List (Html Msg)
renderContents _ _ _ block _ =
    [ Html.div
        [ idAttr block.meta.id
        , HA.id "toc-placeholder"
        ]
        []
    ]


{-| Render an index of all terms collected from [term ...] elements.

    | index

Displays an alphabetically sorted list of terms with links to their locations.

-}
renderIndexBlock : CompilerParameters -> Accumulator -> String -> ExpressionBlock -> List (Html Msg) -> List (Html Msg)
renderIndexBlock _ acc _ block _ =
    let
        -- Helper to get display text for sorting/grouping
        getDisplayText ( term, loc ) =
            loc.displayAs |> Maybe.withDefault term

        -- Get all terms sorted alphabetically by display text (case-insensitive)
        sortedTerms =
            acc.terms
                |> Dict.toList
                |> List.sortBy (\entry -> String.toLower (getDisplayText entry))

        -- Group terms by first letter of display text
        groupedTerms =
            groupByFirstLetterWithDisplay sortedTerms

        -- Render each group
        renderGroup ( letter, terms ) =
            Html.div
                [ HA.style "margin-bottom" "1em" ]
                [ Html.div
                    [ HA.style "font-weight" "bold"
                    , HA.style "font-size" "1.2em"
                    , HA.style "margin-bottom" "0.5em"
                    ]
                    [ Html.text (String.toUpper letter) ]
                , Html.div [] (List.map renderIndexEntry terms)
                ]

        -- Render a single index entry as a clickable link
        -- Uses displayAs if present, otherwise uses the term itself
        renderIndexEntry ( term, loc ) =
            let
                displayText =
                    loc.displayAs |> Maybe.withDefault term

                returnId =
                    block.meta.id ++ "::idx::" ++ term
            in
            Html.div
                [ HA.id returnId
                , HA.style "margin-left" "1em"
                , HA.style "margin-bottom" "0.25em"
                ]
                [ Html.a
                    [ HA.href ("#" ++ loc.id)
                    , HE.custom "click" (Decode.succeed { message = CitationClick { targetId = loc.id, returnId = returnId }, stopPropagation = True, preventDefault = True })
                    , HA.style "color" "#0066cc"
                    , HA.style "text-decoration" "none"
                    , HA.style "cursor" "pointer"
                    ]
                    [ Html.text displayText ]
                ]
    in
    [ Html.div
        [ idAttr block.meta.id ]
        [ Html.h2
            [ HA.style "font-weight" "normal"
            , HA.style "margin-bottom" "1em"
            ]
            [ Html.text "Index" ]
        , Html.div
            [ HA.style "column-count" "2"
            , HA.style "column-gap" "2em"
            ]
            (if List.isEmpty sortedTerms then
                [ Html.text "(No index entries)" ]

             else
                List.map renderGroup groupedTerms
            )
        ]
    ]


{-| Group terms by their first letter, using displayAs when present.
-}
groupByFirstLetterWithDisplay : List ( String, TermLoc ) -> List ( String, List ( String, TermLoc ) )
groupByFirstLetterWithDisplay terms =
    let
        getDisplayText ( term, loc ) =
            loc.displayAs |> Maybe.withDefault term

        getFirstLetter entry =
            String.left 1 (getDisplayText entry) |> String.toLower

        addToGroup entry groups =
            let
                letter =
                    getFirstLetter entry
            in
            case groups of
                [] ->
                    [ ( letter, [ entry ] ) ]

                ( currentLetter, currentTerms ) :: rest ->
                    if currentLetter == letter then
                        ( currentLetter, entry :: currentTerms ) :: rest

                    else
                        ( letter, [ entry ] ) :: groups
    in
    terms
        |> List.foldl addToGroup []
        |> List.map (\( letter, ts ) -> ( letter, List.reverse ts ))
        |> List.reverse


{-| Render content in a bordered box.

    | box
    Important notice here.

-}
renderBox : CompilerParameters -> Accumulator -> String -> ExpressionBlock -> List (Html Msg) -> List (Html Msg)
renderBox params acc _ block children =
    let
        title =
            Dict.get "title" block.properties |> Maybe.withDefault ""
    in
    [ Html.div [ HA.style "margin-left" "2.75em", HA.style "font-size" "1.15em" ] [ Html.text title ]
    , Html.div
        (blockIdAndStyle block
            ++ [ HA.style "border" "1px solid #ccc"
               , HA.style "padding" "1em"
               , HA.style "margin-left" "2.75em"
               , HA.style "margin-right" "5.5em"
               , HA.style "border-radius" "4px"
               , HA.style "background-color"
                    (case params.theme of
                        Light ->
                            "#f5f5f5"

                        Dark ->
                            "#1e1e1e"
                    )
               ]
            ++ Render.Utility.rlBlockSync block.meta
        )
        (renderBody params acc block ++ children)
    ]


{-| Render nothing (comments are hidden).

    | comment
    This won't appear in output.

Also available as `| hide`.

-}
renderComment : CompilerParameters -> Accumulator -> String -> ExpressionBlock -> List (Html Msg) -> List (Html Msg)
renderComment _ _ _ block _ =
    [ Html.div [ idAttr block.meta.id, HA.style "display" "none" ] [] ]


{-| Render document metadata block (hidden).

    | document
    type:article

-}
renderDocument : CompilerParameters -> Accumulator -> String -> ExpressionBlock -> List (Html Msg) -> List (Html Msg)
renderDocument _ _ _ block _ =
    [ Html.div [ idAttr block.meta.id, HA.style "display" "none" ] [] ]


{-| Render collection metadata block (hidden).

    | collection
    docs/chapter1.md
    docs/chapter2.md

-}
renderCollection : CompilerParameters -> Accumulator -> String -> ExpressionBlock -> List (Html Msg) -> List (Html Msg)
renderCollection _ _ _ block _ =
    [ Html.div [ idAttr block.meta.id, HA.style "display" "none" ] [] ]



-- TABLES


{-| Render a table with rows and cells.

    | table format:l c r columnWidths:[100,80,80]
    [table [row [cell A][cell B][cell C]] [row [cell 1][cell 2][cell 3]]]

Properties:

  - format: Column alignment (l=left, c=center, r=right)
  - columnWidths: Pixel widths for each column

-}
renderTable : CompilerParameters -> Accumulator -> String -> ExpressionBlock -> List (Html Msg) -> List (Html Msg)
renderTable params acc _ block _ =
    case block.body of
        Right [ Fun "table" rows _ ] ->
            let
                formatList =
                    Dict.get "format" block.properties
                        |> Maybe.withDefault ""
                        |> String.trim
                        |> String.split " "
                        |> List.map String.trim

                columnWidths =
                    Dict.get "columnWidths" block.properties
                        |> Maybe.withDefault ""
                        |> String.replace "[" ""
                        |> String.replace "]" ""
                        |> String.split ","
                        |> List.map String.trim
                        |> List.filterMap String.toInt
            in
            [ Html.div
                (blockIdAndStyle block
                    ++ [ HA.style "margin" "1em 0"
                       , HA.style "padding-left" "24px"
                       ]
                    ++ Render.Utility.rlBlockSync block.meta
                )
                [ Html.table [ HA.style "border-collapse" "collapse" ]
                    [ Html.tbody [] (List.map (renderTableRow params acc formatList columnWidths) rows) ]
                ]
            ]

        Right _ ->
            [ Html.div [ idAttr block.meta.id ] [] ]

        Left data ->
            [ Html.div [ idAttr block.meta.id ] [ Html.text data ] ]


renderTableRow : CompilerParameters -> Accumulator -> List String -> List Int -> Expression -> Html Msg
renderTableRow params acc formats widths row =
    case row of
        Fun "row" cells _ ->
            Html.tr [ HA.style "height" "20px" ]
                (List.indexedMap (renderTableCell params acc formats widths) cells)

        _ ->
            Html.tr [] []


renderTableCell : CompilerParameters -> Accumulator -> List String -> List Int -> Int -> Expression -> Html Msg
renderTableCell params acc formats widths index cell =
    case cell of
        Fun "cell" exprs _ ->
            let
                width =
                    List.drop index widths
                        |> List.head
                        |> Maybe.withDefault 100

                alignment =
                    List.drop index formats
                        |> List.head
                        |> Maybe.withDefault "l"
                        |> formatToTextAlign
            in
            Html.td
                [ HA.style "width" (String.fromInt (width + 10) ++ "px")
                , HA.style "text-align" alignment
                , HA.style "padding" "4px 8px"
                ]
                (Render.Expression.renderList params acc exprs)

        _ ->
            Html.td [] []


formatToTextAlign : String -> String
formatToTextAlign fmt =
    case fmt of
        "l" ->
            "left"

        "r" ->
            "right"

        "c" ->
            "center"

        _ ->
            "left"



-- DESCRIPTION LISTS


{-| Render a description list item.

    | desc Term
    Definition of the term.

Arguments:

  - Term label

-}
renderDesc : CompilerParameters -> Accumulator -> String -> ExpressionBlock -> List (Html Msg) -> List (Html Msg)
renderDesc params acc _ block children =
    let
        label =
            String.join " " block.args
    in
    [ Html.div
        (blockIdAndStyle block
            ++ [ HA.style "display" "flex"
               , HA.style "margin-bottom" "0.5em"
               ]
            ++ Render.Utility.rlBlockSync block.meta
        )
        [ Html.dt
            [ HA.style "font-weight" "bold"
            , HA.style "width" "100px"
            , HA.style "flex-shrink" "0"
            ]
            [ Html.text label ]
        , Html.dd
            [ HA.style "margin-left" "1em"
            , HA.style "flex" "1"
            ]
            (renderBody params acc block ++ children)
        ]
    ]



-- FOOTNOTES/ENDNOTES


{-| Render collected endnotes at the end of a document.

    | endnotes

Displays all footnotes collected from [footnote ...] expressions.

-}
renderEndnotes : CompilerParameters -> Accumulator -> String -> ExpressionBlock -> List (Html Msg) -> List (Html Msg)
renderEndnotes params acc _ block _ =
    let
        endnoteList =
            acc.footnotes
                |> Dict.toList
                |> List.map
                    (\( content, meta ) ->
                        { label = Dict.get meta.id acc.footnoteNumbers |> Maybe.withDefault 0
                        , content = content
                        , id = meta.id ++ "_"
                        , mSourceBlockId = meta.mSourceId
                        }
                    )
                |> List.sortBy .label
    in
    [ Html.div
        (blockIdAndStyle block
            ++ [ HA.style "margin-top" "2em"
               , HA.style "padding-top" "1em"
               , HA.style "border-top" "1px solid #ccc"
               ]
            ++ Render.Utility.rlBlockSync block.meta
        )
        (Html.div
            [ HA.style "font-weight" "bold"
            , HA.style "font-size" (Render.Sizing.toPx params.sizing 18.0)
            , HA.style "margin-bottom" "0.5em"
            ]
            [ Html.text "Endnotes" ]
            :: List.map (renderFootnoteItem params) endnoteList
        )
    ]


renderFootnoteItem : CompilerParameters -> { label : Int, content : String, id : String, mSourceBlockId : Maybe String } -> Html Msg
renderFootnoteItem params { label, content, id, mSourceBlockId } =
    Html.div
        ([ HA.id id
         , HA.style "margin-bottom" "0.5em"
         , HA.style "cursor" "pointer"
         ]
            ++ (case mSourceBlockId of
                    Just sourceBlockId ->
                        [ HE.stopPropagationOn "click"
                            (Decode.succeed ( FootnoteClick { targetId = sourceBlockId, returnId = id }, True ))
                        ]

                    Nothing ->
                        []
               )
        )
        [ Html.span
            [ HA.style "width" "24px"
            , HA.style "display" "inline-block"
            ]
            [ Html.text (String.fromInt label ++ ".") ]
        , Html.text content
        ]



-- ADDITIONAL BLOCKS FROM V2


{-| Render nothing (for configuration/metadata blocks).

Used for: book, banner, runninghead\_, tags, type, setcounter, shiftandsetcounter.

-}
renderNothing : CompilerParameters -> Accumulator -> String -> ExpressionBlock -> List (Html Msg) -> List (Html Msg)
renderNothing _ _ _ block _ =
    [ Html.span [ HA.id block.meta.id, HA.style "display" "none" ] [] ]


{-| Render a subheading (smaller than section).

    | subheading
    Minor Heading

Also available as `| sh`.

-}
renderSubheading : CompilerParameters -> Accumulator -> String -> ExpressionBlock -> List (Html Msg) -> List (Html Msg)
renderSubheading params acc _ block children =
    [ Html.div
        (blockIdAndStyle block
            ++ [ HA.style "font-size" "1.1em"
               , HA.style "font-weight" "normal"
               , HA.style "margin-top" "1em"
               , HA.style "margin-bottom" "0.5em"
               ]
            ++ Render.Utility.rlBlockSync block.meta
        )
        (renderBody params acc block ++ children)
    ]


{-| Render content with reduced line spacing.

    | compact
    Dense content with tighter line spacing.

-}
renderCompact : CompilerParameters -> Accumulator -> String -> ExpressionBlock -> List (Html Msg) -> List (Html Msg)
renderCompact params acc _ block children =
    [ Html.div
        (blockIdAndStyle block
            ++ [ HA.style "line-height" "1.2"
               ]
            ++ Render.Utility.rlBlockSync block.meta
        )
        (renderBody params acc block ++ children)
    ]


{-| Render content with no special styling (identity transform).

    | identity
    This content is rendered as-is.

-}
renderIdentity : CompilerParameters -> Accumulator -> String -> ExpressionBlock -> List (Html Msg) -> List (Html Msg)
renderIdentity params acc _ block children =
    [ Html.div
        (blockIdAndStyle block
            ++ Render.Utility.rlBlockSync block.meta
        )
        (renderBody params acc block ++ children)
    ]


{-| Render content in a specified color.

    | red
    This text is red.

    | blue
    This text is blue.

Available colors: red, red2, blue.

-}
renderColorBlock : String -> CompilerParameters -> Accumulator -> String -> ExpressionBlock -> List (Html Msg) -> List (Html Msg)
renderColorBlock color params acc _ block children =
    [ Html.div
        (blockIdAndStyle block
            ++ [ HA.style "color" color
               ]
            ++ Render.Utility.rlBlockSync block.meta
        )
        (renderBody params acc block ++ children)
    ]


{-| Render a question block with "Q:" prefix.

    | q
    What is the meaning of life?

-}
renderQuestion : CompilerParameters -> Accumulator -> String -> ExpressionBlock -> List (Html Msg) -> List (Html Msg)
renderQuestion params acc _ block children =
    let
        clickHandler =
            case Dict.get block.meta.id acc.qAndADict of
                Just answerId ->
                    Render.Utility.rlQBlockSync answerId

                Nothing ->
                    Render.Utility.rlBlockSync block.meta
    in
    [ Html.div
        ([ HA.style "margin-bottom" (Render.Sizing.paragraphSpacingPx params.sizing)
         , HA.style "padding" "0.5em"
         , HA.style "background-color" "#f0f8ff"
         , HA.style "border-left" "3px solid #4a90d9"
         , HA.style "cursor" "pointer"
         ]
            ++ blockIdAndStyle block
            ++ clickHandler
        )
        [ Html.div [ HA.style "pointer-events" "none" ]
            (Html.span [ HA.style "font-weight" "bold", HA.style "color" "#4a90d9" ] [ Html.text "Q: " ]
                :: renderBody params acc block
                ++ children
            )
        ]
    ]


{-| Render an answer block with "A:" prefix.

    | a
    42.

-}
renderAnswer : CompilerParameters -> Accumulator -> String -> ExpressionBlock -> List (Html Msg) -> List (Html Msg)
renderAnswer params acc _ block children =
    [ Html.div
        ([ HA.style "margin-bottom" (Render.Sizing.paragraphSpacingPx params.sizing)
         , HA.style "padding" "0.5em"
         , HA.style "background-color" "#f0fff0"
         , HA.style "border-left" "3px solid #4a9"
         , HA.style "display" "none"
         ]
            ++ blockIdAndStyle block
        )
        (Html.span [ HA.style "font-weight" "bold", HA.style "color" "#4a9" ] [ Html.text "A: " ]
            :: renderBody params acc block
            ++ children
        )
    ]


{-| Render collapsible/expandable content.

    | reveal Click to see answer
    The hidden answer is here.

Arguments:

  - Summary text (default: "Click to reveal")

-}
renderReveal : CompilerParameters -> Accumulator -> String -> ExpressionBlock -> List (Html Msg) -> List (Html Msg)
renderReveal params acc _ block children =
    let
        closedText =
            String.join " " block.args
                |> (\s ->
                        if String.isEmpty s then
                            "More ..."

                        else
                            s
                   )

        toggleCss =
            ".reveal-toggle > summary > .reveal-open { display: none; }"
                ++ " .reveal-toggle[open] > summary > .reveal-closed { display: none; }"
                ++ " .reveal-toggle[open] > summary > .reveal-open { display: inline; }"
    in
    [ Html.details
        (blockIdAndStyle block
            ++ [ HA.class "reveal-toggle"
               , HA.style "margin-bottom" (Render.Sizing.paragraphSpacingPx params.sizing)
               ]
            ++ Render.Utility.rlBlockSync block.meta
        )
        [ Html.node "style" [] [ Html.text toggleCss ]
        , Html.summary [ HA.style "cursor" "pointer" ]
            [ Html.span [ HA.class "reveal-closed" ] [ Html.text closedText ]
            , Html.span [ HA.class "reveal-open", HA.style "font-style" "italic" ] [ Html.text closedText ]
            ]
        , Html.div [ HA.style "padding" "0.5em" ]
            (renderBody params acc block ++ children)
        ]
    ]


{-| Render a chapter heading (large h1).

    | chapter
    Introduction to Mathematics

-}
renderChapter : CompilerParameters -> Accumulator -> String -> ExpressionBlock -> List (Html Msg) -> List (Html Msg)
renderChapter params acc _ block children =
    let
        chapterNumber =
            Dict.get "chapter-number" block.properties
                |> Maybe.withDefault ""

        chapterLabel =
            if chapterNumber /= "" then
                "Chapter " ++ chapterNumber ++ ". "

            else
                ""
    in
    [ Html.h1
        (blockIdAndStyle block
            ++ [ HA.style "font-size" "2em"
               , HA.style "font-weight" "normal"
               , HA.style "margin-top" "1.5em"
               , HA.style "margin-bottom" "0.5em"
               ]
            ++ Render.Utility.rlBlockSync block.meta
        )
        (Html.text chapterLabel :: renderBody params acc block ++ children)
    ]


{-| Render an unnumbered section heading.

    | section*
    Appendix

    | section* 2
    Sub-appendix

Arguments:

  - Level (1-3, default 1)

-}
renderUnnumberedSection : CompilerParameters -> Accumulator -> String -> ExpressionBlock -> List (Html Msg) -> List (Html Msg)
renderUnnumberedSection params acc _ block children =
    let
        level =
            block.args
                |> List.head
                |> Maybe.andThen String.toInt
                |> Maybe.withDefault 1

        fontSize =
            case level of
                1 ->
                    "1.5em"

                2 ->
                    "1.3em"

                _ ->
                    "1.1em"
    in
    [ Html.div
        (blockIdAndStyle block
            ++ [ HA.style "font-size" fontSize
               , HA.style "font-weight" "bold"
               , HA.style "margin-top" "1em"
               , HA.style "margin-bottom" "0.5em"
               ]
            ++ Render.Utility.rlBlockSync block.meta
        )
        (renderBody params acc block ++ children)
    ]


{-| Render a visible banner image.

    | visibleBanner
    /images/banner.jpg

-}
renderVisibleBanner : CompilerParameters -> Accumulator -> String -> ExpressionBlock -> List (Html Msg) -> List (Html Msg)
renderVisibleBanner _ _ _ block _ =
    let
        src =
            block.firstLine
    in
    [ Html.img
        [ HA.id block.meta.id
        , HA.src src
        , HA.style "max-width" "100%"
        , HA.style "margin-bottom" "1em"
        ]
        []
    ]


renderBibliography : CompilerParameters -> Accumulator -> String -> ExpressionBlock -> List (Html Msg) -> List (Html Msg)
renderBibliography params _ _ block children =
    [ Html.h2
        (blockIdAndStyle block
            ++ Render.Utility.rlBlockSync block.meta
        )
        [ Html.text "References" ]
    ]
        ++ children


{-| Render a bibliography item.

    | bibitem einstein1905
    Einstein, A. (1905). On the Electrodynamics of Moving Bodies.

Arguments:

  - Citation key (e.g., "einstein1905")

Renders as: [N] <body content>
Wrapped in div with id "key:N" for citation linking.

-}
renderBibitem : CompilerParameters -> Accumulator -> String -> ExpressionBlock -> List (Html Msg) -> List (Html Msg)
renderBibitem params acc _ block children =
    let
        key =
            block.args
                |> List.head
                |> Maybe.withDefault ""

        -- Get the bibitem number from the bibliography dictionary
        number =
            Dict.get key acc.bibliography
                |> Maybe.andThen identity
                |> Maybe.withDefault 0

        -- Create id as "key:number" for citation linking
        bibitemId =
            key ++ ":" ++ String.fromInt number
    in
    [ Html.div
        ([ HA.id bibitemId
         , HA.style "display" "flex"
         , HA.style "margin-bottom" "0.5em"
         ]
            ++ Render.Utility.rlBlockSync block.meta
        )
        [ Html.span
            [ HA.style "font-weight" "bold"
            , HA.style "min-width" "40px"
            ]
            [ Html.text ("[" ++ String.fromInt number ++ "]") ]
        , Html.div [ HA.style "flex" "1" ]
            (renderBody params acc block ++ children)
        ]
    ]


{-| Render a generic named environment.

    | env Algorithm
    Step 1: Initialize
    Step 2: Process
    Step 3: Output

Arguments:

  - Environment name (displayed as title)

-}
renderEnv : CompilerParameters -> Accumulator -> String -> ExpressionBlock -> List (Html Msg) -> List (Html Msg)
renderEnv params acc _ block children =
    let
        envName =
            block.args
                |> List.head
                |> Maybe.withDefault "environment"
    in
    [ Html.div
        (blockIdAndStyle block
            ++ [ HA.style "margin-bottom" (Render.Sizing.paragraphSpacingPx params.sizing)
               , HA.style "padding" "0.5em"
               , HA.style "border" "1px solid #ddd"
               ]
            ++ Render.Utility.rlBlockSync block.meta
        )
        (Html.div [ HA.style "font-weight" "bold", HA.style "margin-bottom" "0.5em" ]
            [ Html.text (capitalize envName) ]
            :: renderBody params acc block
            ++ children
        )
    ]


capitalize : String -> String
capitalize str =
    case String.uncons str of
        Just ( first, rest ) ->
            String.cons (Char.toUpper first) rest

        Nothing ->
            str


{-| Convert text to a URL-friendly slug.
Removes non-alphanumeric characters, compresses spaces, converts to lowercase, and replaces spaces with dashes.

    toSlug "Jon's Stuff!" == "jons-stuff"

    toSlug "Hello   World" == "hello-world"

-}
toSlug : String -> String
toSlug text =
    text
        |> String.toLower
        |> String.toList
        |> List.map
            (\c ->
                if Char.isAlphaNum c then
                    c

                else
                    ' '
            )
        |> String.fromList
        |> String.words
        |> String.join "-"


{-| Extract plain text from a block's body for use in slug generation.
Falls back to firstLine if body is empty.
-}
getBlockText : ExpressionBlock -> String
getBlockText block =
    case block.body of
        Left str ->
            if String.isEmpty str then
                block.firstLine

            else
                str

        Right expressions ->
            let
                bodyText =
                    expressions
                        |> List.map extractTextFromExpr
                        |> String.concat
            in
            if String.isEmpty bodyText then
                block.firstLine

            else
                bodyText


{-| Recursively extract text from an expression.
-}
extractTextFromExpr : Expression -> String
extractTextFromExpr expr =
    case expr of
        Text str _ ->
            str

        Fun _ args _ ->
            List.map extractTextFromExpr args |> String.concat

        VFun _ content _ ->
            content

        ExprList _ exprs _ ->
            List.map extractTextFromExpr exprs |> String.concat
