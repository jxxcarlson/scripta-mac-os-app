module MiniLaTeX.Util exposing (normalizedWord, transformLabel)

import Regex


normalizedWord : List String -> String
normalizedWord words =
    words
        |> List.map
            (String.toLower
                >> removeNonAlphaNum
            )
        |> String.join "-"


transformLabel : String -> String
transformLabel str =
    let
        normalize m =
            m |> List.map (Maybe.withDefault "") |> String.join "" |> String.trim
    in
    userReplace "\\[label(.*?)\\]" (\m -> "\\label{" ++ (m.submatches |> normalize) ++ "}") str


removeNonAlphaNum : String -> String
removeNonAlphaNum string =
    userReplace "[^A-Za-z0-9\\-]" (\_ -> "") string


userReplace : String -> (Regex.Match -> String) -> String -> String
userReplace regexString replacer string =
    case Regex.fromString regexString of
        Nothing ->
            string

        Just regex ->
            Regex.replace regex replacer string
