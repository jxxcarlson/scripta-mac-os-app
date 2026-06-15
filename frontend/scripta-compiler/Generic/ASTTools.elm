module Generic.ASTTools exposing
    ( exprListToStringList
    , expressionNames
    , filterExpressionsOnName_
    , filterExprs
    , filterForestOnLabelNames
    , frontMatterDict
    , getBlockArgsByName
    , getBlockByName
    , getText
    , getVerbatimBlockValue
    , isBlank
    , rawBlockNames
    , stringValueOfList
    )

import Dict exposing (Dict)
import Either exposing (Either(..))
import Generic.BlockUtilities
import Library.Tree
import List.Extra
import RoseTree.Tree as Tree exposing (Tree)
import V3.Types exposing (Expr(..), Expression, ExpressionBlock, Heading(..))


getText : Expression -> Maybe String
getText expression =
    case expression of
        Text str _ ->
            Just str

        VFun _ str _ ->
            Just (String.replace "`" "" str)

        Fun _ expressions _ ->
            List.filterMap getText expressions
                |> String.join " "
                |> Just

        ExprList _ _ _ ->
            Nothing


filterExpressionsOnName_ : String -> List Expression -> List Expression
filterExpressionsOnName_ name exprs =
    List.filter (matchExprOnName_ name) exprs


matchExprOnName_ : String -> Expression -> Bool
matchExprOnName_ name expr =
    getFunctionName expr == Just name


getFunctionName : Expression -> Maybe String
getFunctionName expression =
    case expression of
        Fun name _ _ ->
            Just name

        VFun _ _ _ ->
            Nothing

        Text _ _ ->
            Nothing

        ExprList _ _ _ ->
            Nothing


getExpressionContent : ExpressionBlock -> List Expression
getExpressionContent block =
    case block.body of
        Left _ ->
            []

        Right exprs ->
            exprs


getVerbatimContent : ExpressionBlock -> Maybe String
getVerbatimContent block =
    case block.body of
        Left str ->
            Just str

        Right _ ->
            Nothing


rawBlockNames : List (Tree ExpressionBlock) -> List String
rawBlockNames forest =
    List.map Library.Tree.flatten forest
        |> List.concat
        |> List.filterMap Generic.BlockUtilities.getExpressionBlockName


expressionNames : List (Tree ExpressionBlock) -> List String
expressionNames forest =
    List.map Library.Tree.flatten forest
        |> List.concat
        |> List.map getExpressionContent
        |> List.concat
        |> List.filterMap getFunctionName
        |> List.Extra.unique
        |> List.sort


filterBlocksOnName : String -> List ExpressionBlock -> List ExpressionBlock
filterBlocksOnName name blocks =
    List.filter (\block -> Generic.BlockUtilities.getExpressionBlockName block == Just name) blocks


getBlockByName : String -> List (Tree ExpressionBlock) -> Maybe ExpressionBlock
getBlockByName name ast =
    ast
        |> List.map Library.Tree.flatten
        |> List.concat
        |> filterBlocksOnName name
        |> List.head


getBlockArgsByName : String -> List (Tree ExpressionBlock) -> List String
getBlockArgsByName key ast =
    case getBlockByName key ast of
        Nothing ->
            []

        Just block ->
            block.args


getVerbatimBlockValue : String -> List (Tree ExpressionBlock) -> String
getVerbatimBlockValue key ast =
    case getBlockByName key ast of
        Nothing ->
            "(" ++ key ++ ")"

        Just block ->
            case getVerbatimContent block of
                Just str ->
                    str

                Nothing ->
                    "(" ++ key ++ ")"


filterForestOnLabelNames : (Maybe String -> Bool) -> List (Tree ExpressionBlock) -> List (Tree ExpressionBlock)
filterForestOnLabelNames predicate forest =
    List.filter (\tree -> predicate (Tree.value tree |> Generic.BlockUtilities.getExpressionBlockName)) forest


frontMatterDict : List (Tree ExpressionBlock) -> Dict String String
frontMatterDict ast =
    keyValueDict (getVerbatimBlockValue "docinfo" ast |> String.split "\n" |> fixFrontMatterList)


keyValueDict : List String -> Dict String String
keyValueDict strings_ =
    List.map (String.split ":") strings_
        |> List.map (List.map String.trim)
        |> List.filterMap pairFromList
        |> Dict.fromList


pairFromList : List String -> Maybe ( String, String )
pairFromList strings =
    case strings of
        [ x, y ] ->
            Just ( x, y )

        _ ->
            Nothing


fixFrontMatterList : List String -> List String
fixFrontMatterList strings =
    fixFrontMatterLoop { count = 1, input = strings, output = [] }
        |> List.reverse
        |> handleEmptyDocInfo


handleEmptyDocInfo : List String -> List String
handleEmptyDocInfo strings =
    if strings == [ "(docinfo)" ] then
        [ "date:" ]

    else
        strings


fixFrontMatterLoop : { count : Int, input : List String, output : List String } -> List String
fixFrontMatterLoop state =
    case List.head state.input of
        Nothing ->
            state.output

        Just line ->
            if line == "" then
                fixFrontMatterLoop { state | input = List.drop 1 state.input }

            else if String.left 7 line == "author:" then
                fixFrontMatterLoop
                    { state
                        | input = List.drop 1 state.input
                        , output = String.replace "author:" ("author" ++ String.fromInt state.count ++ ":") line :: state.output
                        , count = state.count + 1
                    }

            else
                fixFrontMatterLoop { state | input = List.drop 1 state.input, output = line :: state.output }


exprListToStringList : List Expression -> List String
exprListToStringList exprList =
    List.filterMap getText exprList
        |> List.map String.trim
        |> List.filter (\s -> s /= "")


stringValueOfList : List Expression -> String
stringValueOfList textList =
    String.join " " (List.map stringValue textList)


stringValue : Expression -> String
stringValue expr =
    case expr of
        Text str _ ->
            str

        Fun _ textList _ ->
            String.join " " (List.map stringValue textList)

        VFun _ str _ ->
            str

        ExprList _ _ _ ->
            "[ExprList]"


filterExprs : (Expression -> Bool) -> List Expression -> List Expression
filterExprs predicate list =
    List.filter predicate list


isBlank : Expression -> Bool
isBlank expr =
    case expr of
        Text content _ ->
            String.trim content == ""

        _ ->
            False
