module Export exposing (html, latex, defaultName)

{-| Export the current Scripta document to standalone HTML or LaTeX using the
vendored compiler. v1 exports Scripta documents only.
-}

import Render
import Scripta


html : Bool -> Int -> Scripta.Document -> String
html isLight contentWidth doc =
    Scripta.exportHtml (Render.options isLight contentWidth) doc


latex : Bool -> Int -> Scripta.Document -> String
latex isLight contentWidth doc =
    Scripta.exportLaTeX (Render.options isLight contentWidth) doc


{-| A sensible default export filename derived from the selected path, with the
given extension (e.g. ".html" or ".tex").
-}
defaultName : Maybe String -> String -> String
defaultName selectedPath ext =
    selectedPath
        |> Maybe.withDefault "document"
        |> String.split "/"
        |> List.reverse
        |> List.head
        |> Maybe.withDefault "document"
        |> stripExt
        |> (\base -> base ++ ext)


stripExt : String -> String
stripExt name =
    case String.split "." name of
        [ single ] ->
            single

        parts ->
            parts |> List.reverse |> List.drop 1 |> List.reverse |> String.join "."
