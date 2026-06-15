module Render.Pretty exposing (print)

{-| Pretty-print Scripta source code by parsing it into a forest of
ExpressionBlocks and reconstructing formatted output with proper indentation.
-}

import Dict
import Either exposing (Either(..))
import Parser.Forest
import RoseTree.Tree as Tree exposing (Tree)
import V3.Types exposing (Expr(..), Expression, ExpressionBlock, Heading(..))


{-| Pretty-print Scripta source text.
-}
print : String -> String
print str =
    (str ++ "\n\n")
        |> String.lines
        |> Parser.Forest.parse
        |> List.map (treeMap printBlock)
        |> List.map treeToString
        |> String.join "\n\n"
        |> (\s -> s ++ "\n")


{-| Convert a block back to its source text representation.
-}
printBlock : ExpressionBlock -> String
printBlock block =
    case block.heading of
        Paragraph ->
            case block.body of
                Left str ->
                    str

                Right exprList ->
                    List.map renderExpression exprList |> String.join " " |> compressSpaces

        Ordinary name ->
            printOrdinaryBlock name block

        Verbatim name ->
            printVerbatimBlock name block


printOrdinaryBlock : String -> ExpressionBlock -> String
printOrdinaryBlock name block =
    let
        content =
            case block.body of
                Left str ->
                    str

                Right exprList ->
                    List.map renderExpression exprList |> String.join " " |> compressSpaces
    in
    case name of
        "numbered" ->
            ". " ++ String.trim content

        "item" ->
            "- " ++ String.trim content

        "section" ->
            let
                level =
                    Dict.get "level" block.properties
                        |> Maybe.andThen String.toInt
                        |> Maybe.withDefault 1

                prefix =
                    String.repeat level "#"
            in
            prefix ++ " " ++ String.trim content

        "itemList" ->
            case block.body of
                Left str ->
                    str

                Right exprList ->
                    List.map
                        (\expr ->
                            let
                                n =
                                    indentation expr
                            in
                            String.repeat n " " ++ "- " ++ renderExpression expr
                        )
                        exprList
                        |> String.join "\n"

        "numberedList" ->
            case block.body of
                Left str ->
                    str

                Right exprList ->
                    List.map
                        (\expr ->
                            let
                                n =
                                    indentation expr
                            in
                            String.repeat n " " ++ ". " ++ renderExpression expr
                        )
                        exprList
                        |> String.join "\n"

        _ ->
            ([ "|", name ] ++ block.args ++ dictToList block.properties |> String.join " ") ++ "\n" ++ content


indentation : Expression -> Int
indentation expr =
    case expr of
        ExprList n _ _ ->
            n

        _ ->
            0


renderExpression : Expression -> String
renderExpression expr =
    case expr of
        Text str _ ->
            str

        Fun fName exprList _ ->
            "[" ++ fName ++ " " ++ (List.map renderExpression exprList |> String.join "") ++ "]"

        VFun fName body _ ->
            case fName of
                "math" ->
                    "[m " ++ body ++ "]"

                _ ->
                    [ "[" ++ fName, body, "]" ] |> String.join " " |> compressSpaces

        ExprList _ exprList _ ->
            List.map renderExpression exprList |> String.join " " |> compressSpaces


printVerbatimBlock : String -> ExpressionBlock -> String
printVerbatimBlock name block =
    let
        content =
            case block.body of
                Left str ->
                    str

                Right _ ->
                    ""

        blockArgs =
            case Dict.get "label" block.properties of
                Nothing ->
                    block.args

                Just _ ->
                    List.filter (\arg -> arg /= "numbered") block.args
    in
    ([ "|", name ] ++ blockArgs ++ dictToList block.properties |> String.join " ") ++ "\n" ++ content


compressSpaces : String -> String
compressSpaces str =
    str |> String.words |> String.join " "


dictToList : Dict.Dict String String -> List String
dictToList dict =
    dict
        |> Dict.remove "id"
        |> Dict.remove "outerId"
        |> Dict.toList
        |> List.map (\( key, value ) -> key ++ ":" ++ value)


treeMap : (a -> b) -> Tree a -> Tree b
treeMap f tree =
    Tree.branch (f (Tree.value tree))
        (List.map (treeMap f) (Tree.children tree))


treeToString : Tree String -> String
treeToString tree =
    treeToStringHelper 0 tree


treeToStringHelper : Int -> Tree String -> String
treeToStringHelper level tree =
    let
        indent =
            String.repeat level "  "

        currentLine =
            indent ++ Tree.value tree

        treeChildren =
            Tree.children tree

        childLines =
            List.map (treeToStringHelper (level + 1)) treeChildren
                |> String.join "\n"
    in
    if List.isEmpty treeChildren then
        currentLine

    else
        currentLine ++ "\n" ++ childLines
