module Render.Export.Html exposing
    ( export, exportExpr, rawExport
    , defaultStyles
    )

{-| Static HTML export.

Produces a complete standalone HTML document (with KaTeX CDN includes for
math) from a parsed Scripta forest. The output contains no Scripta-authored
JavaScript and no editor-sync hooks — it is meant for reading, printing,
or hosting as a plain `.html` file.

@docs export, exportExpr, rawExport
@docs defaultStyles

-}

import Array
import Dict exposing (Dict)
import ETeX.MathMacros
import ETeX.Transform
import Either exposing (Either(..))
import Generic.ASTTools as ASTTools
import Generic.BlockUtilities
import Generic.TextMacro
import List.Extra
import MiniLaTeX.Util
import Render.Export.Util
import Render.Settings exposing (RenderSettings)
import Render.Types
import RoseTree.Tree as Tree exposing (Tree(..))
import Tools.Loop exposing (Step(..), loop)
import V3.Types exposing (Accumulator, Expr(..), Expression, ExpressionBlock, Heading(..))



-- TOP-LEVEL ENTRY POINTS


{-| Export a parsed forest to a complete standalone HTML document.

The document includes a `<head>` with KaTeX CDN links and a default
stylesheet, and a `<body>` containing the title, optional TOC, and rendered
body content.

-}
export : Render.Types.PublicationData -> RenderSettings -> Accumulator -> List (Tree ExpressionBlock) -> String
export publicationData settings_ acc ast =
    let
        titleData : Maybe ExpressionBlock
        titleData =
            ASTTools.getBlockByName "title" ast

        title : String
        title =
            case titleData of
                Nothing ->
                    publicationData.title

                Just expr ->
                    case expr.body of
                        Right [ Text str _ ] ->
                            str

                        _ ->
                            publicationData.title

        properties : Dict String String
        properties =
            Maybe.map .properties titleData
                |> Maybe.map (Dict.insert "title" title)
                |> Maybe.withDefault Dict.empty

        settings : RenderSettings
        settings =
            { settings_ | properties = properties }

        body : String
        body =
            rawExport settings acc ast

        headerBlock : String
        headerBlock =
            renderHeader publicationData title properties
    in
    wrapDocument title (headerBlock ++ "\n" ++ body)


{-| Export the body of the forest, without document scaffolding.

Useful when embedding Scripta-rendered content inside another HTML page.

-}
rawExport : RenderSettings -> Accumulator -> List (Tree ExpressionBlock) -> String
rawExport settings acc ast_ =
    let
        ast : List (Tree ExpressionBlock)
        ast =
            ast_
                |> ASTTools.filterForestOnLabelNames (\name -> not (name == Just "runninghead"))
                |> List.map (Tree.mapValues Generic.BlockUtilities.condenseUrls)
                |> encloseLists
    in
    ast
        |> List.map (exportTree acc settings)
        |> List.filter (\s -> s /= "")
        |> String.join "\n\n"



-- DOCUMENT SCAFFOLDING


wrapDocument : String -> String -> String
wrapDocument title body =
    String.join "\n"
        [ "<!DOCTYPE html>"
        , "<html lang=\"en\">"
        , "<head>"
        , "<meta charset=\"UTF-8\">"
        , "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">"
        , "<title>" ++ escape title ++ "</title>"
        , katexHead
        , "<style>"
        , defaultStyles
        , "</style>"
        , "</head>"
        , "<body>"
        , "<article class=\"scripta-doc\">"
        , body
        , "</article>"
        , "</body>"
        , "</html>"
        ]


{-| KaTeX CSS, JS, and auto-render configured for `\(...\)` / `\[...\]` and `$...$` / `$$...$$` delimiters.
-}
katexHead : String
katexHead =
    String.join "\n"
        [ "<link rel=\"stylesheet\" href=\"https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/katex.min.css\" integrity=\"sha384-n8MVd4RsNIU0tAv4ct0nTaAbDJwPJzDEaqSD1odI+WdtXRGWt2kTvGFasHpSy3SV\" crossorigin=\"anonymous\">"
        , "<script defer src=\"https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/katex.min.js\" integrity=\"sha384-XjKyOOlGwcjNTAIQHIpgOno0Hl1YQqzUOEleOLALmuqehneUG+vnGctmUb0ZY0l8\" crossorigin=\"anonymous\"></script>"
        , "<script defer src=\"https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/contrib/auto-render.min.js\" integrity=\"sha384-+VBxd3r6XgURycqtZ117nYw44OOcIax56Z4dCRWbxyPt0Koah1uHoK0o4+/RRE05\" crossorigin=\"anonymous\"></script>"
        , "<script>"
        , "document.addEventListener(\"DOMContentLoaded\", function() {"
        , "  renderMathInElement(document.body, {"
        , "    delimiters: ["
        , "      {left: '$$', right: '$$', display: true},"
        , "      {left: '\\\\[', right: '\\\\]', display: true},"
        , "      {left: '\\\\(', right: '\\\\)', display: false},"
        , "      {left: '$', right: '$', display: false}"
        , "    ],"
        , "    throwOnError: false"
        , "  });"
        , "});"
        , "// ESC clears the URL fragment so :target highlights fall off."
        , "document.addEventListener(\"keydown\", function(e) {"
        , "  if (e.key === \"Escape\" && location.hash) {"
        , "    history.replaceState(null, \"\", location.pathname + location.search);"
        , "  }"
        , "});"
        , "</script>"
        ]


renderHeader : Render.Types.PublicationData -> String -> Dict String String -> String
renderHeader publicationData title properties =
    let
        authors : List String
        authors =
            case Dict.get "author" properties of
                Just str ->
                    String.split "," str |> List.map String.trim

                Nothing ->
                    publicationData.authorList

        authorBlock : String
        authorBlock =
            case authors of
                [] ->
                    ""

                _ ->
                    "<div class=\"scripta-authors\">"
                        ++ String.join ", " (List.map escape authors)
                        ++ "</div>"

        dateBlock : String
        dateBlock =
            case Dict.get "date" properties of
                Just dateStr ->
                    "<div class=\"scripta-date\">" ++ escape dateStr ++ "</div>"

                Nothing ->
                    ""

        subtitleBlock : String
        subtitleBlock =
            case Dict.get "subtitle" properties of
                Just sub ->
                    "<div class=\"scripta-subtitle\">" ++ escape sub ++ "</div>"

                Nothing ->
                    ""
    in
    if title == "" then
        ""

    else
        String.join "\n"
            [ "<header class=\"scripta-title-block\">"
            , "<h1 class=\"scripta-title\">" ++ escape title ++ "</h1>"
            , subtitleBlock
            , authorBlock
            , dateBlock
            , "</header>"
            ]
            |> stripEmptyLines


stripEmptyLines : String -> String
stripEmptyLines str =
    str
        |> String.lines
        |> List.filter (\line -> String.trim line /= "")
        |> String.join "\n"



-- DEFAULT STYLES


{-| Default stylesheet embedded in the document `<head>`. Exposed so callers
can extract it (e.g. to ship as a separate file). Override by appending
custom rules to the output, or by post-processing the HTML.
-}
defaultStyles : String
defaultStyles =
    """
body {
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
  line-height: 1.5;
  color: #222;
  background: #fff;
  margin: 0;
  padding: 0;
}
.scripta-doc {
  max-width: 800px;
  margin: 2em auto;
  padding: 0 1.5em;
}
.scripta-title-block { margin-bottom: 2em; border-bottom: 1px solid #eee; padding-bottom: 1em; }
.scripta-title { font-size: 2em; margin: 0 0 0.2em 0; }
.scripta-subtitle { font-size: 1.2em; color: #555; margin-bottom: 0.4em; }
.scripta-authors { color: #555; margin-bottom: 0.2em; }
.scripta-date { color: #777; font-size: 0.9em; }
.scripta-section-1 { font-size: 1.5em; margin-top: 1.6em; }
.scripta-section-2 { font-size: 1.3em; margin-top: 1.4em; }
.scripta-section-3 { font-size: 1.15em; margin-top: 1.2em; }
.scripta-section-4 { font-size: 1.0em; margin-top: 1.0em; font-style: italic; }
.scripta-paragraph { margin: 0.7em 0; }
.scripta-itemize, .scripta-enumerate, .scripta-description { margin: 0.6em 0 0.6em 1.5em; }
.scripta-itemize li, .scripta-enumerate li { margin: 0.2em 0; }
.scripta-description dt { font-weight: 600; margin-top: 0.3em; }
.scripta-description dd { margin-left: 1.5em; margin-bottom: 0.3em; }
.scripta-code-block {
  background: #f6f8fa;
  border: 1px solid #e1e4e8;
  border-radius: 4px;
  padding: 0.6em 0.8em;
  font-family: "SFMono-Regular", Consolas, "Liberation Mono", monospace;
  font-size: 0.9em;
  overflow-x: auto;
  white-space: pre;
  margin: 0.8em 0;
}
.scripta-inline-code {
  background: #f6f8fa;
  border-radius: 3px;
  padding: 0.1em 0.3em;
  font-family: "SFMono-Regular", Consolas, "Liberation Mono", monospace;
  font-size: 0.92em;
}
.scripta-math-display { margin: 1em 0; text-align: center; }
.scripta-equation { display: flex; align-items: center; margin: 1em 0; }
.scripta-equation-spacer { flex: 1; }
.scripta-equation-math { flex: 0 0 auto; }
.scripta-equation-number { flex: 1; text-align: right; padding-right: 1em; }
/* Highlight whichever equation the URL fragment points at. Press ESC to clear. */
.scripta-equation:target,
.scripta-math-display:target {
  background-color: #fff3a8;
  border-radius: 4px;
  transition: background-color 0.2s ease;
}
.scripta-quote { border-left: 3px solid #ddd; padding-left: 1em; color: #555; margin: 0.8em 0; }
.scripta-theorem, .scripta-lemma, .scripta-corollary, .scripta-proposition, .scripta-definition, .scripta-example, .scripta-remark, .scripta-note {
  margin: 1em 0;
}
.scripta-theorem-label { font-weight: 600; }
.scripta-proof { margin: 0.8em 0; }
.scripta-proof::before { content: "Proof. "; font-style: italic; font-weight: 600; }
.scripta-link { color: #0366d6; text-decoration: none; }
.scripta-link:hover { text-decoration: underline; }
.scripta-image { max-width: 100%; height: auto; display: block; margin: 0.8em auto; }
.scripta-figure { margin: 1em 0; text-align: center; }
.scripta-figure figcaption { font-size: 0.9em; color: #555; margin-top: 0.3em; }
.scripta-error { color: #b00020; background: #fff0f0; padding: 0.3em 0.6em; border-radius: 3px; }
.scripta-todo { color: #b58900; }
.scripta-indent { margin-left: 1.5em; }
.scripta-banner { margin: 0 0 1em 0; }
.scripta-banner img { max-width: 100%; }
.scripta-q { font-weight: 600; }
.scripta-a { }
.scripta-table {
  border-collapse: collapse;
  margin: 1em auto;
}
.scripta-table th, .scripta-table td {
  padding: 4px 12px;
  border-bottom: 1px solid #ddd;
}
.scripta-table th { border-bottom: 2px solid #333; text-align: left; }
.scripta-table-caption, .scripta-table-title { font-size: 0.9em; color: #555; font-style: italic; margin-top: 0.4em; caption-side: bottom; }
.scripta-box {
  border: 1px solid #ccc;
  background: #f5f5f5;
  border-radius: 4px;
  padding: 0.8em 1em;
  margin: 1em 0;
}
.scripta-box-title { font-weight: 600; margin-bottom: 0.4em; }
.scripta-abstract { margin: 1em 2em; font-size: 0.95em; }
.scripta-abstract-label { font-weight: 600; margin-bottom: 0.3em; }
.scripta-iframe { display: block; margin: 1em auto; max-width: 100%; }
.scripta-svg { display: block; margin: 1em auto; text-align: center; }
.scripta-qed { float: right; }
.scripta-block-label, .scripta-theorem-label { font-weight: 600; }
.scripta-center { margin: 0.8em 0; }
.scripta-paragraph-block { margin: 0.7em 0 0.7em 2em; }
"""



-- TREE TRAVERSAL


exportTree : Accumulator -> RenderSettings -> Tree ExpressionBlock -> String
exportTree acc settings tree =
    let
        block : ExpressionBlock
        block =
            Tree.value tree

        children : List (Tree ExpressionBlock)
        children =
            Tree.children tree
    in
    case children of
        [] ->
            exportBlock acc settings block

        _ ->
            case Generic.BlockUtilities.getExpressionBlockName block of
                Just "item" ->
                    handleItemWithChildren acc settings tree children

                Just "numbered" ->
                    handleItemWithChildren acc settings tree children

                Just "desc" ->
                    handleItemWithChildren acc settings tree children

                _ ->
                    let
                        rendered : String
                        rendered =
                            exportBlock acc settings block

                        childOutput : String
                        childOutput =
                            children
                                |> List.map (exportTree acc settings)
                                |> List.filter (\s -> s /= "")
                                |> String.join "\n"
                    in
                    if childOutput == "" then
                        rendered

                    else if rendered == "" then
                        childOutput

                    else
                        rendered ++ "\n" ++ childOutput


handleItemWithChildren : Accumulator -> RenderSettings -> Tree ExpressionBlock -> List (Tree ExpressionBlock) -> String
handleItemWithChildren acc settings tree children =
    let
        itemContent : String
        itemContent =
            exportBlock acc settings (Tree.value tree)

        childOutput : String
        childOutput =
            children
                |> List.map (exportTree acc settings)
                |> List.filter (\s -> s /= "")
                |> String.join "\n"
    in
    -- Splice children inside the <li>/<dd> by inserting them before the closing tag.
    spliceInsideListItem itemContent childOutput


spliceInsideListItem : String -> String -> String
spliceInsideListItem itemHtml childHtml =
    if childHtml == "" then
        itemHtml

    else
        let
            -- Insert child content before the final closing tag (e.g. "</li>" or "</dd>").
            insertBefore : String -> String -> Maybe String
            insertBefore tag s =
                if String.endsWith tag s then
                    Just (String.dropRight (String.length tag) s ++ "\n" ++ childHtml ++ "\n" ++ tag)

                else
                    Nothing
        in
        case insertBefore "</li>" itemHtml of
            Just merged ->
                merged

            Nothing ->
                case insertBefore "</dd>" itemHtml of
                    Just merged ->
                        merged

                    Nothing ->
                        itemHtml ++ "\n" ++ childHtml



-- LIST ENCLOSURE
-- Same machinery as LaTeX export: walk the forest and inject begin/end blocks
-- around consecutive item / numbered / desc / bibitem siblings.


type Status
    = InsideItemizedList
    | InsideNumberedList
    | InsideDescriptionList
    | InsideBibliography
    | OutsideList


type alias State =
    { status : Status
    , input : List (Tree ExpressionBlock)
    , output : List (Tree ExpressionBlock)
    , itemNumber : Int
    }


encloseLists : List (Tree ExpressionBlock) -> List (Tree ExpressionBlock)
encloseLists blocks =
    let
        processedBlocks : List (Tree ExpressionBlock)
        processedBlocks =
            List.map processTreeChildren blocks
    in
    loop
        { status = OutsideList, input = processedBlocks, output = [], itemNumber = 0 }
        nextStep
        |> List.reverse


processTreeChildren : Tree ExpressionBlock -> Tree ExpressionBlock
processTreeChildren (Tree block children) =
    let
        childList : List (Tree ExpressionBlock)
        childList =
            Array.toList children

        processedChildren =
            case childList of
                [] ->
                    Array.empty

                _ ->
                    encloseLists childList |> Array.fromList
    in
    Tree block processedChildren


nextStep : State -> Step State (List (Tree ExpressionBlock))
nextStep state =
    case List.head state.input of
        Nothing ->
            case state.status of
                InsideItemizedList ->
                    Done (Tree.leaf endItemizedBlock :: state.output)

                InsideNumberedList ->
                    Done (Tree.leaf endNumberedBlock :: state.output)

                InsideDescriptionList ->
                    Done (Tree.leaf endDescriptionBlock :: state.output)

                InsideBibliography ->
                    Done (Tree.leaf endBibliographyBlock :: state.output)

                OutsideList ->
                    Done state.output

        Just tree ->
            Loop (nextState tree state)


nextState : Tree ExpressionBlock -> State -> State
nextState tree state =
    let
        name_ : Maybe String
        name_ =
            Tree.value tree |> Generic.BlockUtilities.getExpressionBlockName
    in
    case ( state.status, name_ ) of
        ( OutsideList, Just "item" ) ->
            { state | status = InsideItemizedList, itemNumber = 1, output = tree :: Tree.leaf beginItemizedBlock :: state.output, input = List.drop 1 state.input }

        ( InsideItemizedList, Just "item" ) ->
            { state | output = tree :: state.output, itemNumber = state.itemNumber + 1, input = List.drop 1 state.input }

        ( InsideItemizedList, _ ) ->
            { state | status = OutsideList, itemNumber = 0, output = tree :: Tree.leaf endItemizedBlock :: state.output, input = List.drop 1 state.input }

        ( OutsideList, Just "numbered" ) ->
            { state | status = InsideNumberedList, itemNumber = 1, output = tree :: Tree.leaf beginNumberedBlock :: state.output, input = List.drop 1 state.input }

        ( InsideNumberedList, Just "numbered" ) ->
            { state | output = tree :: state.output, itemNumber = state.itemNumber + 1, input = List.drop 1 state.input }

        ( InsideNumberedList, _ ) ->
            { state | status = OutsideList, itemNumber = 0, output = tree :: Tree.leaf endNumberedBlock :: state.output, input = List.drop 1 state.input }

        ( OutsideList, Just "desc" ) ->
            { state | status = InsideDescriptionList, itemNumber = 1, output = tree :: Tree.leaf beginDescriptionBlock :: state.output, input = List.drop 1 state.input }

        ( InsideDescriptionList, Just "desc" ) ->
            { state | output = tree :: state.output, itemNumber = state.itemNumber + 1, input = List.drop 1 state.input }

        ( InsideDescriptionList, _ ) ->
            { state | status = OutsideList, itemNumber = 0, output = tree :: Tree.leaf endDescriptionBlock :: state.output, input = List.drop 1 state.input }

        ( OutsideList, Just "bibliography" ) ->
            { state | status = InsideBibliography, output = Tree.leaf beginBibliographyBlock :: state.output, input = List.drop 1 state.input }

        ( InsideBibliography, Just "bibitem" ) ->
            { state | output = tree :: state.output, input = List.drop 1 state.input }

        ( InsideBibliography, _ ) ->
            { state | status = OutsideList, output = tree :: Tree.leaf endBibliographyBlock :: state.output, input = List.drop 1 state.input }

        ( OutsideList, _ ) ->
            { state | output = tree :: state.output, input = List.drop 1 state.input }


emptyExpressionBlock : ExpressionBlock
emptyExpressionBlock =
    { heading = Paragraph
    , indent = 0
    , args = []
    , properties = Dict.empty
    , firstLine = ""
    , body = Right []
    , meta =
        { id = ""
        , position = 0
        , lineNumber = 0
        , bodyLineNumber = 0
        , numberOfLines = 0
        , begin = 0
        , end = 0
        , contentBegin = 0
        , contentEnd = 0
        , messages = []
        , sourceText = ""
        , error = Nothing
        }
    , style = {}
    }


beginItemizedBlock : ExpressionBlock
beginItemizedBlock =
    { emptyExpressionBlock | heading = Ordinary "beginBlock" }


endItemizedBlock : ExpressionBlock
endItemizedBlock =
    { emptyExpressionBlock | heading = Ordinary "endBlock" }


beginNumberedBlock : ExpressionBlock
beginNumberedBlock =
    { emptyExpressionBlock | heading = Ordinary "beginNumberedBlock" }


endNumberedBlock : ExpressionBlock
endNumberedBlock =
    { emptyExpressionBlock | heading = Ordinary "endNumberedBlock" }


beginDescriptionBlock : ExpressionBlock
beginDescriptionBlock =
    { emptyExpressionBlock | heading = Ordinary "beginDescriptionBlock" }


endDescriptionBlock : ExpressionBlock
endDescriptionBlock =
    { emptyExpressionBlock | heading = Ordinary "endDescriptionBlock" }


beginBibliographyBlock : ExpressionBlock
beginBibliographyBlock =
    { emptyExpressionBlock | heading = Ordinary "beginBibliographyBlock" }


endBibliographyBlock : ExpressionBlock
endBibliographyBlock =
    { emptyExpressionBlock | heading = Ordinary "endBibliographyBlock" }



-- BLOCK DISPATCH


exportBlock : Accumulator -> RenderSettings -> ExpressionBlock -> String
exportBlock acc settings block =
    case block.heading of
        Paragraph ->
            case block.body of
                Left str ->
                    paragraphTag (escape str)

                Right exprs_ ->
                    let
                        rendered =
                            exportExprList acc settings exprs_
                    in
                    if String.trim rendered == "" then
                        ""

                    else
                        paragraphTag rendered

        Ordinary "table" ->
            exportXTable acc settings block

        Ordinary "banner" ->
            exportBanner block

        Ordinary name ->
            case block.body of
                Left _ ->
                    ""

                Right exprs_ ->
                    let
                        body =
                            exportExprList acc settings exprs_
                    in
                    case Dict.get name blockDict of
                        Just f ->
                            f settings block.args body block.properties

                        Nothing ->
                            -- Fallback for unknown ordinary blocks: render as
                            -- a theorem-like environment with the block name
                            -- as a bold label.
                            namedEnvironment name body

        Verbatim name ->
            case block.body of
                Left str ->
                    exportVerbatimBlock acc settings name str block

                Right _ ->
                    ""


paragraphTag : String -> String
paragraphTag body =
    "<p class=\"scripta-paragraph\">" ++ body ++ "</p>"


{-| Render an unknown ordinary block as a theorem-like environment with the
block name as a bold label.
-}
namedEnvironment : String -> String -> String
namedEnvironment name body =
    "<div class=\"scripta-block scripta-block-"
        ++ escapeAttr name
        ++ "\"><span class=\"scripta-block-label\">"
        ++ escape (capitalize name)
        ++ ".</span> "
        ++ body
        ++ "</div>"



-- VERBATIM BLOCK DISPATCH


exportVerbatimBlock : Accumulator -> RenderSettings -> String -> String -> ExpressionBlock -> String
exportVerbatimBlock acc _ name str block =
    case name of
        "math" ->
            displayMath acc block str

        "equation" ->
            displayMath acc block str

        "aligned" ->
            alignedMath acc block str

        "code" ->
            codeBlock (stripTrailingFence str)

        "verbatim" ->
            codeBlock (stripTrailingFence str)

        "verse" ->
            "<pre class=\"scripta-code-block scripta-verse\">" ++ escape (stripTrailingFence str) ++ "</pre>"

        "tabular" ->
            renderTabularBlock block str

        "csvtable" ->
            renderCsvTable block str

        "chem" ->
            "<div class=\"scripta-math-display\">\\[\\ce{" ++ str ++ "}\\]</div>"

        "mathmacros" ->
            -- Hidden LaTeX \newcommand definitions so KaTeX auto-render picks
            -- them up. KaTeX supports \newcommand inside a math block.
            "<div class=\"scripta-math-display\" style=\"display:none\">\\["
                ++ ETeX.Transform.toLaTeXNewCommands str
                ++ "\\]</div>"

        "texComment" ->
            ""

        "textmacros" ->
            ""

        "image" ->
            renderVerbatimImage block str

        "svg" ->
            -- The body is raw SVG; pass it through unchanged inside a wrapper.
            "<div class=\"scripta-svg\">" ++ str ++ "</div>"

        "iframe" ->
            renderIframeBlock block str

        "quiver" ->
            todoBlock "verbatim:quiver" str

        "tikz" ->
            todoBlock "verbatim:tikz" str

        "load-files" ->
            ""

        "load-data" ->
            ""

        "docinfo" ->
            ""

        "hide" ->
            ""

        "settings" ->
            ""

        "setup" ->
            ""

        "include" ->
            ""

        _ ->
            todoBlock ("verbatim:" ++ name) str


displayMath : Accumulator -> ExpressionBlock -> String -> String
displayMath acc block str =
    let
        cleaned : String
        cleaned =
            str
                |> String.lines
                |> List.filter (\line -> String.left 2 line /= "$$")
                |> String.join "\n"
                |> ETeX.Transform.transformETeX acc.mathMacroDict
                |> MiniLaTeX.Util.transformLabel
    in
    renderNumberedEquation block ("\\[" ++ cleaned ++ "\\]")


alignedMath : Accumulator -> ExpressionBlock -> String -> String
alignedMath acc block str =
    let
        stripTrailingBackslashes : String -> String
        stripTrailingBackslashes line =
            if String.endsWith "\\\\" line then
                String.dropRight 2 line |> String.trimRight

            else
                line

        lines : List String
        lines =
            str
                |> String.lines
                |> List.map String.trim
                |> List.filter (\line -> not (String.isEmpty line))
                |> List.map stripTrailingBackslashes
                |> List.map (ETeX.Transform.transformETeX acc.mathMacroDict)
                |> List.map MiniLaTeX.Util.transformLabel

        joined : String
        joined =
            case List.reverse lines of
                [] ->
                    ""

                lastLine :: restReversed ->
                    (List.reverse restReversed |> List.map (\line -> line ++ "\\\\"))
                        ++ [ lastLine ]
                        |> String.join "\n"
    in
    renderNumberedEquation block ("\\[\\begin{aligned}\n" ++ joined ++ "\n\\end{aligned}\\]")


{-| Wrap a math expression with the block's id (used as cross-reference
anchor) and, if the accumulator assigned one, an equation number on the
right.
-}
renderNumberedEquation : ExpressionBlock -> String -> String
renderNumberedEquation block math =
    let
        idAttr : String
        idAttr =
            if block.meta.id == "" then
                ""

            else
                " id=\"" ++ escapeAttr block.meta.id ++ "\""

        equationNumber : String
        equationNumber =
            Dict.get "equation-number" block.properties |> Maybe.withDefault ""
    in
    if equationNumber == "" then
        "<div class=\"scripta-math-display\"" ++ idAttr ++ ">" ++ math ++ "</div>"

    else
        "<div class=\"scripta-equation\""
            ++ idAttr
            ++ "><div class=\"scripta-equation-spacer\"></div><div class=\"scripta-equation-math\">"
            ++ math
            ++ "</div><div class=\"scripta-equation-number\">("
            ++ escape equationNumber
            ++ ")</div></div>"


codeBlock : String -> String
codeBlock str =
    "<pre class=\"scripta-code-block\"><code>" ++ escape str ++ "</code></pre>"


{-| Strip a trailing line of three or more backticks from a fenced code body.

The block parser ends ``` blocks on a blank line, not on the closing fence,
so when an author writes the canonical form

    ```
    print("hi")
    ```

the body arrives here as `"print(\"hi\")\n```"`. Trim the closing fence so it
does not show up in the rendered output. A `\| code` block whose author never
typed a fence is unaffected.

-}
stripTrailingFence : String -> String
stripTrailingFence str =
    case List.reverse (String.lines str) of
        lastLine :: rest ->
            if String.startsWith "```" (String.trim lastLine) then
                List.reverse rest |> String.join "\n"

            else
                str

        [] ->
            str


todoBlock : String -> String -> String
todoBlock name str =
    "<div class=\"scripta-todo\" data-todo=\""
        ++ escapeAttr name
        ++ "\"><em>[TODO "
        ++ escape name
        ++ "]</em><pre>"
        ++ escape str
        ++ "</pre></div>"


todoInline : String -> String
todoInline name =
    "<span class=\"scripta-todo\" data-todo=\"" ++ escapeAttr name ++ "\">[TODO " ++ escape name ++ "]</span>"



-- ORDINARY BLOCK DICTIONARY
-- Mirrors the LaTeX exporter's blockDict so that gaps in HTML coverage are
-- visible. Each entry is keyed by the Scripta block name and receives the
-- rendered body (HTML string) plus args and properties.


type alias BlockRenderer =
    RenderSettings -> List String -> String -> Dict String String -> String


blockDict : Dict String BlockRenderer
blockDict =
    Dict.fromList
        ([ -- Suppressed metadata blocks: rendered separately in the title block.
           ( "title", emptyBlock )
         , ( "subtitle", emptyBlock )
         , ( "author", emptyBlock )
         , ( "date", emptyBlock )
         , ( "contents", emptyBlock )
         , ( "hide", emptyBlock )
         , ( "comment", emptyBlock )
         , ( "tags", emptyBlock )
         , ( "docinfo", emptyBlock )
         , ( "set-key", emptyBlock )
         , ( "endnotes", emptyBlock )
         , ( "index", emptyBlock )
         , ( "references", emptyBlock )
         , ( "setcounter", emptyBlock )
         , ( "collection", emptyBlock )
         , ( "document", emptyBlock )
         , ( "type", emptyBlock )
         , ( "runninghead_", emptyBlock )
         , ( "shiftandsetcounter", emptyBlock )
         , ( "visibleBanner", emptyBlock )
         , ( "bibliography", emptyBlock )
         , ( "texComment", emptyBlock )
         , ( "book", emptyBlock )
         , ( "mathmacros", \_ _ _ _ -> "" )

         -- Headings
         , ( "chapter", \_ _ body _ -> "<h1 class=\"scripta-chapter\">" ++ body ++ "</h1>" )
         , ( "section", renderSection )
         , ( "section*", \_ _ body _ -> "<h3 class=\"scripta-section scripta-section-unnumbered\">" ++ body ++ "</h3>" )
         , ( "subheading", \_ _ body _ -> "<div class=\"scripta-subheading\">" ++ body ++ "</div>" )
         , ( "smallsubheading", \_ _ body _ -> "<div class=\"scripta-smallsubheading\">" ++ body ++ "</div>" )
         , ( "sh", \_ _ body _ -> "<div class=\"scripta-subheading\">" ++ body ++ "</div>" )

         -- List enclosure (begin/end pairs injected by encloseLists)
         , ( "beginBlock", \_ _ _ _ -> "<ul class=\"scripta-itemize\">" )
         , ( "endBlock", \_ _ _ _ -> "</ul>" )
         , ( "beginNumberedBlock", \_ _ _ _ -> "<ol class=\"scripta-enumerate\">" )
         , ( "endNumberedBlock", \_ _ _ _ -> "</ol>" )
         , ( "beginDescriptionBlock", \_ _ _ _ -> "<dl class=\"scripta-description\">" )
         , ( "endDescriptionBlock", \_ _ _ _ -> "</dl>" )
         , ( "beginBibliographyBlock", \_ _ _ _ -> "<div class=\"scripta-bibliography\"><h2>References</h2><dl>" )
         , ( "endBibliographyBlock", \_ _ _ _ -> "</dl></div>" )

         -- List items
         , ( "item", \_ _ body _ -> "<li>" ++ body ++ "</li>" )
         , ( "itemList", \_ _ body _ -> body )
         , ( "numbered", \_ _ body _ -> "<li>" ++ body ++ "</li>" )
         , ( "desc", \_ args body _ -> descriptionItem args body )
         , ( "descriptionItem", \_ args body _ -> descriptionItem args body )
         , ( "bibitem", \_ args body _ -> bibitem args body )

         -- Layout and pass-through blocks
         , ( "compact", \_ _ body _ -> body )
         , ( "identity", \_ _ body _ -> body )
         , ( "datatable", \_ _ body _ -> body )
         , ( "reveal", \_ _ body _ -> body )
         , ( "more", \_ _ body _ -> body )
         , ( "paragraph", \_ _ body _ -> "<div class=\"scripta-paragraph-block\">" ++ body ++ "</div>" )
         , ( "indent", \_ _ body _ -> "<div class=\"scripta-indent\">" ++ body ++ "</div>" )
         , ( "center", \_ _ body _ -> "<div class=\"scripta-center\" style=\"text-align:center\">" ++ body ++ "</div>" )
         , ( "quotation", renderQuotationBlock )
         , ( "quote", renderQuotationBlock )
         , ( "abstract", renderAbstractBlock )

         -- Colored blocks
         , ( "red", \_ _ body _ -> "<div class=\"scripta-color-red\" style=\"color:#d33\">" ++ body ++ "</div>" )
         , ( "red2", \_ _ body _ -> "<div class=\"scripta-color-red2\" style=\"color:#a22\">" ++ body ++ "</div>" )
         , ( "blue", \_ _ body _ -> "<div class=\"scripta-color-blue\" style=\"color:#3366cc\">" ++ body ++ "</div>" )

         -- Q&A and environments
         , ( "q", \_ _ body _ -> "<div class=\"scripta-q\"><strong>Question.</strong> " ++ body ++ "</div>" )
         , ( "a", \_ _ body _ -> "<div class=\"scripta-a\"><strong>Answer.</strong> " ++ body ++ "</div>" )
         , ( "env", renderEnv )
         , ( "box", renderBoxBlock )

         -- Proof: italic "Proof." label, QED at end
         , ( "proof", \_ _ body _ -> "<div class=\"scripta-proof\">" ++ body ++ " <span class=\"scripta-qed\">\u{220E}</span></div>" )

         -- ordinary "table" is handled before blockDict lookup; include a
         -- placeholder so non-standard table shapes still produce some output.
         , ( "table", \_ _ body _ -> "<div class=\"scripta-table-fallback\">" ++ body ++ "</div>" )
         ]
            ++ List.map (\name -> ( name, renderTheoremLike name )) theoremLikeNames
        )


theoremLikeNames : List String
theoremLikeNames =
    [ "theorem", "lemma", "corollary", "proposition", "definition"
    , "remark", "note", "example", "exercise", "problem", "question"
    , "axiom"
    ]


renderTheoremLike : String -> BlockRenderer
renderTheoremLike name _ _ body properties =
    let
        number : String
        number =
            case Dict.get "label" properties of
                Just l ->
                    if l == "" then
                        ""

                    else
                        " " ++ escape l

                Nothing ->
                    ""

        title : String
        title =
            case Dict.get "title" properties of
                Just t ->
                    if t == "" then
                        ""

                    else
                        " (" ++ escape t ++ ")"

                Nothing ->
                    ""
    in
    "<div class=\"scripta-"
        ++ name
        ++ "\"><span class=\"scripta-theorem-label\">"
        ++ escape (capitalize name)
        ++ number
        ++ title
        ++ ".</span> "
        ++ body
        ++ "</div>"


renderQuotationBlock : BlockRenderer
renderQuotationBlock _ _ body _ =
    "<blockquote class=\"scripta-quote\">" ++ body ++ "</blockquote>"


renderAbstractBlock : BlockRenderer
renderAbstractBlock _ _ body _ =
    "<div class=\"scripta-abstract\"><div class=\"scripta-abstract-label\">Abstract</div>" ++ body ++ "</div>"


renderBoxBlock : BlockRenderer
renderBoxBlock _ args body properties =
    let
        title : String
        title =
            case Dict.get "title" properties of
                Just t ->
                    t

                Nothing ->
                    String.join " " args

        titleHtml : String
        titleHtml =
            if String.trim title == "" then
                ""

            else
                "<div class=\"scripta-box-title\">" ++ escape title ++ "</div>"
    in
    "<div class=\"scripta-box\">" ++ titleHtml ++ "<div class=\"scripta-box-body\">" ++ body ++ "</div></div>"


emptyBlock : BlockRenderer
emptyBlock _ _ _ _ =
    ""


descriptionItem : List String -> String -> String
descriptionItem args body =
    let
        label : String
        label =
            args
                |> List.filter (\a -> not (String.contains "label:" a))
                |> String.join " "
    in
    case args of
        [] ->
            "<dt></dt><dd>" ++ body ++ "</dd>"

        _ ->
            "<dt>" ++ escape label ++ "</dt><dd>" ++ body ++ "</dd>"


bibitem : List String -> String -> String
bibitem args body =
    let
        key : String
        key =
            List.head args |> Maybe.withDefault ""
    in
    "<dt id=\"bib-" ++ escapeAttr key ++ "\">[" ++ escape key ++ "]</dt><dd>" ++ body ++ "</dd>"


renderSection : BlockRenderer
renderSection _ args body _ =
    let
        levelStr : String
        levelStr =
            List.head args |> Maybe.withDefault "1"

        ( tag, klass ) =
            case levelStr of
                "1" ->
                    ( "h2", "scripta-section scripta-section-1" )

                "2" ->
                    ( "h3", "scripta-section scripta-section-2" )

                "3" ->
                    ( "h4", "scripta-section scripta-section-3" )

                "4" ->
                    ( "h5", "scripta-section scripta-section-4" )

                _ ->
                    ( "h6", "scripta-section scripta-section-other" )

        slug : String
        slug =
            body
                |> stripTags
                |> String.words
                |> MiniLaTeX.Util.normalizedWord
    in
    "<" ++ tag ++ " id=\"" ++ escapeAttr slug ++ "\" class=\"" ++ klass ++ "\">" ++ body ++ "</" ++ tag ++ ">"


renderEnv : BlockRenderer
renderEnv _ args body _ =
    let
        envName : String
        envName =
            args |> List.head |> Maybe.withDefault "env"

        klass : String
        klass =
            "scripta-" ++ String.toLower envName
    in
    "<div class=\""
        ++ escapeAttr klass
        ++ "\"><span class=\"scripta-theorem-label\">"
        ++ escape (capitalize envName)
        ++ ".</span> "
        ++ body
        ++ "</div>"


capitalize : String -> String
capitalize str =
    case String.uncons str of
        Just ( c, rest ) ->
            String.fromChar (Char.toUpper c) ++ rest

        Nothing ->
            str


{-| Remove HTML tags from a string (rough — used only for slug generation).
-}
stripTags : String -> String
stripTags str =
    stripTagsHelp str ""


stripTagsHelp : String -> String -> String
stripTagsHelp input acc =
    case String.uncons input of
        Nothing ->
            acc

        Just ( '<', rest ) ->
            case String.indexes ">" rest of
                idx :: _ ->
                    stripTagsHelp (String.dropLeft (idx + 1) rest) acc

                [] ->
                    acc

        Just ( c, rest ) ->
            stripTagsHelp rest (acc ++ String.fromChar c)



-- EXPRESSION DISPATCH


exportExprList : Accumulator -> RenderSettings -> List Expression -> String
exportExprList acc settings exprs =
    List.map (exportExpr acc settings) exprs |> String.join ""


{-| Export a single expression to HTML.
-}
exportExpr : Accumulator -> RenderSettings -> Expression -> String
exportExpr acc settings expr =
    case expr of
        Text str _ ->
            escape str

        Fun name exps_ _ ->
            exportFun acc settings name exps_

        VFun name body _ ->
            exportVFun acc name body

        ExprList _ itemExprs _ ->
            exportExprList acc settings itemExprs


exportFun : Accumulator -> RenderSettings -> String -> List Expression -> String
exportFun acc settings name exps_ =
    if List.member name [ "scheme", "compute", "data", "button", "newPost" ] then
        todoInline ("inline:" ++ name)

    else if name == "tableRow" || name == "row" then
        -- Stripped of context; render children inline.
        exportExprList acc settings exps_

    else if name == "tableItem" || name == "cell" then
        exportExprList acc settings exps_

    else if name == "table" then
        exportInlineTable acc settings exps_

    else if name == "sup" then
        "<sup>" ++ (Render.Export.Util.getOneArg exps_ |> escape) ++ "</sup>"

    else if name == "sub" then
        "<sub>" ++ (Render.Export.Util.getOneArg exps_ |> escape) ++ "</sub>"

    else if name == "bi" then
        let
            arg =
                Render.Export.Util.getArgs exps_ |> String.join " " |> escape
        in
        "<strong><em>" ++ arg ++ "</em></strong>"

    else if name == "ds" || name == "dollar" then
        "$"

    else if name == "lambda" then
        case Generic.TextMacro.extract (Fun name exps_ { begin = 0, end = 0, index = 0, id = "" }) of
            Just lambda ->
                Generic.TextMacro.toString (exportExpr acc settings) lambda

            Nothing ->
                todoInline "lambda"

    else if name == "math" || name == "m" then
        let
            arg : String
            arg =
                case exps_ of
                    [ Text str _ ] ->
                        str

                    _ ->
                        ""
        in
        "\\(" ++ ETeX.Transform.transformETeX acc.mathMacroDict arg ++ "\\)"

    else if name == "chem" then
        let
            arg : String
            arg =
                case exps_ of
                    [ Text str _ ] ->
                        str

                    _ ->
                        ""
        in
        "\\(\\ce{" ++ arg ++ "}\\)"

    else if name == "code" then
        let
            arg : String
            arg =
                case exps_ of
                    [ Text str _ ] ->
                        str

                    _ ->
                        ""
        in
        "<code class=\"scripta-inline-code\">" ++ escape arg ++ "</code>"

    else
        case Dict.get name macroDict of
            Just f ->
                f acc settings exps_

            Nothing ->
                case Dict.get name simpleAliasDict of
                    Just ( open, close ) ->
                        open ++ exportExprList acc settings exps_ ++ close

                    Nothing ->
                        -- Unknown inline function: render its children with a debug class.
                        "<span class=\"scripta-unknown\" data-name=\""
                            ++ escapeAttr name
                            ++ "\">"
                            ++ exportExprList acc settings exps_
                            ++ "</span>"


exportVFun : Accumulator -> String -> String -> String
exportVFun acc name body =
    case name of
        "math" ->
            "\\(" ++ ETeX.Transform.transformETeX acc.mathMacroDict body ++ "\\)"

        "$" ->
            "\\(" ++ ETeX.Transform.transformETeX acc.mathMacroDict body ++ "\\)"

        "m" ->
            "\\(" ++ ETeX.Transform.transformETeX acc.mathMacroDict body ++ "\\)"

        "code" ->
            "<code class=\"scripta-inline-code\">" ++ escape body ++ "</code>"

        "`" ->
            "<code class=\"scripta-inline-code\">" ++ escape body ++ "</code>"

        "chem" ->
            "\\(\\ce{" ++ body ++ "}\\)"

        _ ->
            escape body



-- INLINE FUNCTION DICTIONARY


type alias InlineRenderer =
    Accumulator -> RenderSettings -> List Expression -> String


{-| Inline functions that need argument introspection (links, refs, etc.)
-}
macroDict : Dict String InlineRenderer
macroDict =
    Dict.fromList
        [ ( "link", \_ _ exprs -> link exprs )
        , ( "ilink", \_ _ exprs -> ilink exprs )
        , ( "wikilink", \_ _ exprs -> wikilink exprs )
        , ( "mark", \_ _ exprs -> markwith exprs )
        , ( "par", \_ _ _ -> "<br>" )
        , ( "eqref", \acc _ exprs -> eqref acc exprs )
        , ( "mathref", \acc _ exprs -> eqref acc exprs )
        , ( "ref", \acc _ exprs -> ref acc exprs )
        , ( "index", \_ _ _ -> "" )
        , ( "index_", \_ _ _ -> "" )
        , ( "image", \_ _ exprs -> imageInline exprs )
        , ( "vspace", \_ _ exprs -> vspace exprs )
        , ( "bolditalic", \_ _ exprs -> bolditalic exprs )
        , ( "brackets", \_ _ exprs -> "[" ++ (Render.Export.Util.getArgs exprs |> List.map escape |> String.join " ") ++ "]" )
        , ( "lb", \_ _ _ -> "[" )
        , ( "rb", \_ _ _ -> "]" )
        , ( "bt", \_ _ _ -> "`" )
        , ( "underscore", \_ _ _ -> "_" )
        , ( "qed", \_ _ _ -> "<span class=\"scripta-qed\">\u{00A0}\u{25A1}</span>" )
        , ( "tags", \_ _ _ -> "" )
        , ( "setcounter", \_ _ _ -> "" )
        , ( "abstract", \_ _ exprs -> "<strong>Abstract.</strong> " ++ (Render.Export.Util.getArgs exprs |> List.map escape |> String.join " ") )
        , ( "bibitem", \_ _ exprs -> "[" ++ (Render.Export.Util.getArgs exprs |> List.map escape |> String.join " ") ++ "]" )
        , ( "cite", \_ _ exprs -> cite exprs )
        , ( "box", \_ _ _ -> "\u{25A1}" )
        , ( "cbox", \_ _ _ -> "\u{22A0}" )
        , ( "rbox", \_ _ _ -> "<span style=\"color:#c33\">\u{25A1}</span>" )
        , ( "crbox", \_ _ _ -> "<span style=\"color:#c33\">\u{22A0}</span>" )
        , ( "fbox", \_ _ _ -> "\u{25A0}" )
        , ( "frbox", \_ _ _ -> "<span style=\"color:#c33\">\u{25A0}</span>" )
        , ( "xbox", \_ _ _ -> "\u{22A0}" )
        , ( "errorHighlight", \_ _ exprs -> "<span class=\"scripta-error\">[" ++ (Render.Export.Util.getArgs exprs |> List.map escape |> String.join " ") ++ "]</span>" )
        , ( "contents", \_ _ _ -> "" )
        , ( "term", \_ _ exprs -> "<em>" ++ (Render.Export.Util.getArgs exprs |> List.map escape |> String.join " ") ++ "</em>" )
        ]


{-| Simple paired-tag aliases: name -> (open tag, close tag).
-}
simpleAliasDict : Dict String ( String, String )
simpleAliasDict =
    Dict.fromList
        [ ( "italic", ( "<em>", "</em>" ) )
        , ( "i", ( "<em>", "</em>" ) )
        , ( "bold", ( "<strong>", "</strong>" ) )
        , ( "b", ( "<strong>", "</strong>" ) )
        , ( "strong", ( "<strong>", "</strong>" ) )
        , ( "emph", ( "<em>", "</em>" ) )
        , ( "em", ( "<em>", "</em>" ) )
        , ( "large", ( "<span style=\"font-size:1.2em\">", "</span>" ) )
        , ( "red", ( "<span style=\"color:#d33\">", "</span>" ) )
        , ( "blue", ( "<span style=\"color:#3366cc\">", "</span>" ) )
        , ( "green", ( "<span style=\"color:#3a3\">", "</span>" ) )
        , ( "pink", ( "<span style=\"color:#e6a\">", "</span>" ) )
        , ( "magenta", ( "<span style=\"color:#c3c\">", "</span>" ) )
        , ( "violet", ( "<span style=\"color:#83c\">", "</span>" ) )
        , ( "gray", ( "<span style=\"color:#888\">", "</span>" ) )
        , ( "comment", ( "<span style=\"color:#3366cc\">", "</span>" ) )
        , ( "strike", ( "<s>", "</s>" ) )
        , ( "u", ( "<u>", "</u>" ) )
        , ( "underline", ( "<u>", "</u>" ) )
        , ( "group", ( "", "" ) )
        ]



-- INLINE HELPERS


link : List Expression -> String
link exprs =
    let
        args =
            Render.Export.Util.getTwoArgs exprs
    in
    "<a class=\"scripta-link\" href=\""
        ++ escapeAttr args.second
        ++ "\">"
        ++ escape args.first
        ++ "</a>"


ilink : List Expression -> String
ilink exprs =
    let
        args =
            Render.Export.Util.getTwoArgs exprs
    in
    "<a class=\"scripta-link\" href=\"https://scripta.io/s/"
        ++ escapeAttr args.second
        ++ "\">"
        ++ escape args.first
        ++ "</a>"


wikilink : List Expression -> String
wikilink exprs =
    -- Treat the first text token as both link text and slug.
    case exprs of
        (Text first _) :: _ ->
            "<a class=\"scripta-link\" href=\"https://scripta.io/s/"
                ++ escapeAttr (String.trim first)
                ++ "\">"
                ++ escape first
                ++ "</a>"

        _ ->
            ""


markwith : List Expression -> String
markwith exprs =
    -- Produce a span with an id derived from the mark argument so anchors work.
    let
        arg : String
        arg =
            Render.Export.Util.getOneArg exprs |> String.trim
    in
    "<span id=\"" ++ escapeAttr arg ++ "\"></span>"


eqref : Accumulator -> List Expression -> String
eqref acc exprs =
    let
        arg : String
        arg =
            Render.Export.Util.getOneArg exprs |> String.trim
    in
    case Dict.get arg acc.reference of
        Just { id, numRef } ->
            "<a class=\"scripta-link\" href=\"#"
                ++ escapeAttr id
                ++ "\">("
                ++ escape numRef
                ++ ")</a>"

        Nothing ->
            "<span class=\"scripta-error\">(??" ++ escape arg ++ ")</span>"


ref : Accumulator -> List Expression -> String
ref acc exprs =
    let
        arg : String
        arg =
            Render.Export.Util.getOneArg exprs |> String.trim
    in
    case Dict.get arg acc.reference of
        Just { id, numRef } ->
            "<a class=\"scripta-link\" href=\"#"
                ++ escapeAttr id
                ++ "\">"
                ++ escape numRef
                ++ "</a>"

        Nothing ->
            "<span class=\"scripta-error\">??" ++ escape arg ++ "</span>"


cite : List Expression -> String
cite exprs =
    case exprs of
        [ Text key _ ] ->
            "<a class=\"scripta-link\" href=\"#bib-" ++ escapeAttr (String.trim key) ++ "\">[" ++ escape (String.trim key) ++ "]</a>"

        _ ->
            ""


vspace : List Expression -> String
vspace exprs =
    let
        ptStr : String
        ptStr =
            Render.Export.Util.getOneArg exprs
                |> String.toFloat
                |> Maybe.withDefault 0
                |> (\x -> x * 0.25)
                |> String.fromFloat
    in
    "<div style=\"height:" ++ ptStr ++ "em\"></div>"


bolditalic : List Expression -> String
bolditalic exprs =
    let
        arg : String
        arg =
            Render.Export.Util.getArgs exprs |> List.map escape |> String.join " "
    in
    "<strong><em>" ++ arg ++ "</em></strong>"


imageInline : List Expression -> String
imageInline exprs =
    let
        url : String
        url =
            Render.Export.Util.getOneArg exprs
    in
    "<img class=\"scripta-image\" src=\"" ++ escapeAttr url ++ "\" alt=\"\">"



-- TABLES


{-| Render an inline `[table [tableRow [tableItem ...]]]` or
`[table [row [cell ...]]]` expression to an HTML `<table>`.
-}
exportInlineTable : Accumulator -> RenderSettings -> List Expression -> String
exportInlineTable acc settings rowExprs =
    let
        isRow : Expression -> Bool
        isRow expr =
            case expr of
                Fun "tableRow" _ _ ->
                    True

                Fun "row" _ _ ->
                    True

                _ ->
                    False

        cellsOf : Expression -> List Expression
        cellsOf expr =
            case expr of
                Fun "tableRow" cells _ ->
                    List.filter isCellLike cells

                Fun "row" cells _ ->
                    List.filter isCellLike cells

                _ ->
                    []

        isCellLike : Expression -> Bool
        isCellLike expr =
            case expr of
                Fun "tableItem" _ _ ->
                    True

                Fun "cell" _ _ ->
                    True

                _ ->
                    False

        cellContents : Expression -> List Expression
        cellContents expr =
            case expr of
                Fun "tableItem" exprs _ ->
                    exprs

                Fun "cell" exprs _ ->
                    exprs

                _ ->
                    []

        rows : List (List Expression)
        rows =
            rowExprs
                |> List.filter isRow
                |> List.map cellsOf

        renderCell : Expression -> String
        renderCell cell =
            "<td class=\"scripta-cell\">" ++ exportExprList acc settings (cellContents cell) ++ "</td>"

        renderRow : List Expression -> String
        renderRow cells =
            "<tr>" ++ String.concat (List.map renderCell cells) ++ "</tr>"
    in
    case rows of
        [] ->
            ""

        _ ->
            "<table class=\"scripta-table\">" ++ String.concat (List.map renderRow rows) ++ "</table>"


{-| Render an `Ordinary "table"` block whose body has `ExprList`-shaped rows
and cells (the "xtable" form produced by the parser for `| table` blocks).
-}
exportXTable : Accumulator -> RenderSettings -> ExpressionBlock -> String
exportXTable acc settings block =
    let
        widths : List Int
        widths =
            Dict.get "widths" block.properties
                |> Maybe.withDefault ""
                |> String.split ","
                |> List.map String.trim
                |> List.filterMap String.toInt

        formats : List String
        formats =
            Dict.get "format" block.properties
                |> Maybe.withDefault ""
                |> String.toList
                |> List.map (String.fromChar >> formatToTextAlign)

        captionText : Maybe String
        captionText =
            Dict.get "caption" block.properties

        tableNumber : Maybe String
        tableNumber =
            Dict.get "table" block.properties

        captionLine : Maybe String
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

        renderCell : Int -> Expression -> String
        renderCell index cell =
            let
                widthAttr : String
                widthAttr =
                    case List.Extra.getAt index widths of
                        Just w ->
                            " style=\"width:" ++ String.fromInt w ++ "px"

                        Nothing ->
                            " style=\""

                alignAttr : String
                alignAttr =
                    case List.Extra.getAt index formats of
                        Just a ->
                            "text-align:" ++ a ++ ";"

                        Nothing ->
                            ""

                content : String
                content =
                    case cell of
                        ExprList _ exprs _ ->
                            exportExprList acc settings exprs

                        _ ->
                            exportExpr acc settings cell
            in
            "<td" ++ widthAttr ++ alignAttr ++ "\">" ++ content ++ "</td>"

        renderRow : Expression -> String
        renderRow row =
            case row of
                ExprList _ cells _ ->
                    "<tr>" ++ String.concat (List.indexedMap renderCell cells) ++ "</tr>"

                _ ->
                    ""

        rowsHtml : String
        rowsHtml =
            case block.body of
                Right rows ->
                    String.concat (List.map renderRow rows)

                Left _ ->
                    ""

        captionHtml : String
        captionHtml =
            case captionLine of
                Just txt ->
                    "<figcaption class=\"scripta-table-caption\">" ++ escape txt ++ "</figcaption>"

                Nothing ->
                    ""
    in
    if rowsHtml == "" then
        ""

    else
        "<figure class=\"scripta-figure\"><table class=\"scripta-table\">"
            ++ rowsHtml
            ++ "</table>"
            ++ captionHtml
            ++ "</figure>"


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



-- VERBATIM IMAGE / BANNER / TABULAR / CSV / IFRAME


{-| Render a `| banner` block: emit an `<img>` whose src is the block's first
line.
-}
exportBanner : ExpressionBlock -> String
exportBanner block =
    let
        src : String
        src =
            String.trim block.firstLine
    in
    if src == "" then
        ""

    else
        "<div class=\"scripta-banner\"><img src=\"" ++ escapeAttr src ++ "\" alt=\"\"></div>"


{-| Render a `| image` verbatim block. The body is the URL; properties carry
caption, width, figure number, description, float.
-}
renderVerbatimImage : ExpressionBlock -> String -> String
renderVerbatimImage block str =
    let
        src : String
        src =
            String.trim str

        description : String
        description =
            Dict.get "description" block.properties |> Maybe.withDefault ""

        widthStyle : String
        widthStyle =
            case Dict.get "width" block.properties of
                Just "fill" ->
                    "width:100%"

                Just "to-edges" ->
                    "width:100%"

                Just w ->
                    case String.toInt w of
                        Just _ ->
                            "max-width:" ++ w ++ "px"

                        Nothing ->
                            ""

                Nothing ->
                    ""

        floatStyle : String
        floatStyle =
            case Dict.get "float" block.properties of
                Just "left" ->
                    "float:left;margin:0 1em 0.5em 0"

                Just "right" ->
                    "float:right;margin:0 0 0.5em 1em"

                _ ->
                    ""

        figureStyle : String
        figureStyle =
            if floatStyle == "" then
                ""

            else
                " style=\"" ++ floatStyle ++ "\""

        imgStyle : String
        imgStyle =
            if widthStyle == "" then
                ""

            else
                " style=\"" ++ widthStyle ++ "\""

        captionHtml : String
        captionHtml =
            case ( Dict.get "figure" block.properties, Dict.get "caption" block.properties ) of
                ( Nothing, Nothing ) ->
                    ""

                ( Nothing, Just cap ) ->
                    "<figcaption>" ++ escape cap ++ "</figcaption>"

                ( Just fig, Nothing ) ->
                    "<figcaption>Figure " ++ escape fig ++ "</figcaption>"

                ( Just fig, Just cap ) ->
                    "<figcaption><strong>Figure " ++ escape fig ++ ".</strong> " ++ escape cap ++ "</figcaption>"
    in
    "<figure class=\"scripta-figure\""
        ++ figureStyle
        ++ "><img class=\"scripta-image\" src=\""
        ++ escapeAttr src
        ++ "\" alt=\""
        ++ escapeAttr description
        ++ "\""
        ++ imgStyle
        ++ ">"
        ++ captionHtml
        ++ "</figure>"


{-| Render a `| tabular` verbatim block. Each line is a row; cells are
separated by `&`; lines may end with `\\\\`. Args specify column alignments
(e.g. `l c r`).
-}
renderTabularBlock : ExpressionBlock -> String -> String
renderTabularBlock block str =
    let
        formats : List String
        formats =
            block.args |> List.map (String.toLower >> formatToTextAlign)

        stripBackslashes : String -> String
        stripBackslashes line =
            if String.endsWith "\\\\" line then
                String.dropRight 2 line |> String.trimRight

            else
                line

        rowsRaw : List (List String)
        rowsRaw =
            str
                |> String.lines
                |> List.map (String.trim >> stripBackslashes)
                |> List.filter (\line -> line /= "")
                |> List.map (\line -> String.split "&" line |> List.map String.trim)

        renderCell : Int -> String -> String
        renderCell index cell =
            let
                alignAttr : String
                alignAttr =
                    case List.Extra.getAt index formats of
                        Just a ->
                            " style=\"text-align:" ++ a ++ "\""

                        Nothing ->
                            ""
            in
            "<td" ++ alignAttr ++ ">" ++ escape cell ++ "</td>"

        renderRow : List String -> String
        renderRow cells =
            "<tr>" ++ String.concat (List.indexedMap renderCell cells) ++ "</tr>"
    in
    if rowsRaw == [] then
        ""

    else
        "<table class=\"scripta-table\">" ++ String.concat (List.map renderRow rowsRaw) ++ "</table>"


{-| Render a `| csvtable` verbatim block. First line is the header; remaining
lines are data rows. Cells are comma-separated.
-}
renderCsvTable : ExpressionBlock -> String -> String
renderCsvTable block str =
    let
        parseRow : String -> List String
        parseRow line =
            String.split "," line |> List.map String.trim

        rows : List (List String)
        rows =
            str
                |> String.lines
                |> List.filter (\line -> String.trim line /= "")
                |> List.map parseRow

        ( header, body ) =
            case rows of
                h :: rest ->
                    ( h, rest )

                [] ->
                    ( [], [] )

        title : String
        title =
            case Dict.get "title" block.properties of
                Just t ->
                    "<caption class=\"scripta-table-title\">" ++ escape t ++ "</caption>"

                Nothing ->
                    ""

        renderHeaderRow : List String -> String
        renderHeaderRow cells =
            "<thead><tr>"
                ++ String.concat (List.map (\c -> "<th>" ++ escape c ++ "</th>") cells)
                ++ "</tr></thead>"

        renderRow : List String -> String
        renderRow cells =
            "<tr>" ++ String.concat (List.map (\c -> "<td>" ++ escape c ++ "</td>") cells) ++ "</tr>"
    in
    case header of
        [] ->
            ""

        _ ->
            "<table class=\"scripta-table\">"
                ++ title
                ++ renderHeaderRow header
                ++ "<tbody>"
                ++ String.concat (List.map renderRow body)
                ++ "</tbody></table>"


{-| Render a `| iframe` verbatim block. The body is the embed URL.
-}
renderIframeBlock : ExpressionBlock -> String -> String
renderIframeBlock block str =
    let
        src : String
        src =
            String.trim str

        widthAttr : String
        widthAttr =
            Dict.get "width" block.properties
                |> Maybe.withDefault "560"

        heightAttr : String
        heightAttr =
            Dict.get "height" block.properties
                |> Maybe.withDefault "315"
    in
    if src == "" then
        ""

    else
        "<iframe class=\"scripta-iframe\" src=\""
            ++ escapeAttr src
            ++ "\" width=\""
            ++ escapeAttr widthAttr
            ++ "\" height=\""
            ++ escapeAttr heightAttr
            ++ "\" frameborder=\"0\" allowfullscreen></iframe>"



-- ESCAPING


{-| Escape a string for HTML text content.
-}
escape : String -> String
escape =
    String.replace "&" "&amp;"
        >> String.replace "<" "&lt;"
        >> String.replace ">" "&gt;"


{-| Escape a string for use inside a double-quoted HTML attribute.
-}
escapeAttr : String -> String
escapeAttr =
    String.replace "&" "&amp;"
        >> String.replace "\"" "&quot;"
        >> String.replace "<" "&lt;"
        >> String.replace ">" "&gt;"
