module Render.Data exposing (prepareTable)

import Dict
import Either exposing (Either(..))
import List.Extra
import Maybe.Extra
import V3.Types exposing (ExpressionBlock)


type alias TableData =
    { title : Maybe String, columnWidths : List Int, totalWidth : Int, selectedCells : List (List String) }


getVerbatimContent : ExpressionBlock -> String
getVerbatimContent block =
    case block.body of
        Left str ->
            str

        Right _ ->
            ""


prepareTable : Int -> ExpressionBlock -> TableData
prepareTable fontWidth_ block =
    let
        title =
            Dict.get "title" block.properties

        columnsToDisplay : List Int
        columnsToDisplay =
            Dict.get "columns" block.properties
                |> Maybe.map (String.split ",")
                |> Maybe.withDefault []
                |> List.map (String.trim >> String.toInt)
                |> Maybe.Extra.values
                |> List.map (\n -> n - 1)

        lines =
            String.split "\n" (getVerbatimContent block)

        rawCells : List (List String)
        rawCells =
            List.map (String.split ",") lines
                |> List.map (List.map String.trim)

        selectedCells : List (List String)
        selectedCells =
            if columnsToDisplay == [] then
                rawCells

            else
                let
                    cols : List ( Int, List String )
                    cols =
                        List.Extra.transpose rawCells |> List.indexedMap (\k col -> ( k, col ))

                    updater : ( Int, List String ) -> List (List String) -> List (List String)
                    updater =
                        \( k, col ) acc_ ->
                            if List.member k columnsToDisplay then
                                col :: acc_

                            else
                                acc_

                    selectedCols =
                        List.foldl updater [] cols
                in
                List.Extra.transpose (List.reverse selectedCols)

        columnWidths : List Int
        columnWidths =
            List.map (List.map String.length) selectedCells
                |> List.Extra.transpose
                |> List.map (\column -> List.maximum column |> Maybe.withDefault 1)
                |> List.map (\w -> fontWidth_ * w)

        totalWidth =
            List.sum columnWidths
    in
    { title = title, columnWidths = columnWidths, totalWidth = totalWidth, selectedCells = selectedCells }
