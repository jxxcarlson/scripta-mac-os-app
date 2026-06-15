module V3.Compiler exposing (compile, parse, render)

{-| Parse source text its AST (and Accumulator),
compile source text to HTML Msg

    import Compiler
    import Types exposing (CompilerParameters, Filter(..), Theme(..))

    params =
        { filter = NoFilter
        , windowWidth = 800
        , theme = Light
        , editCount = 0
        }

    parse params (String.lines sourceText)
        --> ( Accumulator, List (Tree ExpressionBlock) )

    compile params (String.lines sourceText)
        --> CompilerOutput Msg

-}

import Dict
import Either exposing (Either(..))
import Html exposing (Html)
import Html.Attributes as HA
import Parser.Forest
import Render.TOC
import Render.Tree
import RoseTree.Tree as Tree exposing (Tree)
import V3.Types
    exposing
        ( Accumulator
        , CompilerOutput
        , CompilerParameters
        , Expr(..)
        , ExpressionBlock
        , Heading(..)
        , Msg
        )


parse : CompilerParameters -> List String -> ( Accumulator, List (Tree ExpressionBlock) )
parse params lines =
    Parser.Forest.parseToForestWithAccumulator params lines


{-| Compile source lines to HTML output.
-}
compile : CompilerParameters -> List String -> CompilerOutput Msg
compile params lines =
    render params (Parser.Forest.parseToForestWithAccumulator params lines)


{-| Render parsed forest and accumulator to HTML output.
-}
render : CompilerParameters -> ( Accumulator, List (Tree ExpressionBlock) ) -> CompilerOutput Msg
render params ( accumulator, forest ) =
    let
        body =
            Render.Tree.renderForest params accumulator forest

        toc =
            if params.showTOC then
                Render.TOC.build params accumulator forest

            else
                []

        title =
            extractTitle forest

        banner =
            extractBanner forest
    in
    { body = body
    , banner = banner
    , toc = toc
    , title = title
    }


{-| Extract title from forest.
-}
extractTitle : List (Tree ExpressionBlock) -> Html Msg
extractTitle forest =
    forest
        |> findBlockByName "title"
        |> Maybe.map blockToTitleHtml
        |> Maybe.withDefault (Html.text "")


{-| Extract banner from forest.
-}
extractBanner : List (Tree ExpressionBlock) -> Maybe (Html Msg)
extractBanner forest =
    forest
        |> findBlockByName "banner"
        |> Maybe.map blockToBannerHtml


{-| Find a block by name in the forest.
-}
findBlockByName : String -> List (Tree ExpressionBlock) -> Maybe ExpressionBlock
findBlockByName name forest =
    forest
        |> List.filterMap (findInTree name)
        |> List.head


{-| Find a block in a tree.
-}
findInTree : String -> Tree ExpressionBlock -> Maybe ExpressionBlock
findInTree name tree =
    let
        block =
            Tree.value tree
    in
    case block.heading of
        Ordinary blockName ->
            if blockName == name then
                Just block

            else
                Tree.children tree
                    |> List.filterMap (findInTree name)
                    |> List.head

        _ ->
            Tree.children tree
                |> List.filterMap (findInTree name)
                |> List.head


{-| Convert a title block to HTML.
-}
blockToTitleHtml : ExpressionBlock -> Html Msg
blockToTitleHtml block =
    Html.span []
        [ Html.text (extractBlockText block) ]


{-| Convert a banner block to HTML.
-}
blockToBannerHtml : ExpressionBlock -> Html Msg
blockToBannerHtml block =
    let
        src =
            block.firstLine
    in
    Html.img
        [ HA.src src
        , HA.style "max-width" "100%"
        ]
        []


{-| Extract text content from a block.
-}
extractBlockText : ExpressionBlock -> String
extractBlockText block =
    case block.body of
        Left str ->
            str

        Right expressions ->
            expressions
                |> List.map extractExprText
                |> String.concat


{-| Extract text from an expression.
-}
extractExprText : V3.Types.Expression -> String
extractExprText expr =
    case expr of
        Text str _ ->
            str

        Fun _ args _ ->
            List.map extractExprText args |> String.concat

        VFun _ content _ ->
            content

        ExprList _ exprs _ ->
            List.map extractExprText exprs |> String.concat
