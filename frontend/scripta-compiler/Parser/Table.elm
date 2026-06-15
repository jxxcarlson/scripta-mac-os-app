module Parser.Table exposing (parseTable)

import Parser.Expression
import V3.Types


parseTable : Int -> List String -> List V3.Types.Expression
parseTable gen rows =
    List.indexedMap (\row -> parseRow gen row) rows


parseRow : Int -> Int -> String -> V3.Types.Expression
parseRow gen row str =
    List.indexedMap (\col -> parseCell gen row col) (String.split "&" str)
        |> (\exprs -> V3.Types.ExprList 0 exprs { begin = 0, end = String.length str, index = 0, id = "row-" ++ String.fromInt row })


parseCell : Int -> Int -> Int -> String -> V3.Types.Expression
parseCell gen row col str =
    str
        |> String.trim
        |> Parser.Expression.parse gen
        |> (\exprs -> V3.Types.ExprList 0 exprs { begin = 0, end = String.length str, index = 0, id = "cell-" ++ String.fromInt row ++ "-" ++ String.fromInt col })
