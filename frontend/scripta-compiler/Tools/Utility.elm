module Tools.Utility exposing (compressWhitespace, keyValueDict)

import Dict exposing (Dict)


compressWhitespace : String -> String
compressWhitespace str =
    str
        |> String.words
        |> String.join " "


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
