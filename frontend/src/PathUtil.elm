module PathUtil exposing (basename, parentDir, siblingPath)

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


{-| Path of a file named `fileName` placed in the same folder as `reference`
(the open document, if any). No reference, or a reference at the vault root,
yields `fileName` itself; a nested reference yields `<folder>/<fileName>`.
-}
siblingPath : Maybe String -> String -> String
siblingPath reference fileName =
    case reference of
        Nothing ->
            fileName

        Just ref ->
            case parentDir ref of
                "" ->
                    fileName

                dir ->
                    dir ++ "/" ++ fileName
