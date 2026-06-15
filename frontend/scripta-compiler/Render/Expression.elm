module Render.Expression exposing (renderList)

{-| Render expressions to HTML.
-}

import Dict exposing (Dict)
import ETeX.Transform
import Html exposing (Html)
import Html.Attributes as HA
import Html.Events as HE
import Json.Decode as Decode
import Render.Constants
import Render.Math exposing (DisplayMode(..), mathText)
import Render.Utility
import V3.Types exposing (Accumulator, CompilerParameters, Expr(..), ExprMeta, Expression, MathMacroDict, Msg(..))


{-| Render a list of expressions.
-}
renderList : CompilerParameters -> Accumulator -> List Expression -> List (Html Msg)
renderList params acc expressions =
    List.map (render params acc) expressions


{-| Render a single expression.
-}
render : CompilerParameters -> Accumulator -> Expression -> Html Msg
render params acc expr =
    case expr of
        Text str meta ->
            renderText params str meta

        Fun name args meta ->
            renderFun params acc name args meta

        VFun name content meta ->
            renderVFun params acc name content meta

        ExprList _ exprs meta ->
            Html.span (Render.Utility.rlSync meta)
                (renderList params acc exprs)


{-| Render plain text with position data attributes for selection sync.
-}
renderText : CompilerParameters -> String -> ExprMeta -> Html Msg
renderText params str meta =
    Html.span
        (Render.Utility.rlSync meta)
        [ Html.text str ]


{-| Render a function application.
-}
renderFun : CompilerParameters -> Accumulator -> String -> List Expression -> ExprMeta -> Html Msg
renderFun params acc name args meta =
    case Dict.get name markupDict of
        Just renderer ->
            renderer params acc args meta

        Nothing ->
            -- Default rendering for unknown functions
            renderDefaultFun params acc name args meta


{-| Render a verbatim function.
-}
renderVFun : CompilerParameters -> Accumulator -> String -> String -> ExprMeta -> Html Msg
renderVFun params acc name content meta =
    case name of
        "$" ->
            -- Inline math (legacy) - apply ETeX transform with user macros
            mathText params.editCount { id = meta.id, begin = meta.begin, end = meta.end } InlineMathMode (applyMathMacros acc.mathMacroDict content)

        "math" ->
            -- Inline math - apply ETeX transform with user macros
            mathText params.editCount { id = meta.id, begin = meta.begin, end = meta.end } InlineMathMode (applyMathMacros acc.mathMacroDict content)

        "m" ->
            -- Inline math (short alias) - apply ETeX transform with user macros
            mathText params.editCount { id = meta.id, begin = meta.begin, end = meta.end } InlineMathMode (applyMathMacros acc.mathMacroDict content)

        "chem" ->
            -- Chemistry formula - render as math with mhchem
            mathText params.editCount { id = meta.id, begin = meta.begin, end = meta.end } InlineMathMode ("\\ce{" ++ content ++ "}")

        "code" ->
            Html.code (Render.Utility.rlSync meta ++ [ HA.style "font-size" "1.01rem" ]) [ Html.text content ]

        "`" ->
            -- Backtick code (alias for code)
            Html.code (Render.Utility.rlSync meta ++ [ HA.style "font-size" "1.01rem" ]) [ Html.text content ]

        _ ->
            -- Default: just show the content
            Html.span (Render.Utility.rlSync meta) [ Html.text content ]


{-| Transform ETeX notation to LaTeX using ETeX.Transform.evalStr.

Converts notation like `int_0^2`, `frac(1,n+1)` to `\int_0^2`, `\frac{1}{n+1}`.
Also expands user-defined macros from mathmacros blocks.

-}
applyMathMacros : MathMacroDict -> String -> String
applyMathMacros macroDict content =
    ETeX.Transform.evalStr macroDict content


{-| Default rendering for unknown function names.
-}
renderDefaultFun : CompilerParameters -> Accumulator -> String -> List Expression -> ExprMeta -> Html Msg
renderDefaultFun params acc name args meta =
    Html.span (Render.Utility.rlSync meta)
        (Html.span [ HA.style "color" "blue" ] [ Html.text ("[" ++ name ++ " ") ]
            :: renderList params acc args
            ++ [ Html.text "]" ]
        )



-- MARKUP DICTIONARY


{-| Dictionary of markup function renderers.
-}
markupDict : Dict String (CompilerParameters -> Accumulator -> List Expression -> ExprMeta -> Html Msg)
markupDict =
    Dict.fromList
        [ ( "strong", renderStrong )
        , ( "bold", renderStrong )
        , ( "b", renderStrong )
        , ( "italic", renderItalic )
        , ( "i", renderItalic )
        , ( "emph", renderItalic )
        , ( "strike", renderStrike )
        , ( "underline", renderUnderline )
        , ( "red", renderColor "red" )
        , ( "blue", renderColor "blue" )
        , ( "green", renderColor "#006400" )
        , ( "pink", renderColor "#ff6464" )
        , ( "magenta", renderColor "#ff33c0" )
        , ( "violet", renderColor "#9664ff" )
        , ( "gray", renderColor "#808080" )
        , ( "comment", renderColor "blue" )
        , ( "highlight", renderHighlight )
        , ( "errorHighlight", renderErrorHighlight )
        , ( "link", renderLink )
        , ( "href", renderHref )
        , ( "image", renderImage )
        , ( "ilink", renderIlink )
        , ( "wikilink", renderWikilink )
        , ( "index", renderIndex_ )
        , ( "ref", renderRef )
        , ( "eqref", renderMathRef )
        , ( "mathref", renderMathRef )
        , ( "cite", renderCite )
        , ( "sup", renderSup )
        , ( "sub", renderSub )

        --, ( "term", renderIndex_ )
        --, ( "term_", renderTermHidden )
        , ( "vspace", renderVspace )
        , ( "break", renderVspace )

        -- Aliases
        , ( "textbf", renderStrong )
        , ( "textit", renderItalic )
        , ( "u", renderUnderline )
        , ( "underscore", renderUnderline )

        -- Text styling
        , ( "bi", renderBoldItalic )
        , ( "boldItalic", renderBoldItalic )
        , ( "var", renderVar )
        , ( "title", renderTitle )
        , ( "subheading", renderSubheading )
        , ( "sh", renderSubheading )
        , ( "smallsubheading", renderSmallSubheading )
        , ( "ssh", renderSmallSubheading )
        , ( "large", renderLarge )
        , ( "qed", renderQed )

        -- Special characters
        , ( "mdash", renderChar "—" )
        , ( "ndash", renderChar "–" )
        , ( "dollarSign", renderChar "$" )
        , ( "dollar", renderChar "$" )
        , ( "ds", renderChar "$" )
        , ( "backTick", renderChar "`" )
        , ( "bt", renderChar "`" )
        , ( "rb", renderChar "]" )
        , ( "lb", renderChar "[" )
        , ( "bracket", renderBracket )

        -- Checkbox symbols
        , ( "box", renderBox )
        , ( "cbox", renderCbox )
        , ( "rbox", renderRbox )
        , ( "crbox", renderCrbox )
        , ( "fbox", renderFbox )
        , ( "frbox", renderFrbox )
        , ( "xbox", renderXbox )

        -- Hidden/no-op
        , ( "hide", renderHidden )
        , ( "author", renderHidden )
        , ( "date", renderHidden )
        , ( "today", renderHidden )
        , ( "lambda", renderHidden )
        , ( "setcounter", renderHidden )
        , ( "label", renderHidden )
        , ( "tags", renderHidden )

        -- Structure
        , ( "//", renderPar )
        , ( "par", renderPar )
        , ( "///", renderPar2 )
        , ( "par2", renderPar2 )
        , ( "indent", renderIndent )
        , ( "quote", renderQuote )
        , ( "abstract", renderAbstract )
        , ( "anchor", renderAnchor )
        , ( "footnote", renderFootnote )
        , ( "marked", renderMarked )

        -- Tables
        , ( "table", renderTable )
        , ( "tableRow", renderTableRow )
        , ( "tableItem", renderTableItem )

        -- Images
        , ( "inlineimage", renderInlineImage )

        -- Bibliography
        , ( "bibitem", renderBibitem )

        -- Links (specialized)
        , ( "ulink", renderUlink )
        , ( "reflink", renderReflink )
        , ( "cslink", renderCslink )
        , ( "newPost", renderHidden )

        -- Special/Interactive (simplified)
        , ( "scheme", renderScheme )
        , ( "compute", renderCompute )
        , ( "data", renderData )
        , ( "button", renderButton )
        , ( "progress", renderProgress )

        -- Misc
        , ( "hrule", renderHrule )
        , ( "mark", renderMark )
        ]



-- MARKUP RENDERERS


{-| Render bold/strong text.

    [ strong bold text ]

    [ b bold text ]

    [ bold bold text ]

-}
renderStrong : CompilerParameters -> Accumulator -> List Expression -> ExprMeta -> Html Msg
renderStrong params acc args meta =
    Html.span (Render.Utility.rlSync meta ++ [ HA.style "font-weight" Render.Constants.boldFontWeight ]) (renderList params acc args)


{-| Render italic/emphasized text.

    [ italic emphasized text ]

    [ i emphasized text ]

    [ emph emphasized text ]

-}
renderItalic : CompilerParameters -> Accumulator -> List Expression -> ExprMeta -> Html Msg
renderItalic params acc args meta =
    Html.em (Render.Utility.rlSync meta) (renderList params acc args)


{-| Render strikethrough text.

    [ strike deleted text ]

-}
renderStrike : CompilerParameters -> Accumulator -> List Expression -> ExprMeta -> Html Msg
renderStrike params acc args meta =
    Html.span (Render.Utility.rlSync meta ++ [ HA.style "text-decoration" "line-through" ]) (renderList params acc args)


{-| Render underlined text.

    [ underline important text ]

    [ u underlined ]

-}
renderUnderline : CompilerParameters -> Accumulator -> List Expression -> ExprMeta -> Html Msg
renderUnderline params acc args meta =
    Html.span (Render.Utility.rlSync meta ++ [ HA.style "text-decoration" "underline" ]) (renderList params acc args)


{-| Render colored text.

    [ red warning text ]

    [ blue info text ]

    [ green success text ]

Available colors: red, blue, green, pink, magenta, violet, gray.

-}
renderColor : String -> CompilerParameters -> Accumulator -> List Expression -> ExprMeta -> Html Msg
renderColor color params acc args meta =
    Html.span (Render.Utility.rlSync meta ++ [ HA.style "color" color ]) (renderList params acc args)


{-| Render highlighted text with background color.

    [ highlight important text ]

    [ highlight [ color blue ] blue highlighted ]

Colors: yellow (default), blue, green, pink, orange, purple, cyan, gray.

-}
renderHighlight : CompilerParameters -> Accumulator -> List Expression -> ExprMeta -> Html Msg
renderHighlight params acc args meta =
    let
        -- Filter out the color expression from display
        displayArgs =
            filterOutExpressionsOnName "color" args

        cssColor =
            case params.theme of
                V3.Types.Light ->
                    "#ffff00"

                V3.Types.Dark ->
                    "#CC7000"
    in
    Html.span
        (Render.Utility.rlSync meta
            ++ [ HA.style "background-color" cssColor
               , HA.style "padding-left" "0.25em"
               , HA.style "padding-right" "0.25em"
               ]
        )
        (renderList params acc displayArgs)


highlightColorDict : Dict String String
highlightColorDict =
    Dict.fromList
        [ ( "yellow", "#ffff00" )
        , ( "blue", "#b4b4ff" )
        , ( "green", "#b4ffb4" )
        , ( "pink", "#ffb4b4" )
        , ( "orange", "#ffd494" )
        , ( "purple", "#d4b4ff" )
        , ( "cyan", "#b4ffff" )
        , ( "gray", "#d4d4d4" )
        ]


filterExpressionsOnName : String -> List Expression -> List Expression
filterExpressionsOnName name exprs =
    List.filter (hasName name) exprs


filterOutExpressionsOnName : String -> List Expression -> List Expression
filterOutExpressionsOnName name exprs =
    List.filter (hasName name >> not) exprs


hasName : String -> Expression -> Bool
hasName name expr =
    case expr of
        Fun n _ _ ->
            n == name

        _ ->
            False


getTextFromExpr : Expression -> Maybe String
getTextFromExpr expr =
    case expr of
        Fun _ args _ ->
            args |> List.filterMap getTextContent |> List.head

        _ ->
            Nothing


{-| Render a hyperlink.

    [ link Label https :// example.com ]

    [ link https :// example.com ]

-}
renderLink : CompilerParameters -> Accumulator -> List Expression -> ExprMeta -> Html Msg
renderLink _ _ args meta =
    let
        -- Extract all text from args and join with spaces
        argString =
            args
                |> List.filterMap getTextContent
                |> String.join " "

        words =
            String.words argString

        n =
            List.length words
    in
    if n == 0 then
        Html.span [ HA.id meta.id ] [ Html.text "link: missing url" ]

    else if n == 1 then
        -- Single word is URL only
        let
            url =
                String.join "" words
        in
        Html.a [ HA.id meta.id, HA.href url, HA.target "_blank" ] [ Html.text url ]

    else
        -- Multiple words: last word is URL, rest is label
        let
            label =
                List.take (n - 1) words |> String.join " "

            url =
                List.drop (n - 1) words |> String.join ""
        in
        Html.a [ HA.id meta.id, HA.href url, HA.target "_blank" ] [ Html.text label ]


{-| Render a URL as a clickable link.

    [ href https :// example.com ]

-}
renderHref : CompilerParameters -> Accumulator -> List Expression -> ExprMeta -> Html Msg
renderHref params acc args meta =
    case args of
        [ Text url _ ] ->
            Html.a [ HA.id meta.id, HA.href url, HA.target "_blank" ] [ Html.text url ]

        _ ->
            Html.span [ HA.id meta.id ] (renderList params acc args)


{-| Render an inline image.

    [ image https :// example.com / photo.jpg ]

-}
renderImage : CompilerParameters -> Accumulator -> List Expression -> ExprMeta -> Html Msg
renderImage params _ args meta =
    case args of
        [ Text src _ ] ->
            Html.img
                [ HA.id meta.id
                , HA.src src
                , HA.style "max-width" (String.fromInt params.width ++ "px")
                ]
                []

        _ ->
            Html.text "[image: invalid args]"


{-| Render an internal document link.

    [ ilink Section 1 sec1 ]

Clicking navigates within the document.

-}
renderIlink : CompilerParameters -> Accumulator -> List Expression -> ExprMeta -> Html Msg
renderIlink params acc args meta =
    let
        -- Extract all text content and split into words. Tokens prefixed
        -- "with:" are key:value args (slug for the backlinks table); they
        -- are stripped from the visible label and from target-id selection
        -- here, but the source body still contains them so they round-trip
        -- through save unchanged. Of the remaining words, the last is the
        -- targetId; the rest form the label.
        allText =
            List.map exprText args |> String.join " "

        ( withTokens, positionalWords ) =
            String.words allText
                |> List.partition (String.startsWith "with:")

        slug =
            List.head withTokens
                |> Maybe.map (String.dropLeft 5)
    in
    case List.reverse positionalWords of
        targetId :: labelWords ->
            Html.a
                [ HA.id (Maybe.withDefault meta.id slug)
                , HA.href ("#" ++ targetId)
                , HE.custom "click"
                    (Decode.succeed
                        { message = GoToDocument targetId meta
                        , stopPropagation = True
                        , preventDefault = True
                        }
                    )
                , HA.style "color"
                    (case params.theme of
                        V3.Types.Light ->
                            "#0066cc"

                        V3.Types.Dark ->
                            "#66b3ff"
                    )
                , HA.style "text-decoration" "none"
                , HA.style "cursor" "pointer"
                ]
                [ Html.text (String.join " " (List.reverse labelWords)) ]

        _ ->
            Html.span [ HA.id meta.id ] (renderList params acc args)


{-| Render a wikilink. Args arrive with ID first, then label words.
Reshuffle so ID is last (to match ilink's trailing-ID convention), then
delegate to renderIlink.
-}
renderWikilink : CompilerParameters -> Accumulator -> List Expression -> ExprMeta -> Html Msg
renderWikilink params acc args meta =
    renderIlink params acc (moveFirstTextToEnd args) meta


moveFirstTextToEnd : List Expression -> List Expression
moveFirstTextToEnd args =
    case args of
        [ Text first firstMeta ] ->
            [ Text first firstMeta, Text first firstMeta ]

        (Text first firstMeta) :: rest ->
            dropLeadingWhitespace rest ++ [ Text first firstMeta ]

        _ ->
            args


dropLeadingWhitespace : List Expression -> List Expression
dropLeadingWhitespace args =
    case args of
        (Text s m) :: rest ->
            if String.trim s == "" then
                dropLeadingWhitespace rest

            else
                Text s m :: rest

        _ ->
            args


exprText : Expression -> String
exprText expr =
    case expr of
        Text s _ ->
            s

        Fun _ children _ ->
            List.map exprText children |> String.join " "

        VFun _ content _ ->
            content

        ExprList _ children _ ->
            List.map exprText children |> String.join " "


{-| Render an index entry (hidden in output).

    [ index term ]

The term is collected for index generation but not displayed.

-}
renderIndex : CompilerParameters -> Accumulator -> List Expression -> ExprMeta -> Html Msg
renderIndex _ _ _ meta =
    Html.span [ HA.id meta.id, HA.style "display" "none" ] []


{-| Render a cross-reference to a labeled element.

    [ ref theorem1 ]

Displays the number of the referenced element.

-}
renderRef : CompilerParameters -> Accumulator -> List Expression -> ExprMeta -> Html Msg
renderRef _ acc args meta =
    case args of
        [ Text refId _ ] ->
            let
                trimmedRefId =
                    String.trim refId
            in
            case Dict.get trimmedRefId acc.reference of
                Just { id, numRef } ->
                    -- Use id from reference dict as the scroll target
                    Html.a
                        [ HA.id meta.id
                        , HA.href ("#" ++ id)
                        , HE.custom "click" (Decode.succeed { message = CitationClick { targetId = id, returnId = meta.id }, stopPropagation = True, preventDefault = True })
                        , HA.style "color" "#0066cc"
                        , HA.style "text-decoration" "none"
                        , HA.style "cursor" "pointer"
                        , HA.style "padding" "2px 4px"
                        , HA.style "margin" "-2px -4px"
                        ]
                        [ Html.text numRef ]

                Nothing ->
                    Html.span [ HA.id meta.id, HA.style "color" "red" ] [ Html.text ("??" ++ trimmedRefId) ]

        _ ->
            Html.span [ HA.id meta.id ] [ Html.text "[ref: invalid]" ]


{-| Render a cross-reference to an equation.

    [ eqref eq1 ]

Displays as "(N)" where N is the equation number, linking to the equation.

-}
renderMathRef : CompilerParameters -> Accumulator -> List Expression -> ExprMeta -> Html Msg
renderMathRef _ acc args meta =
    case args of
        [ Text refId _ ] ->
            let
                trimmedRefId =
                    String.trim refId
            in
            case Dict.get trimmedRefId acc.reference of
                Just { id, numRef } ->
                    Html.a
                        [ HA.id meta.id
                        , HA.href ("#" ++ id)
                        , HE.custom "click" (Decode.succeed { message = CitationClick { targetId = id, returnId = meta.id }, stopPropagation = True, preventDefault = True })
                        , HA.style "color" "#0066cc"
                        , HA.style "text-decoration" "none"
                        , HA.style "cursor" "pointer"
                        , HA.style "padding" "2px 4px"
                        , HA.style "margin" "-2px -4px"
                        ]
                        [ Html.text ("(" ++ numRef ++ ")") ]

                Nothing ->
                    Html.span [ HA.id meta.id, HA.style "color" "red" ] [ Html.text ("(??" ++ trimmedRefId ++ ")") ]

        _ ->
            Html.span [ HA.id meta.id ] [ Html.text "[eqref: invalid]" ]


{-| Render a citation.

    [ cite einstein1905 ]

Displays as "[key]".

-}
renderCite : CompilerParameters -> Accumulator -> List Expression -> ExprMeta -> Html Msg
renderCite _ acc args meta =
    case args of
        [ Text key _ ] ->
            let
                trimmedKey =
                    String.trim key

                -- Look up the bibitem number in the bibliography dictionary
                ( targetId, displayNumber ) =
                    case Dict.get trimmedKey acc.bibliography of
                        Just (Just number) ->
                            ( trimmedKey ++ ":" ++ String.fromInt number, String.fromInt number )

                        _ ->
                            ( trimmedKey, "?" )
            in
            Html.a
                [ HA.id meta.id
                , HA.href ("#" ++ targetId)
                , HE.custom "click" (Decode.succeed { message = CitationClick { targetId = targetId, returnId = meta.id }, stopPropagation = True, preventDefault = True })
                , HA.style "color" "#0066cc"
                , HA.style "text-decoration" "none"
                , HA.style "cursor" "pointer"
                ]
                [ Html.text ("[" ++ displayNumber ++ "]") ]

        _ ->
            Html.span [ HA.id meta.id ] [ Html.text "[cite: invalid]" ]


{-| Render superscript text.

    [ sup 2 ]

-}
renderSup : CompilerParameters -> Accumulator -> List Expression -> ExprMeta -> Html Msg
renderSup params acc args meta =
    Html.sup (Render.Utility.rlSync meta) (renderList params acc args)


{-| Render subscript text.

    [ sub i ]

-}
renderSub : CompilerParameters -> Accumulator -> List Expression -> ExprMeta -> Html Msg
renderSub params acc args meta =
    Html.sub (Render.Utility.rlSync meta) (renderList params acc args)


{-| Render a term (italicized, for definitions).

    [term entropy]
    [term prime number list-as:number, prime]

The list-as: property is stripped from display (it only affects index listing).

-}
renderIndex_ : CompilerParameters -> Accumulator -> List Expression -> ExprMeta -> Html Msg
renderIndex_ _ _ args meta =
    let
        -- Get all text content and strip list-as: property
        fullText =
            args
                |> List.filterMap getExprText
                |> String.join " "

        displayText =
            case String.split "list-as:" fullText of
                termPart :: _ ->
                    String.trim termPart

                [] ->
                    fullText
    in
    Html.em
        --(Render.Utility.rlSync meta
        --    ++ [ HA.style "padding-right" "2px" ]
        --)
        [ HA.style "padding-right" "2px" ]
        [ Html.text displayText ]


{-| Extract text content from an expression.
-}
getExprText : Expression -> Maybe String
getExprText expr =
    case expr of
        Text str _ ->
            Just str

        _ ->
            Nothing


{-| Render a hidden term (for index only, not displayed).

    [ term_ hidden entry ]

-}
renderTermHidden : CompilerParameters -> Accumulator -> List Expression -> ExprMeta -> Html Msg
renderTermHidden _ _ _ meta =
    Html.span [ HA.id meta.id, HA.style "display" "none" ] []


{-| Render vertical space.

    [ vspace 20 ]

    [ break 10 ]

Argument is height in pixels.

-}
renderVspace : CompilerParameters -> Accumulator -> List Expression -> ExprMeta -> Html Msg
renderVspace _ _ args meta =
    let
        h =
            args
                |> List.filterMap getTextContent
                |> String.concat
                |> String.toInt
                |> Maybe.withDefault 1
    in
    Html.div
        [ HA.id meta.id
        , HA.style "height" (String.fromInt h ++ "px")
        ]
        []


getTextContent : Expression -> Maybe String
getTextContent expr =
    case expr of
        Text str _ ->
            Just str

        _ ->
            Nothing


{-| Render bold italic text.

    [ bi bold and italic ]

    [ boldItalic text ]

-}
renderBoldItalic : CompilerParameters -> Accumulator -> List Expression -> ExprMeta -> Html Msg
renderBoldItalic params acc args meta =
    Html.span
        (Render.Utility.rlSync meta
            ++ [ HA.style "font-weight" "bold"
               , HA.style "font-style" "italic"
               ]
        )
        (renderList params acc args)


{-| Render a variable (no special formatting).

    [ var x ]

-}
renderVar : CompilerParameters -> Accumulator -> List Expression -> ExprMeta -> Html Msg
renderVar params acc args meta =
    Html.span (Render.Utility.rlSync meta) (renderList params acc args)


{-| Render inline title text (32px).

    [ title Document Title ]

-}
renderTitle : CompilerParameters -> Accumulator -> List Expression -> ExprMeta -> Html Msg
renderTitle params acc args meta =
    Html.span
        (Render.Utility.rlSync meta
            ++ [ HA.style "font-size" "32px" ]
        )
        (renderList params acc args)


{-| Render an inline subheading (18px).

    [ subheading Section Name ]

    [ sh Section Name ]

-}
renderSubheading : CompilerParameters -> Accumulator -> List Expression -> ExprMeta -> Html Msg
renderSubheading params acc args meta =
    Html.div (Render.Utility.rlSync meta)
        [ Html.p
            [ HA.style "font-size" "18px"
            , HA.style "margin-top" "8px"
            , HA.style "margin-bottom" "0"
            ]
            (renderList params acc args)
        ]


{-| Render a small subheading (16px, italic).

    [ smallsubheading Minor Heading ]

    [ ssh Minor Heading ]

-}
renderSmallSubheading : CompilerParameters -> Accumulator -> List Expression -> ExprMeta -> Html Msg
renderSmallSubheading params acc args meta =
    Html.div (Render.Utility.rlSync meta)
        [ Html.p
            [ HA.style "font-size" "16px"
            , HA.style "font-style" "italic"
            , HA.style "margin-top" "8px"
            , HA.style "margin-bottom" "0"
            ]
            (renderList params acc args)
        ]


{-| Render large text (18px).

    [ large larger text ]

-}
renderLarge : CompilerParameters -> Accumulator -> List Expression -> ExprMeta -> Html Msg
renderLarge params acc args meta =
    Html.span
        (Render.Utility.rlSync meta
            ++ [ HA.style "font-size" "1.5em" ]
        )
        (renderList params acc args)


{-| Render Q.E.D. marker (end of proof).

    [ qed ]

-}
renderQed : CompilerParameters -> Accumulator -> List Expression -> ExprMeta -> Html Msg
renderQed _ _ _ meta =
    Html.span
        (Render.Utility.rlSync meta
            ++ [ HA.style "font-weight" "bold" ]
        )
        [ Html.text "Q.E.D." ]


{-| Render error-highlighted text (red background).

    [ errorHighlight problematic text ]

-}
renderErrorHighlight : CompilerParameters -> Accumulator -> List Expression -> ExprMeta -> Html Msg
renderErrorHighlight params acc args meta =
    Html.span
        (Render.Utility.rlSync meta
            ++ [ HA.style "background-color" "#ffc8c8"
               , HA.style "padding" "2px 4px"
               ]
        )
        (renderList params acc args)


{-| Render a special character.

    [mdash] → —
    [ndash] → –
    [dollarSign] or [ds] → $
    [backTick] or [bt] → `
    [rb] → ]
    [lb] → [

-}
renderChar : String -> CompilerParameters -> Accumulator -> List Expression -> ExprMeta -> Html Msg
renderChar char _ _ _ meta =
    Html.span (Render.Utility.rlSync meta) [ Html.text char ]


{-| Render content in square brackets.

    [ brackets content ]

-}
renderBracket : CompilerParameters -> Accumulator -> List Expression -> ExprMeta -> Html Msg
renderBracket params acc args meta =
    Html.span (Render.Utility.rlSync meta)
        (Html.text "[" :: renderList params acc args ++ [ Html.text "]" ])


{-| Render an empty checkbox ☐.

    [ box ]

-}
renderBox : CompilerParameters -> Accumulator -> List Expression -> ExprMeta -> Html Msg
renderBox _ _ _ meta =
    Html.span (Render.Utility.rlSync meta ++ [ HA.style "font-size" "20px" ]) [ Html.text "☐" ]


{-| Render a checked checkbox ☑.

    [ cbox ]

-}
renderCbox : CompilerParameters -> Accumulator -> List Expression -> ExprMeta -> Html Msg
renderCbox _ _ _ meta =
    Html.span (Render.Utility.rlSync meta ++ [ HA.style "font-size" "20px" ]) [ Html.text "☑" ]


{-| Render a red empty checkbox ☐.

    [ rbox ]

-}
renderRbox : CompilerParameters -> Accumulator -> List Expression -> ExprMeta -> Html Msg
renderRbox _ _ _ meta =
    Html.span (Render.Utility.rlSync meta ++ [ HA.style "font-size" "20px", HA.style "color" "#b30000" ]) [ Html.text "☐" ]


{-| Render a red checked checkbox ☑.

    [ crbox ]

-}
renderCrbox : CompilerParameters -> Accumulator -> List Expression -> ExprMeta -> Html Msg
renderCrbox _ _ _ meta =
    Html.span (Render.Utility.rlSync meta ++ [ HA.style "font-size" "20px", HA.style "color" "#b30000" ]) [ Html.text "☑" ]


{-| Render a filled box ■.

    [ fbox ]

-}
renderFbox : CompilerParameters -> Accumulator -> List Expression -> ExprMeta -> Html Msg
renderFbox _ _ _ meta =
    Html.span (Render.Utility.rlSync meta ++ [ HA.style "font-size" "24px" ]) [ Html.text "■" ]


{-| Render a red filled box ■.

    [ frbox ]

-}
renderFrbox : CompilerParameters -> Accumulator -> List Expression -> ExprMeta -> Html Msg
renderFrbox _ _ _ meta =
    Html.span (Render.Utility.rlSync meta ++ [ HA.style "font-size" "24px", HA.style "color" "#b30000" ]) [ Html.text "■" ]


renderXbox : CompilerParameters -> Accumulator -> List Expression -> ExprMeta -> Html Msg
renderXbox _ _ _ meta =
    Html.span (Render.Utility.rlSync meta ++ [ HA.style "font-size" "20px" ]) [ Html.text "☒" ]


{-| Render nothing (hidden content).

Used for: hide, author, date, today, lambda, setcounter, label, tags.

-}
renderHidden : CompilerParameters -> Accumulator -> List Expression -> ExprMeta -> Html Msg
renderHidden _ _ _ meta =
    Html.span [ HA.id meta.id, HA.style "display" "none" ] []


{-| Render a paragraph break.

    [//]
    [par]

-}
renderPar : CompilerParameters -> Accumulator -> List Expression -> ExprMeta -> Html Msg
renderPar _ _ _ meta =
    Html.div [ HA.id meta.id, HA.style "height" "5px" ] []


renderPar2 : CompilerParameters -> Accumulator -> List Expression -> ExprMeta -> Html Msg
renderPar2 _ _ _ meta =
    Html.div [ HA.id meta.id, HA.style "height" "10px" ] []


{-| Render inline indentation (2em).

    [ indent ]

-}
renderIndent : CompilerParameters -> Accumulator -> List Expression -> ExprMeta -> Html Msg
renderIndent _ _ _ meta =
    Html.span [ HA.id meta.id, HA.style "margin-left" "2em" ] []


{-| Render quoted text with curly quotes.

    [ quote text here ]

-}
renderQuote : CompilerParameters -> Accumulator -> List Expression -> ExprMeta -> Html Msg
renderQuote params acc args meta =
    Html.span (Render.Utility.rlSync meta)
        (Html.text "“" :: renderList params acc args ++ [ Html.text "”" ])


{-| Render inline abstract with "Abstract." prefix.

    [ abstract text here ]

-}
renderAbstract : CompilerParameters -> Accumulator -> List Expression -> ExprMeta -> Html Msg
renderAbstract params acc args meta =
    Html.span (Render.Utility.rlSync meta)
        (Html.span [ HA.style "font-size" "18px" ] [ Html.text "Abstract. " ]
            :: renderList params acc args
        )


{-| Render an anchor (underlined text).

    [ anchor some text ]

-}
renderAnchor : CompilerParameters -> Accumulator -> List Expression -> ExprMeta -> Html Msg
renderAnchor params acc args meta =
    Html.span
        (Render.Utility.rlSync meta
            ++ [ HA.style "text-decoration" "underline" ]
        )
        (renderList params acc args)


{-| Render a footnote reference.

    [footnote This is the footnote text.]

Displays as superscript number linking to endnotes.
Clicking scrolls to endnote; ESC returns to footnote.

-}
renderFootnote : CompilerParameters -> Accumulator -> List Expression -> ExprMeta -> Html Msg
renderFootnote _ acc args meta =
    case args of
        [ Text _ textMeta ] ->
            case Dict.get textMeta.id acc.footnoteNumbers of
                Just k ->
                    Html.a
                        [ HA.id meta.id
                        , HA.href ("#" ++ textMeta.id ++ "_")
                        , HE.preventDefaultOn "click" (Decode.succeed ( FootnoteClick { targetId = textMeta.id ++ "_", returnId = meta.id }, True ))
                        , HA.style "font-weight" "bold"
                        , HA.style "color" "#0000b3"
                        , HA.style "text-decoration" "none"
                        , HA.style "cursor" "pointer"
                        ]
                        [ Html.sup [] [ Html.text (String.fromInt k) ] ]

                Nothing ->
                    Html.span [ HA.id meta.id ] []

        _ ->
            Html.span [ HA.id meta.id ] []


{-| Render marked/labeled content.

    [ marked label content ]

First arg is used as the element ID.

-}
renderMarked : CompilerParameters -> Accumulator -> List Expression -> ExprMeta -> Html Msg
renderMarked params acc args meta =
    case args of
        [ first ] ->
            Html.span [ HA.id meta.id ] (renderList params acc [ first ])

        (Text str _) :: rest ->
            Html.span [ HA.id str ] (renderList params acc rest)

        _ ->
            Html.span [ HA.id meta.id ] []



-- TABLE RENDERING


{-| Render an inline table.

    [ table [ tableRow [ tableItem A ] [ tableItem B ] ] [ tableRow [ tableItem 1 ] [ tableItem 2 ] ] ]

-}
renderTable : CompilerParameters -> Accumulator -> List Expression -> ExprMeta -> Html Msg
renderTable params acc rows meta =
    Html.table
        [ HA.id meta.id
        , HA.style "border-collapse" "collapse"
        , HA.style "margin" "8px 0"
        ]
        [ Html.tbody [] (List.map (renderTableRowExpr params acc) rows) ]


{-| Render a table row expression (internal helper).
-}
renderTableRowExpr : CompilerParameters -> Accumulator -> Expression -> Html Msg
renderTableRowExpr params acc expr =
    case expr of
        Fun "tableRow" items rowMeta ->
            Html.tr [ HA.id rowMeta.id ]
                (List.map (renderTableItemExpr params acc) items)

        _ ->
            Html.tr [] []


{-| Render a table item expression (internal helper).
-}
renderTableItemExpr : CompilerParameters -> Accumulator -> Expression -> Html Msg
renderTableItemExpr params acc expr =
    case expr of
        Fun "tableItem" exprList itemMeta ->
            Html.td
                [ HA.id itemMeta.id
                , HA.style "padding" "4px 8px"
                , HA.style "border" "1px solid #ddd"
                ]
                (renderList params acc exprList)

        _ ->
            Html.td [] []


{-| Render a table row.

    [ tableRow [ tableItem A ] [ tableItem B ] ]

-}
renderTableRow : CompilerParameters -> Accumulator -> List Expression -> ExprMeta -> Html Msg
renderTableRow params acc items meta =
    Html.tr [ HA.id meta.id ]
        (List.map (renderTableItemExpr params acc) items)


{-| Render a table cell.

    [ tableItem cell content ]

-}
renderTableItem : CompilerParameters -> Accumulator -> List Expression -> ExprMeta -> Html Msg
renderTableItem params acc exprList meta =
    Html.td
        [ HA.id meta.id
        , HA.style "padding" "4px 8px"
        , HA.style "border" "1px solid #ddd"
        ]
        (renderList params acc exprList)



-- IMAGES


{-| Render an inline image (fits within text line).

    [ inlineimage https :// example.com / icon.png ]

Max height is 1.5em to fit inline.

-}
renderInlineImage : CompilerParameters -> Accumulator -> List Expression -> ExprMeta -> Html Msg
renderInlineImage params _ args meta =
    case args of
        [ Text src _ ] ->
            Html.img
                [ HA.id meta.id
                , HA.src src
                , HA.style "display" "inline"
                , HA.style "vertical-align" "middle"
                , HA.style "max-height" "1.5em"
                ]
                []

        _ ->
            Html.span [ HA.id meta.id ] [ Html.text "[inlineimage: invalid args]" ]



-- BIBLIOGRAPHY


{-| Render an inline bibliography reference.

    [ bibitem einstein1905 ]

-}
renderBibitem : CompilerParameters -> Accumulator -> List Expression -> ExprMeta -> Html Msg
renderBibitem _ _ args meta =
    let
        content =
            args
                |> List.filterMap getTextContent
                |> String.join " "
    in
    Html.span (Render.Utility.rlSync meta) [ Html.text ("[" ++ content ++ "]") ]



-- SPECIALIZED LINKS


{-| Render a user-defined link (internal navigation).

    [ ulink Section 1 sec1 ]

Last word is the target ID.

-}
renderUlink : CompilerParameters -> Accumulator -> List Expression -> ExprMeta -> Html Msg
renderUlink _ _ args meta =
    let
        argString =
            args |> List.filterMap getTextContent |> String.join " "

        words =
            String.words argString

        n =
            List.length words

        label =
            List.take (n - 1) words |> String.join " "

        target =
            List.drop (n - 1) words |> String.concat
    in
    Html.a
        [ HA.id meta.id
        , HA.href ("#" ++ target)
        , HA.style "color" "#0066cc"
        , HA.style "cursor" "pointer"
        ]
        [ Html.text label ]


{-| Render a reference link with lookup.

    [ reflink Theorem theorem1 ]

Last word is the reference key.

-}
renderReflink : CompilerParameters -> Accumulator -> List Expression -> ExprMeta -> Html Msg
renderReflink _ acc args meta =
    let
        argString =
            args |> List.filterMap getTextContent |> String.join " "

        words =
            String.words argString

        n =
            List.length words

        key =
            List.drop (n - 1) words |> String.concat

        label =
            List.take (n - 1) words |> String.join " "

        targetId =
            Dict.get key acc.reference
                |> Maybe.map .id
                |> Maybe.withDefault ""
    in
    Html.a
        [ HA.id meta.id
        , HA.href ("#" ++ targetId)
        , HE.onClick (SelectId targetId)
        , HA.style "color" "#0066cc"
        , HA.style "font-weight" "600"
        ]
        [ Html.text label ]


{-| Render a cross-site link.

    [ cslink External Page page123 ]

-}
renderCslink : CompilerParameters -> Accumulator -> List Expression -> ExprMeta -> Html Msg
renderCslink _ _ args meta =
    let
        argString =
            args |> List.filterMap getTextContent |> String.join " "

        words =
            String.words argString

        n =
            List.length words

        label =
            List.take (n - 1) words |> String.join " "
    in
    Html.a
        [ HA.id meta.id
        , HA.style "color" "#0066cc"
        , HA.style "cursor" "pointer"
        ]
        [ Html.text label ]



-- SPECIAL/INTERACTIVE (simplified versions)


{-| Render Scheme code (monospace).

    [scheme (+ 1 2)]

-}
renderScheme : CompilerParameters -> Accumulator -> List Expression -> ExprMeta -> Html Msg
renderScheme _ _ args meta =
    let
        content =
            args |> List.filterMap getTextContent |> String.join " "
    in
    Html.code
        (Render.Utility.rlSync meta
            ++ [ HA.style "background-color" "#f5f5f5"
               , HA.style "padding" "2px 4px"
               , HA.style "font-family" "monospace"
               ]
        )
        [ Html.text content ]


renderProgress : CompilerParameters -> Accumulator -> List Expression -> ExprMeta -> Html Msg
renderProgress _ _ args meta =
    let
        argValues =
            args
                |> List.filterMap getTextContent
                |> String.join " "
                |> String.words
                |> List.filterMap String.toInt

        percentageString : Int -> Int -> String
        percentageString num denom =
            let
                ratio =
                    toFloat num / toFloat denom

                percentage_ x =
                    toFloat (round (1000.0 * x)) / 10
            in
            String.fromFloat (percentage_ ratio)
    in
    case argValues of
        [ numerator, denominator ] ->
            let
                data =
                    [ String.fromInt numerator
                    , String.fromInt denominator
                    , percentageString numerator denominator ++ "%"
                    ]
            in
            Html.text (String.join " " data)

        _ ->
            Html.text "invalid args"


{-| Render a compute placeholder (displays as "[compute: ...]").

    [ compute expression ]

-}
renderCompute : CompilerParameters -> Accumulator -> List Expression -> ExprMeta -> Html Msg
renderCompute _ _ args meta =
    let
        content =
            args |> List.filterMap getTextContent |> String.join " "
    in
    Html.span
        (Render.Utility.rlSync meta
            ++ [ HA.style "font-family" "monospace"
               , HA.style "color" "#666"
               ]
        )
        [ Html.text ("[compute: " ++ content ++ "]") ]


{-| Render a data placeholder (displays as "[data: ...]").

    [ data key ]

-}
renderData : CompilerParameters -> Accumulator -> List Expression -> ExprMeta -> Html Msg
renderData _ _ args meta =
    let
        content =
            args |> List.filterMap getTextContent |> String.join " "
    in
    Html.span
        (Render.Utility.rlSync meta
            ++ [ HA.style "font-family" "monospace"
               , HA.style "color" "#666"
               ]
        )
        [ Html.text ("[data: " ++ content ++ "]") ]


{-| Render a button.

    [ button Click Me, action ]

First part before comma is the label.

-}
renderButton : CompilerParameters -> Accumulator -> List Expression -> ExprMeta -> Html Msg
renderButton _ _ args meta =
    let
        content =
            args |> List.filterMap getTextContent |> String.join " "

        labelText =
            content
                |> String.split ","
                |> List.head
                |> Maybe.withDefault "Button"
                |> String.trim
    in
    Html.button
        [ HA.id meta.id
        , HA.style "padding" "4px 8px"
        , HA.style "font-size" "14px"
        , HA.style "cursor" "pointer"
        ]
        [ Html.text labelText ]


{-| Render a horizontal rule.

    [ hrule ]

-}
renderHrule : CompilerParameters -> Accumulator -> List Expression -> ExprMeta -> Html Msg
renderHrule params _ _ meta =
    Html.hr
        [ HA.id meta.id
        , HA.style "width" (String.fromInt params.width ++ "px")
        , HA.style "border" "none"
        , HA.style "border-top" "1px solid #bfbfbf"
        , HA.style "margin" "8px 0"
        ]
        []


{-| Render a mark with anchor.

    [ mark id [ anchor text ] ]

Sets element ID for linking.

-}
renderMark : CompilerParameters -> Accumulator -> List Expression -> ExprMeta -> Html Msg
renderMark params acc args meta =
    let
        withValue =
            getWithValue args

        markId =
            Maybe.withDefault meta.id withValue

        strippedArgs =
            stripWithProperty args

        markClass =
            if withValue /= Nothing then
                [ HA.class "scripta-mark" ]

            else
                []
    in
    Html.span ([ HA.id markId ] ++ markClass) (renderList params acc strippedArgs)


{-| Extract the value from a trailing " with:..." in the last Text node.
-}
getWithValue : List Expression -> Maybe String
getWithValue args =
    case List.reverse args of
        (Text str _) :: _ ->
            case String.indexes " with:" str of
                [] ->
                    Nothing

                indices ->
                    let
                        lastIndex =
                            List.foldl max 0 indices
                    in
                    Just (String.dropLeft (lastIndex + 6) str |> String.trim)

        _ ->
            Nothing


{-| Strip trailing " with:..." from the last Text node in an expression list.
-}
stripWithProperty : List Expression -> List Expression
stripWithProperty args =
    case List.reverse args of
        (Text str m) :: rest ->
            List.reverse (Text (stripWithSuffix str) m :: rest)

        _ ->
            args


stripWithSuffix : String -> String
stripWithSuffix str =
    case String.indexes " with:" str of
        [] ->
            str

        indices ->
            let
                lastIndex =
                    List.foldl max 0 indices
            in
            String.left lastIndex str
