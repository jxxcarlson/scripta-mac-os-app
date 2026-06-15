module Language exposing (Language(..), fromPath, isSupported, label)

{-| The markup language of a document, derived from its file extension.
Only Scripta is wired for rendering in v1; the others are reserved for
later milestones (the compiler needs a dispatch layer added upstream).
-}


type Language
    = Scripta
    | MiniLaTeX
    | Markdown


{-| Determine the language from a file path by its extension (case-insensitive).
-}
fromPath : String -> Maybe Language
fromPath path =
    case path |> String.split "." |> lastSegment |> Maybe.map String.toLower of
        Just "scripta" ->
            Just Scripta

        Just "tex" ->
            Just MiniLaTeX

        Just "md" ->
            Just Markdown

        _ ->
            Nothing


lastSegment : List String -> Maybe String
lastSegment xs =
    List.head (List.reverse xs)


{-| Whether v1 can render this language. Only Scripta for now.
-}
isSupported : Language -> Bool
isSupported lang =
    lang == Scripta


label : Language -> String
label lang =
    case lang of
        Scripta ->
            "Scripta"

        MiniLaTeX ->
            "MiniLaTeX"

        Markdown ->
            "Markdown"
