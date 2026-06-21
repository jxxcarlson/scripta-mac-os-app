module PathUtil exposing (ancestorDirs, basename, kbaseRoot, parentDir, siblingPath)

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


{-| Every ancestor folder of a '/'-separated path, outermost first. The final
segment (the file name) is dropped. So `"a/b/c.md"` yields `["a", "a/b"]`,
`"Inbox/foo.md"` yields `["Inbox"]`, and a bare `"foo.md"` yields `[]`.
-}
ancestorDirs : String -> List String
ancestorDirs path =
    let
        folders =
            path |> String.split "/" |> List.reverse |> List.drop 1 |> List.reverse
    in
    folders
        |> List.foldl
            (\seg acc ->
                case acc of
                    prev :: _ ->
                        (prev ++ "/" ++ seg) :: acc

                    [] ->
                        [ seg ]
            )
            []
        |> List.reverse


{-| If `path` contains a directory segment named "kbase", return the path
truncated to and including that segment (the kbase root); otherwise Nothing.
So `…/kbase` and `…/kbase/sub` both yield `Just "…/kbase"`. Matches whole
segments only, so `kbase-backup` does not qualify. An absolute path's leading
"" segment is preserved by the rejoin.
-}
kbaseRoot : String -> Maybe String
kbaseRoot path =
    let
        go acc remaining =
            case remaining of
                [] ->
                    Nothing

                seg :: rest ->
                    if seg == "kbase" then
                        Just (String.join "/" (List.reverse (seg :: acc)))

                    else
                        go (seg :: acc) rest
    in
    go [] (String.split "/" path)


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
