module PathUtil exposing (basename, parentDir)

{-| Small '/'-separated path helpers shared by the file-open logic.
-}


{-| The final path segment (the file name).
-}
basename : String -> String
basename path =
    path |> String.split "/" |> List.reverse |> List.head |> Maybe.withDefault path


{-| Everything before the final segment; "" if there is no '/'.
-}
parentDir : String -> String
parentDir path =
    case path |> String.split "/" |> List.reverse of
        _ :: rest ->
            rest |> List.reverse |> String.join "/"

        [] ->
            ""
