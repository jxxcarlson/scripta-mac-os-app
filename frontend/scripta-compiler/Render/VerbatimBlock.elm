module Render.VerbatimBlock exposing (render)

{-| Render verbatim blocks to HTML.
-}

import Dict exposing (Dict)
import ETeX.Let
import ETeX.Transform
import Either exposing (Either(..))
import Html exposing (Html)
import Html.Attributes as HA
import Html.Events
import Json.Decode
import Parser
import Parser.Expression
import Render.Expression
import Render.Math exposing (DisplayMode(..), mathText)
import Render.Sizing
import Render.Utility exposing (blockIdAndStyle, idAttr)
import SyntaxHighlight
import V3.Types exposing (Accumulator, CompilerParameters, ExpressionBlock, MathMacroDict, Msg(..), Theme(..))


{-| Render a verbatim block by name.
-}
render : CompilerParameters -> Accumulator -> String -> ExpressionBlock -> List (Html Msg) -> List (Html Msg)
render params acc name block children =
    case Dict.get name blockDict of
        Just renderer ->
            renderer params acc name block children

        Nothing ->
            renderDefault params acc name block children


{-| Dictionary of verbatim block renderers.
-}
blockDict : Dict String (CompilerParameters -> Accumulator -> String -> ExpressionBlock -> List (Html Msg) -> List (Html Msg))
blockDict =
    Dict.fromList
        [ ( "math", renderEquation )
        , ( "equation", renderEquation )
        , ( "math", renderEquation )
        , ( "aligned", renderAligned )
        , ( "code", renderCode )
        , ( "verse", renderVerse )
        , ( "mathmacros", renderMathMacros )
        , ( "textmacros", renderTextMacros )
        , ( "datatable", renderDataTable )
        , ( "chart", renderChart )
        , ( "svg", renderSvg )
        , ( "quiver", renderQuiver )
        , ( "tikz", renderTikz )
        , ( "image", renderImage )
        , ( "iframe", renderIframe )
        , ( "load", renderLoad )

        -- Chemistry
        , ( "chem", renderChem )

        -- Arrays/tables
        , ( "array", renderArray )
        , ( "textarray", renderTextArray )
        , ( "csvtable", renderCsvTable )

        -- Raw verbatim
        , ( "verbatim", renderVerbatim )

        -- Book/document info
        , ( "book", renderBook )
        , ( "article", renderArticle )

        -- No-op/hidden blocks
        , ( "settings", renderNothing )
        , ( "load-data", renderNothing )
        , ( "hide", renderNothing )
        , ( "texComment", renderNothing )
        , ( "docinfo", renderNothing )
        , ( "load-files", renderNothing )
        , ( "include", renderNothing )
        , ( "setup", renderNothing )
        ]


{-| Default rendering for unknown verbatim block names.
-}
renderDefault : CompilerParameters -> Accumulator -> String -> ExpressionBlock -> List (Html Msg) -> List (Html Msg)
renderDefault params _ name block _ =
    [ Html.div
        (blockIdAndStyle block
            ++ [ HA.style "margin-bottom" (Render.Sizing.paragraphSpacingPx params.sizing)
               , HA.style "cursor" "pointer"
               ]
            ++ Render.Utility.rlBlockSync block.meta
        )
        [ Html.span [ HA.style "font-weight" "bold", HA.style "color" "purple", HA.style "pointer-events" "none" ]
            [ Html.text ("[verbatim:" ++ name ++ "]") ]
        , Html.pre [ HA.style "margin" "0.5em 0", HA.style "pointer-events" "none" ]
            [ Html.text (getVerbatimContent block) ]
        ]
    ]


{-| Get verbatim content from block body.
-}
getVerbatimContent : ExpressionBlock -> String
getVerbatimContent block =
    case block.body of
        Left content ->
            content

        Right _ ->
            ""



-- MATH BLOCKS


{-| Render a display math block (unnumbered).

    | math
    \int_0^1 x^n dx = \frac{1}{n+1}

-}
renderMath : CompilerParameters -> Accumulator -> String -> ExpressionBlock -> List (Html Msg) -> List (Html Msg)
renderMath params acc _ block _ =
    let
        content =
            getVerbatimContent block
                |> applyMathMacros acc.mathMacroDict
    in
    [ Html.div
        (blockIdAndStyle block
            ++ [ HA.style "text-align" "center"
               , HA.style "margin" "1em 0"
               , HA.style "cursor" "pointer"
               ]
            ++ Render.Utility.rlBlockSync (.meta block)
        )
        [ Html.div [ HA.style "pointer-events" "none" ]
            [ mathText params.editCount { id = block.meta.id, begin = block.meta.contentBegin, end = block.meta.contentEnd } DisplayMathMode content ]
        ]
    ]


{-| Render a numbered equation block.

    | equation
    E = mc^2

Supports alignment with & for multi-line equations:

    | equation
    a &= b + c \\
    &= d

-}
renderEquation : CompilerParameters -> Accumulator -> String -> ExpressionBlock -> List (Html Msg) -> List (Html Msg)
renderEquation params acc _ block _ =
    let
        raw =
            getVerbatimContent block

        -- Resolve LET/IN blocks first, before line-by-line processing
        reduced =
            ETeX.Let.reduce raw

        -- Process content: if it contains &, handle alignment
        -- But first check if & only appears inside environments (e.g. pmatrix)
        processedContent =
            if hasTopLevelAmpersand reduced then
                wrapInAligned (processAlignedLines acc.mathMacroDict reduced)

            else
                applyMathMacros acc.mathMacroDict reduced

        content =
            processedContent

        -- Get equation number from block properties (set by transformBlock when label is present)
        equationNumber =
            Dict.get "equation-number" block.properties |> Maybe.withDefault ""
    in
    [ Html.div
        (blockIdAndStyle block
            ++ [ HA.style "display" "flex"
               , HA.style "justify-content" "center"
               , HA.style "align-items" "center"
               , HA.style "margin" "1em 0"
               , HA.style "cursor" "pointer"
               ]
            ++ Render.Utility.rlBlockSync (.meta block)
        )
        [ Html.div [ HA.style "flex" "1" ] []
        , Html.div [ HA.style "pointer-events" "none" ]
            [ mathText params.editCount { id = block.meta.id, begin = block.meta.contentBegin, end = block.meta.contentEnd } DisplayMathMode content ]
        , Html.div
            [ HA.style "flex" "1"
            , HA.style "text-align" "right"
            , HA.style "padding-right" "1em"
            , HA.style "pointer-events" "none"
            ]
            [ Html.text
                (if equationNumber /= "" then
                    "(" ++ equationNumber ++ ")"

                 else
                    ""
                )
            ]
        ]
    ]


{-| Render an aligned math block (unnumbered, multi-line).

    | aligned
    a &= b + c \\
    &= d + e

-}
renderAligned : CompilerParameters -> Accumulator -> String -> ExpressionBlock -> List (Html Msg) -> List (Html Msg)
renderAligned params acc _ block _ =
    let
        content =
            getVerbatimContent block
                |> processAlignedLines acc.mathMacroDict
                |> wrapInAligned
    in
    [ Html.div
        (blockIdAndStyle block
            ++ [ HA.style "text-align" "center"
               , HA.style "margin" "1em 0"
               , HA.style "cursor" "pointer"
               ]
            ++ Render.Utility.rlBlockSync (.meta block)
        )
        [ Html.div [ HA.style "pointer-events" "none" ]
            [ mathText params.editCount { id = block.meta.id, begin = block.meta.contentBegin, end = block.meta.contentEnd } DisplayMathMode content ]
        ]
    ]


wrapInAligned : String -> String
wrapInAligned content =
    "\\begin{aligned}\n" ++ content ++ "\n\\end{aligned}"


{-| Process aligned math content line-by-line.

Splits into lines, strips trailing backslashes, applies ETeX transformation
to each line individually, then rejoins with `\\\\` separators.
This avoids two problems with processing the whole string at once:

1.  Line breaks are lost when evalStr concatenates parsed results
2.  Trailing `\\\\` causes the ETeX parser to fail

-}
processAlignedLines : MathMacroDict -> String -> String
processAlignedLines macroDict content =
    let
        stripTrailingBackslashes line =
            if String.endsWith "\\\\" line then
                String.dropRight 2 line |> String.trimRight

            else
                line

        lines =
            content
                |> String.lines
                |> List.map String.trim
                |> List.filter (not << String.isEmpty)
                |> collapseEnvironments
                |> List.map (stripTrailingBackslashes >> applyMathMacros macroDict)
    in
    case List.reverse lines of
        [] ->
            ""

        lastLine :: restReversed ->
            (List.reverse restReversed |> List.map (\line -> line ++ " \\\\"))
                ++ [ lastLine ]
                |> String.join "\n"


{-| Check if raw content has & characters outside of \\begin{...}...\\end{...} environments.
-}
hasTopLevelAmpersand : String -> Bool
hasTopLevelAmpersand raw =
    raw
        |> String.lines
        |> List.map String.trim
        |> List.filter (not << String.isEmpty)
        |> collapseEnvironments
        |> List.filter (not << isCollapsedEnvironment)
        |> List.any (String.contains "&")


{-| Check if a line is a fully collapsed environment (starts with \\begin and ends with \\end).
-}
isCollapsedEnvironment : String -> Bool
isCollapsedEnvironment line =
    case extractBeginEnv line of
        Just name ->
            String.endsWith ("\\end{" ++ name ++ "}") line

        Nothing ->
            False


{-| Collapse multi-line LaTeX environments into single lines.

For example, lines like:

    \\begin{pmatrix}
    2 & 1 \\\\
    1 & 2
    \\end{pmatrix}

become a single line:

    \\begin{pmatrix} 2 & 1 \\\\ 1 & 2 \\end{pmatrix}

This preserves the environment structure when the surrounding code
processes lines individually for aligned-equation formatting.

-}
collapseEnvironments : List String -> List String
collapseEnvironments lines =
    collapseEnvironmentsHelper lines [] Nothing []


collapseEnvironmentsHelper : List String -> List String -> Maybe String -> List String -> List String
collapseEnvironmentsHelper remaining accumulated envName result =
    case remaining of
        [] ->
            -- Flush any accumulated lines if we hit the end while inside an environment
            case envName of
                Nothing ->
                    List.reverse result

                Just _ ->
                    List.reverse (String.join " " (List.reverse accumulated) :: result)

        line :: rest ->
            case envName of
                Nothing ->
                    -- Not inside an environment: check if this line starts one
                    case extractBeginEnv line of
                        Just name ->
                            if String.contains ("\\end{" ++ name ++ "}") line then
                                -- Environment opens and closes on same line, pass through
                                collapseEnvironmentsHelper rest [] Nothing (line :: result)

                            else
                                -- Start accumulating
                                collapseEnvironmentsHelper rest [ line ] (Just name) result

                        Nothing ->
                            -- Regular line, pass through
                            collapseEnvironmentsHelper rest [] Nothing (line :: result)

                Just name ->
                    -- Inside an environment: accumulate until we see \end{name}
                    if String.contains ("\\end{" ++ name ++ "}") line then
                        -- End of environment: collapse all accumulated lines into one
                        -- But check if there's another \begin{} after the \end{} on the same line
                        let
                            endTag =
                                "\\end{" ++ name ++ "}"

                            ( beforeEnd, afterEnd ) =
                                splitOnFirst endTag line

                            envLine =
                                beforeEnd ++ endTag

                            collapsed =
                                String.join " " (List.reverse (envLine :: accumulated))

                            newRemaining =
                                if String.isEmpty (String.trim afterEnd) then
                                    rest

                                else
                                    String.trim afterEnd :: rest
                        in
                        collapseEnvironmentsHelper newRemaining [] Nothing (collapsed :: result)

                    else
                        -- Still inside, keep accumulating
                        collapseEnvironmentsHelper rest (line :: accumulated) envName result


{-| Extract the environment name from a \\begin{name} line, if present.
-}
extractBeginEnv : String -> Maybe String
extractBeginEnv line =
    if String.contains "\\begin{" line then
        let
            afterBegin =
                line
                    |> String.split "\\begin{"
                    |> List.drop 1
                    |> List.head
                    |> Maybe.withDefault ""
        in
        case String.split "}" afterBegin of
            name :: _ ->
                if String.isEmpty name then
                    Nothing

                else
                    Just name

            [] ->
                Nothing

    else
        Nothing


{-| Split a string on the first occurrence of a separator.
Returns ( before, after ) where the separator is excluded from both.
-}
splitOnFirst : String -> String -> ( String, String )
splitOnFirst sep str =
    case String.indexes sep str of
        idx :: _ ->
            ( String.left idx str
            , String.dropLeft (idx + String.length sep) str
            )

        [] ->
            ( str, "" )


{-| Transform ETeX notation to LaTeX using ETeX.Transform.evalStr.

Converts notation like `int_0^2`, `frac(1,n+1)` to `\int_0^2`, `\frac{1}{n+1}`.
Also expands user-defined macros from mathmacros blocks.

-}
applyMathMacros : MathMacroDict -> String -> String
applyMathMacros macroDict content =
    ETeX.Transform.evalStr macroDict content



-- CODE BLOCKS


{-| Render a code block with syntax highlighting.

    | code python
    def hello():
        print("Hello!")

If a supported language is specified as an argument, syntax highlighting
is applied using elm-syntax-highlight. Supported languages: elm, javascript,
xml, css, python, sql, json, nix, kotlin, go.

If no language or an unsupported language is given, falls back to plain
monospace rendering.

Properties:

  - linenumbers: Show line numbers (presence enables, e.g. `linenumbers:yes`)
  - indent: Left/right margin indentation in em units

-}
renderCode : CompilerParameters -> Accumulator -> String -> ExpressionBlock -> List (Html Msg) -> List (Html Msg)
renderCode params _ _ block _ =
    let
        language =
            List.head block.args |> Maybe.withDefault ""

        content =
            getVerbatimContent block

        indentation =
            case Dict.get "indent" block.properties of
                Nothing ->
                    "0em"

                Just k ->
                    k ++ "em"

        showLineNumbers =
            Dict.member "linenumbers" block.properties

        lineNumberStart =
            if showLineNumbers then
                Just 1

            else
                Nothing

        theme =
            case params.theme of
                Light ->
                    SyntaxHighlight.gitHub

                Dark ->
                    SyntaxHighlight.monokai
    in
    case languageParser language of
        Just parser ->
            case parser content of
                Ok hcode ->
                    [ Html.div
                        (blockIdAndStyle block
                            ++ [ HA.style "margin" "1em 0"
                               , HA.style "cursor" "pointer"
                               ]
                            ++ Render.Utility.rlBlockSync block.meta
                        )
                        ([ SyntaxHighlight.useTheme theme
                         ]
                            ++ (if showLineNumbers then
                                    [ lineNumberCss ]

                                else
                                    []
                               )
                            ++ [ Html.div
                                    [ HA.style "margin-left" indentation
                                    , HA.style "margin-right" indentation
                                    , HA.style "border-radius" "4px"
                                    , HA.style "overflow-x" "auto"
                                    , HA.style "font-size" (Render.Sizing.codeSize params.sizing)
                                    , HA.style "pointer-events" "none"
                                    ]
                                    [ SyntaxHighlight.toBlockHtml lineNumberStart hcode ]
                               ]
                        )
                    ]

                Err _ ->
                    renderCodePlain params block content indentation

        Nothing ->
            renderCodePlain params block content indentation


{-| Plain code rendering fallback for unsupported or missing languages.
-}
renderCodePlain : CompilerParameters -> ExpressionBlock -> String -> String -> List (Html Msg)
renderCodePlain params block content indentation =
    [ Html.div
        (blockIdAndStyle block
            ++ [ HA.style "margin" "1em 0"
               , HA.style "cursor" "pointer"
               ]
            ++ Render.Utility.rlBlockSync block.meta
        )
        [ Html.pre
            [ HA.style "background-color"
                (case params.theme of
                    Light ->
                        "#f5f5f5"

                    Dark ->
                        "#1e1e1e"
                )
            , HA.style "padding" "1em"
            , HA.style "margin-left" indentation
            , HA.style "margin-right" indentation
            , HA.style "border-radius" "4px"
            , HA.style "overflow-x" "auto"
            , HA.style "font-family" "monospace"
            , HA.style "font-size" (Render.Sizing.codeSize params.sizing)
            , HA.style "pointer-events" "none"
            ]
            [ Html.code []
                [ Html.text content ]
            ]
        ]
    ]


{-| Map a language name string to its SyntaxHighlight parser function.
Returns Nothing for unsupported or empty language strings.
-}
languageParser : String -> Maybe (String -> Result (List Parser.DeadEnd) SyntaxHighlight.HCode)
languageParser lang =
    case String.toLower lang of
        "elm" ->
            Just SyntaxHighlight.elm

        "javascript" ->
            Just SyntaxHighlight.javascript

        "js" ->
            Just SyntaxHighlight.javascript

        "xml" ->
            Just SyntaxHighlight.xml

        "html" ->
            Just SyntaxHighlight.xml

        "css" ->
            Just SyntaxHighlight.css

        "python" ->
            Just SyntaxHighlight.python

        "sql" ->
            Just SyntaxHighlight.sql

        "json" ->
            Just SyntaxHighlight.json

        "nix" ->
            Just SyntaxHighlight.nix

        _ ->
            Nothing


{-| CSS for displaying line numbers on `.elmsh-line` elements.
The elm-syntax-highlight library sets `data-elmsh-lc` on each line div
but does not include the CSS to render it.
-}
lineNumberCss : Html msg
lineNumberCss =
    Html.node "style"
        []
        [ Html.text
            (String.join "\n"
                [ ".elmsh-line::before {"
                , "  content: attr(data-elmsh-lc);"
                , "  display: inline-block;"
                , "  text-align: right;"
                , "  width: 2.5em;"
                , "  margin-right: 1em;"
                , "  padding-right: 0.5em;"
                , "  border-right: 1px solid rgba(128, 128, 128, 0.4);"
                , "  color: rgba(128, 128, 128, 0.6);"
                , "  user-select: none;"
                , "}"
                ]
            )
        ]



-- VERSE


{-| Render a verse/poetry block preserving line breaks.

    | verse
    Roses are red,
    Violets are blue,
    Sugar is sweet,
    And so are you.

-}
renderVerse : CompilerParameters -> Accumulator -> String -> ExpressionBlock -> List (Html Msg) -> List (Html Msg)
renderVerse params acc str block _ =
    let
        content =
            getVerbatimContent block

        lines =
            String.split "\n" content

        parsedContent : List (List V3.Types.Expression)
        parsedContent =
            List.indexedMap (\k -> Parser.Expression.parse k) lines

        htmlContent : List (Html Msg)
        htmlContent =
            List.map (Render.Expression.renderList params acc >> Html.div []) parsedContent
    in
    [ Html.div
        (blockIdAndStyle block
            ++ [ HA.style "margin" "1em 2em"

               --, HA.style "font-style" "italic"
               , HA.style "white-space" "pre-wrap"
               , HA.style "cursor" "pointer"
               ]
            ++ Render.Utility.rlBlockSync block.meta
        )
        [ Html.div [ HA.style "pointer-events" "none" ] htmlContent ]
    ]



-- MACRO DEFINITIONS


{-| Define math macros for use in math blocks. Hidden in output.

    | mathmacros
    \newcommand{\R}{\mathbb{R}}
    \newcommand{\norm}[1]{\left\| #1 \right\|}

-}
renderMathMacros : CompilerParameters -> Accumulator -> String -> ExpressionBlock -> List (Html Msg) -> List (Html Msg)
renderMathMacros _ _ _ block _ =
    [ Html.div [ idAttr block.meta.id, HA.style "display" "none" ] [] ]


{-| Define text macros for use in document. Hidden in output.

    | textmacros
    \newcommand{\version}{2.0}

-}
renderTextMacros : CompilerParameters -> Accumulator -> String -> ExpressionBlock -> List (Html Msg) -> List (Html Msg)
renderTextMacros _ _ _ block _ =
    [ Html.div [ idAttr block.meta.id, HA.style "display" "none" ] [] ]



-- DATA AND CHARTS


{-| Render raw data in a preformatted block.

    | datatable
    x, y, z
    1, 2, 3
    4, 5, 6

-}
renderDataTable : CompilerParameters -> Accumulator -> String -> ExpressionBlock -> List (Html Msg) -> List (Html Msg)
renderDataTable params _ _ block _ =
    let
        content =
            getVerbatimContent block
    in
    [ Html.div
        (blockIdAndStyle block
            ++ [ HA.style "margin" "1em 0"
               , HA.style "cursor" "pointer"
               ]
            ++ Render.Utility.rlBlockSync block.meta
        )
        [ Html.pre [ HA.style "font-family" "monospace", HA.style "pointer-events" "none" ]
            [ Html.text content ]
        ]
    ]


{-| Render a chart (placeholder, requires external JS library).

    | chart
    type: bar
    data: ...

-}
renderChart : CompilerParameters -> Accumulator -> String -> ExpressionBlock -> List (Html Msg) -> List (Html Msg)
renderChart params _ _ block _ =
    [ Html.div
        (blockIdAndStyle block
            ++ [ HA.class "chart-placeholder"
               , HA.style "margin" "1em 0"
               , HA.style "min-height" "200px"
               , HA.style "border" "1px dashed #ccc"
               , HA.style "cursor" "pointer"
               ]
            ++ Render.Utility.rlBlockSync block.meta
        )
        [ Html.span [ HA.style "pointer-events" "none" ] [ Html.text "[Chart]" ] ]
    ]



-- GRAPHICS


{-| Render inline SVG content (placeholder, requires JS integration).

    | svg
    <svg width="100" height="100">
      <circle cx="50" cy="50" r="40" fill="red" />
    </svg>

-}
renderSvg : CompilerParameters -> Accumulator -> String -> ExpressionBlock -> List (Html Msg) -> List (Html Msg)
renderSvg params _ _ block _ =
    [ Html.div
        (blockIdAndStyle block
            ++ [ HA.style "text-align" "center"
               , HA.style "margin" "1em 0"
               , HA.class "svg-container"
               , HA.style "cursor" "pointer"
               ]
            ++ Render.Utility.rlBlockSync block.meta
        )
        [ Html.pre
            [ HA.style "font-family" "monospace"
            , HA.style "font-size" (Render.Sizing.codeSize params.sizing)
            , HA.style "pointer-events" "none"
            ]
            [ Html.text "[SVG content - requires JS integration]" ]
        ]
    ]


{-| Render a Quiver commutative diagram.

The image URL comes from the `image` property (without protocol prefix).

Properties:

  - image: Image path (<https://> is prepended automatically)
  - width: Image width in pixels (default: panel width)
  - caption: Caption text displayed below the diagram

Example:

    | quiver
    | image:imagedelivery.net/example/public
    | width:400
    | caption:Commutative diagram
    ---
    \[\begin{tikzcd} A \arrow[r] & B \end{tikzcd}\]

-}
renderQuiver : CompilerParameters -> Accumulator -> String -> ExpressionBlock -> List (Html Msg) -> List (Html Msg)
renderQuiver params _ _ block _ =
    let
        url =
            Dict.get "image" block.properties
                |> Maybe.map (\path -> "https://" ++ path)
                |> Maybe.withDefault ""

        width =
            case Dict.get "width" block.properties of
                Nothing ->
                    String.fromInt params.width ++ "px"

                Just w ->
                    case String.toInt w of
                        Just _ ->
                            w ++ "px"

                        Nothing ->
                            String.fromInt params.width ++ "px"

        caption =
            Dict.get "caption" block.properties

        captionElement =
            case caption of
                Just cap ->
                    [ Html.div
                        [ HA.style "font-size" "0.9em"
                        , HA.style "font-style" "italic"
                        , HA.style "margin-top" "0.5em"
                        , HA.style "color" "#555"
                        ]
                        [ Html.text cap ]
                    ]

                Nothing ->
                    []

        isExpandable =
            List.member "expandable" block.args

        imageElement =
            Html.img
                [ HA.src url
                , HA.style "max-width" width
                , HA.style "pointer-events" "none"
                ]
                []

        imageDisplay =
            if isExpandable then
                Html.span
                    [ HA.style "cursor" "zoom-in"
                    , HA.style "display" "inline-block"
                    , Html.Events.stopPropagationOn "click"
                        (Json.Decode.succeed ( ExpandImage url, True ))
                    ]
                    [ imageElement ]

            else
                imageElement
    in
    if url == "" then
        [ Html.div
            (blockIdAndStyle block
                ++ [ HA.style "margin" "1em 0"
                   , HA.style "cursor" "pointer"
                   ]
                ++ Render.Utility.rlBlockSync block.meta
            )
            [ Html.span [ HA.style "pointer-events" "none" ] [ Html.text "[Quiver: no image URL]" ] ]
        ]

    else
        [ Html.div
            (blockIdAndStyle block
                ++ [ HA.style "text-align" "center"
                   , HA.style "margin" "1em 0"
                   , HA.style "cursor" "pointer"
                   ]
                ++ Render.Utility.rlBlockSync block.meta
            )
            (imageDisplay
                :: captionElement
            )
        ]


{-| Render a TikZ diagram as an image.

The image URL comes from the `image` property (without protocol prefix).

Properties:

  - image: Image path (<https://> is prepended automatically)
  - width: Image width in pixels (default: panel width)
  - caption: Caption text displayed below the diagram

Example:

    | tikz
    | image:imagedelivery.net/example/public
    | width:400
    | caption:A triangle
    ---
    \begin{tikzpicture}
    \draw (0,0) -- (1,1) -- (2,0) -- cycle;
    \end{tikzpicture}

-}
renderTikz : CompilerParameters -> Accumulator -> String -> ExpressionBlock -> List (Html Msg) -> List (Html Msg)
renderTikz params _ _ block _ =
    let
        url =
            Dict.get "image" block.properties
                |> Maybe.map (\path -> "https://" ++ path)
                |> Maybe.withDefault ""

        width =
            case Dict.get "width" block.properties of
                Nothing ->
                    String.fromInt params.width ++ "px"

                Just w ->
                    case String.toInt w of
                        Just _ ->
                            w ++ "px"

                        Nothing ->
                            String.fromInt params.width ++ "px"

        caption =
            Dict.get "caption" block.properties

        captionElement =
            case caption of
                Just cap ->
                    [ Html.div
                        [ HA.style "font-size" "0.9em"
                        , HA.style "font-style" "italic"
                        , HA.style "margin-top" "0.5em"
                        , HA.style "color" "#555"
                        ]
                        [ Html.text cap ]
                    ]

                Nothing ->
                    []

        isExpandable =
            List.member "expandable" block.args

        imageElement =
            Html.img
                [ HA.src url
                , HA.style "max-width" width
                , HA.style "pointer-events" "none"
                ]
                []

        imageDisplay =
            if isExpandable then
                Html.span
                    [ HA.style "cursor" "zoom-in"
                    , HA.style "display" "inline-block"
                    , Html.Events.stopPropagationOn "click"
                        (Json.Decode.succeed ( ExpandImage url, True ))
                    ]
                    [ imageElement ]

            else
                imageElement
    in
    if url == "" then
        [ Html.div
            (blockIdAndStyle block
                ++ [ HA.style "margin" "1em 0"
                   , HA.style "cursor" "pointer"
                   ]
                ++ Render.Utility.rlBlockSync block.meta
            )
            [ Html.span [ HA.style "pointer-events" "none" ] [ Html.text "[TikZ: no image URL]" ] ]
        ]

    else
        [ Html.div
            (blockIdAndStyle block
                ++ [ HA.style "text-align" "center"
                   , HA.style "margin" "1em 0"
                   , HA.style "cursor" "pointer"
                   ]
                ++ Render.Utility.rlBlockSync block.meta
            )
            (imageDisplay
                :: captionElement
            )
        ]



-- MEDIA


{-| Render an image block.

    | image [arguments] [properties]
    <url>

Arguments:

  - expandable: Click thumbnail to open full-size overlay; click overlay to close

Properties:

  - width: Image width. Values: pixel number, "fill" (100%), or "to-edges" (120% of panel)
  - float: Float image with text wrap. Values: "left" or "right"
  - ypadding: Vertical padding in pixels (default 18, ignored when floated)
  - description: Alt text for accessibility
  - figure: Figure number (displays "Figure N")
  - caption: Caption text (italic, below image)

Examples:

    | image
    https://example.com/photo.jpg

    | image expandable width:400 caption:A lovely sunset
    https://example.com/sunset.jpg

    | image float:left width:200
    https://example.com/portrait.jpg

-}
renderImage : CompilerParameters -> Accumulator -> String -> ExpressionBlock -> List (Html Msg) -> List (Html Msg)
renderImage params _ _ block _ =
    let
        -- For verbatim blocks, the URL is in body (Left String), not firstLine
        src =
            case block.body of
                Left content ->
                    String.trim content

                Right _ ->
                    block.firstLine

        -- Width: supports "fill", "to-edges", or pixel value
        widthStyle =
            case Dict.get "width" block.properties of
                Nothing ->
                    [ HA.style "max-width" (String.fromInt params.width ++ "px") ]

                Just "fill" ->
                    [ HA.style "width" "100%" ]

                Just "to-edges" ->
                    [ HA.style "max-width" (String.fromInt (round (1.2 * toFloat params.width)) ++ "px") ]

                Just w ->
                    case String.toInt w of
                        Just pixels ->
                            [ HA.style "max-width" (String.fromInt pixels ++ "px") ]

                        Nothing ->
                            [ HA.style "max-width" (String.fromInt params.width ++ "px") ]

        -- Vertical padding (used for non-floated images)
        ypadding =
            Dict.get "ypadding" block.properties
                |> Maybe.andThen String.toInt
                |> Maybe.withDefault 18

        -- Float: left or right (small top margin to align with text baseline)
        floatStyle =
            case Dict.get "float" block.properties of
                Just "left" ->
                    [ HA.style "float" "left"
                    , HA.style "margin-right" "1em"
                    , HA.style "margin-top" "4px"
                    , HA.style "margin-bottom" "0.5em"
                    ]

                Just "right" ->
                    [ HA.style "float" "right"
                    , HA.style "margin-left" "1em"
                    , HA.style "margin-top" "4px"
                    , HA.style "margin-bottom" "0.5em"
                    ]

                _ ->
                    [ HA.style "text-align" "center"
                    , HA.style "padding-top" (String.fromInt ypadding ++ "px")
                    , HA.style "padding-bottom" (String.fromInt ypadding ++ "px")
                    ]

        -- Description (alt text)
        description =
            Dict.get "description" block.properties
                |> Maybe.withDefault ""

        -- Figure label and caption
        figureLabel =
            case ( Dict.get "figure" block.properties, Dict.get "caption" block.properties ) of
                ( Nothing, Nothing ) ->
                    Html.text ""

                ( Nothing, Just cap ) ->
                    Html.div
                        [ HA.style "font-size" "0.9em"
                        , HA.style "font-style" "italic"
                        , HA.style "margin-top" "0.5em"
                        , HA.style "color" "#555"
                        ]
                        [ Html.text cap ]

                ( Just fig, Nothing ) ->
                    Html.div
                        [ HA.style "font-size" "0.9em"
                        , HA.style "margin-top" "0.5em"
                        , HA.style "color" "#555"
                        ]
                        [ Html.text ("Figure " ++ fig) ]

                ( Just fig, Just cap ) ->
                    Html.div
                        [ HA.style "font-size" "0.9em"
                        , HA.style "margin-top" "0.5em"
                        , HA.style "color" "#555"
                        ]
                        [ Html.span [ HA.style "font-weight" "bold" ] [ Html.text ("Figure " ++ fig ++ ". ") ]
                        , Html.span [ HA.style "font-style" "italic" ] [ Html.text cap ]
                        ]

        -- The image element
        imageElement =
            Html.img
                ([ HA.src src
                 , HA.alt description
                 ]
                    ++ widthStyle
                )
                []

        -- Check if expandable (as an argument)
        isExpandable =
            List.member "expandable" block.args

        -- Expandable: click to show overlay via Elm message
        expandableImage =
            Html.span
                [ HA.style "cursor" "zoom-in"
                , HA.style "display" "inline-block"
                , Html.Events.stopPropagationOn "click"
                    (Json.Decode.succeed ( ExpandImage src, True ))
                ]
                [ imageElement ]

        -- Choose which image display to use
        imageDisplay =
            if isExpandable then
                expandableImage

            else
                imageElement
    in
    [ Html.div
        (blockIdAndStyle block
            ++ floatStyle
            ++ Render.Utility.rlBlockSync block.meta
        )
        [ imageDisplay
        , figureLabel
        ]
    ]


{-| Render an embedded iframe.

    | iframe
    https://www.youtube.com/embed/dQw4w9WgXcQ

Properties:

  - width: Width in pixels (default: panel width)
  - height: Height in pixels (default: 400)

-}
renderIframe : CompilerParameters -> Accumulator -> String -> ExpressionBlock -> List (Html Msg) -> List (Html Msg)
renderIframe params _ _ block _ =
    let
        src =
            block.firstLine

        width =
            Dict.get "width" block.properties
                |> Maybe.andThen String.toInt
                |> Maybe.withDefault params.width

        height =
            Dict.get "height" block.properties
                |> Maybe.andThen String.toInt
                |> Maybe.withDefault 400
    in
    [ Html.div
        (blockIdAndStyle block
            ++ [ HA.style "text-align" "center"
               , HA.style "margin" "1em 0"
               ]
        )
        [ Html.iframe
            [ HA.src src
            , HA.style "width" (String.fromInt width ++ "px")
            , HA.style "height" (String.fromInt height ++ "px")
            , HA.style "border" "none"
            ]
            []
        ]
    ]



-- INCLUDES


{-| Load external content (processed at higher level, hidden in output).

    | load
    /path/to/file.md

-}
renderLoad : CompilerParameters -> Accumulator -> String -> ExpressionBlock -> List (Html Msg) -> List (Html Msg)
renderLoad _ _ _ block _ =
    [ Html.div [ idAttr block.meta.id, HA.style "display" "none" ] [] ]



-- CHEMISTRY


{-| Render chemical equations using mhchem notation.

    | chem
    2H2 + O2 -> 2H2O

-}
renderChem : CompilerParameters -> Accumulator -> String -> ExpressionBlock -> List (Html Msg) -> List (Html Msg)
renderChem params acc _ block children =
    let
        content =
            getVerbatimContent block
                |> (\s -> "\\ce{" ++ s ++ "}")
                |> applyMathMacros acc.mathMacroDict
    in
    [ Html.div
        (blockIdAndStyle block
            ++ [ HA.style "text-align" "center"
               , HA.style "margin" "1em 0"
               , HA.style "cursor" "pointer"
               ]
            ++ Render.Utility.rlBlockSync block.meta
        )
        [ Html.div [ HA.style "pointer-events" "none" ]
            [ mathText params.editCount { id = block.meta.id, begin = block.meta.contentBegin, end = block.meta.contentEnd } DisplayMathMode content ]
        ]
    ]



-- ARRAYS


{-| Render a LaTeX-style math array.

    | array ccc
    a & b & c \\
    d & e & f

Arguments:

  - Column format (e.g., "ccc" for 3 centered columns, "lcr" for left/center/right)

-}
renderArray : CompilerParameters -> Accumulator -> String -> ExpressionBlock -> List (Html Msg) -> List (Html Msg)
renderArray params acc _ block _ =
    let
        format =
            List.head block.args |> Maybe.withDefault "c"

        content =
            getVerbatimContent block
                |> applyMathMacros acc.mathMacroDict

        -- Wrap in array environment
        arrayContent =
            "\\begin{array}{" ++ format ++ "}\n" ++ content ++ "\n\\end{array}"
    in
    [ Html.div
        (blockIdAndStyle block
            ++ [ HA.style "text-align" "center"
               , HA.style "margin" "1em 0"
               , HA.style "cursor" "pointer"
               ]
            ++ Render.Utility.rlBlockSync block.meta
        )
        [ Html.div [ HA.style "pointer-events" "none" ]
            [ mathText params.editCount { id = block.meta.id, begin = block.meta.contentBegin, end = block.meta.contentEnd } DisplayMathMode arrayContent ]
        ]
    ]


{-| Render a text table with & as column separator.

    | textarray
    Name & Age & City
    Alice & 30 & NYC
    Bob & 25 & LA

Also available as `| table`.

-}
renderTextArray : CompilerParameters -> Accumulator -> String -> ExpressionBlock -> List (Html Msg) -> List (Html Msg)
renderTextArray params _ _ block _ =
    let
        content =
            getVerbatimContent block

        rows =
            content
                |> String.lines
                |> List.filter (\line -> String.trim line /= "")
                |> List.map parseTableRow
    in
    [ Html.div
        (blockIdAndStyle block
            ++ [ HA.style "margin" "1em 0"
               , HA.style "cursor" "pointer"
               ]
            ++ Render.Utility.rlBlockSync block.meta
        )
        [ Html.table
            [ HA.style "border-collapse" "collapse"
            , HA.style "margin" "0 auto"
            , HA.style "pointer-events" "none"
            ]
            [ Html.tbody [] (List.map renderTextArrayRow rows) ]
        ]
    ]


parseTableRow : String -> List String
parseTableRow line =
    String.split "&" line
        |> List.map String.trim


renderTextArrayRow : List String -> Html Msg
renderTextArrayRow cells =
    Html.tr []
        (List.map
            (\cell ->
                Html.td
                    [ HA.style "padding" "4px 12px"
                    , HA.style "border" "1px solid #ddd"
                    ]
                    [ Html.text cell ]
            )
            cells
        )


{-| Render a CSV table with comma-separated values.

    | csvtable title:Sales Data
    Product,Q1,Q2,Q3
    Widgets,100,150,200
    Gadgets,50,75,100

Properties:

  - title: Optional table title

-}
renderCsvTable : CompilerParameters -> Accumulator -> String -> ExpressionBlock -> List (Html Msg) -> List (Html Msg)
renderCsvTable params _ _ block _ =
    let
        content =
            getVerbatimContent block

        title =
            Dict.get "title" block.properties

        rows =
            content
                |> String.lines
                |> List.filter (\line -> String.trim line /= "")
                |> List.map parseCsvRow

        headerRow =
            List.head rows |> Maybe.withDefault []

        dataRows =
            List.drop 1 rows
    in
    [ Html.div
        (blockIdAndStyle block
            ++ [ HA.style "margin" "1em 0"
               , HA.style "cursor" "pointer"
               ]
            ++ Render.Utility.rlBlockSync block.meta
        )
        [ Html.div [ HA.style "pointer-events" "none" ]
            (case title of
                Just t ->
                    [ Html.div [ HA.style "font-weight" "bold", HA.style "margin-bottom" "0.5em" ] [ Html.text t ]
                    , renderCsvTableHtml headerRow dataRows
                    ]

                Nothing ->
                    [ renderCsvTableHtml headerRow dataRows ]
            )
        ]
    ]


parseCsvRow : String -> List String
parseCsvRow line =
    String.split "," line
        |> List.map String.trim


renderCsvTableHtml : List String -> List (List String) -> Html Msg
renderCsvTableHtml headers rows =
    Html.table
        [ HA.style "border-collapse" "collapse" ]
        [ Html.thead []
            [ Html.tr []
                (List.map
                    (\h ->
                        Html.th
                            [ HA.style "padding" "4px 12px"
                            , HA.style "border-bottom" "2px solid #333"
                            , HA.style "text-align" "left"
                            ]
                            [ Html.text h ]
                    )
                    headers
                )
            ]
        , Html.tbody []
            (List.map
                (\row ->
                    Html.tr []
                        (List.map
                            (\cell ->
                                Html.td
                                    [ HA.style "padding" "4px 12px"
                                    , HA.style "border-bottom" "1px solid #ddd"
                                    ]
                                    [ Html.text cell ]
                            )
                            row
                        )
                )
                rows
            )
        ]



-- RAW VERBATIM


{-| Render raw verbatim text in a preformatted block.

    | verbatim
    This text is displayed exactly as written,
    with all spacing and formatting preserved.

-}
renderVerbatim : CompilerParameters -> Accumulator -> String -> ExpressionBlock -> List (Html Msg) -> List (Html Msg)
renderVerbatim params _ _ block _ =
    let
        content =
            getVerbatimContent block
    in
    [ Html.div
        (blockIdAndStyle block
            ++ [ HA.style "margin" "1em 0"
               , HA.style "cursor" "pointer"
               ]
            ++ Render.Utility.rlBlockSync block.meta
        )
        [ Html.pre
            [ HA.style "font-family" "monospace"
            , HA.style "font-size" (Render.Sizing.codeSize params.sizing)
            , HA.style "background-color" "#f5f5f5"
            , HA.style "padding" "1em"
            , HA.style "padding-left" "2em"
            , HA.style "white-space" "pre-wrap"
            , HA.style "pointer-events" "none"
            ]
            [ Html.text content ]
        ]
    ]


{-| Render a book block.

    | book
    title: Nature
    author: Phineas Peabody
    publication-date: 2026

Renders as:

    Nature

    by Phineas Peabody

-}
renderBook : CompilerParameters -> Accumulator -> String -> ExpressionBlock -> List (Html Msg) -> List (Html Msg)
renderBook params _ _ block _ =
    let
        title =
            Dict.get "title" block.properties |> Maybe.withDefault "Untitled"

        author =
            Dict.get "author" block.properties |> Maybe.withDefault ""

        authorLine =
            if author /= "" then
                [ Html.div
                    [ HA.style "margin-top" "0.5em"
                    , HA.style "font-size" "1.2em"
                    ]
                    [ Html.text ("by " ++ author) ]
                ]

            else
                []
    in
    [ Html.div
        (blockIdAndStyle block
            ++ [ HA.style "text-align" "center"
               , HA.style "margin" "2em 0"
               , HA.style "cursor" "pointer"
               ]
            ++ Render.Utility.rlBlockSync block.meta
        )
        [ Html.div [ HA.style "pointer-events" "none" ]
            (Html.div
                [ HA.style "font-size" "2.5em"
                , HA.style "margin-bottom" "0.5em"
                ]
                [ Html.text title ]
                :: authorLine
            )
        ]
    ]


{-| Render an article block.

    | article
    title: On the Nature of Things
    author: Jane Smith

Renders the same as a book block.

-}
renderArticle : CompilerParameters -> Accumulator -> String -> ExpressionBlock -> List (Html Msg) -> List (Html Msg)
renderArticle params acc name block children =
    renderBook params acc name block children



-- NO-OP BLOCKS


{-| Render nothing (for hidden/configuration blocks).

Used for: settings, load-data, hide, texComment, docinfo, load-files, include, setup

-}
renderNothing : CompilerParameters -> Accumulator -> String -> ExpressionBlock -> List (Html Msg) -> List (Html Msg)
renderNothing _ _ _ block _ =
    [ Html.div [ idAttr block.meta.id, HA.style "display" "none" ] [] ]
