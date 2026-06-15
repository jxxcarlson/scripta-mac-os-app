module Scripta.Document exposing
    ( Document
    , hasSections, idsContainingSource, sourceOfId, title
    )

{-| Query functions over a parsed Scripta `Document`.

@docs Document
@docs hasSections, idsContainingSource, sourceOfId, title

-}

import Either exposing (Either(..))
import RoseTree.Tree as Tree exposing (Tree)
import Scripta.Internal as Internal
import V3.Types exposing (Expr(..), ExpressionBlock, Heading(..))


{-| Re-export of the opaque `Document` type.
-}
type alias Document =
    Internal.Document


{-| Flatten a forest into a flat list of blocks (pre-order).
-}
flattenForest : List (Tree ExpressionBlock) -> List ExpressionBlock
flattenForest forest =
    List.concatMap flattenTree forest


flattenTree : Tree ExpressionBlock -> List ExpressionBlock
flattenTree tree =
    Tree.value tree :: List.concatMap flattenTree (Tree.children tree)


{-| Return the ids of all blocks whose source text contains `target`.

Replaces hand-rolled forest walks like `Editor.matchingIdsInAST`. Used for
left-to-right sync: editor selection -> matching rendered element ids.
An empty or whitespace-only target yields `[]`.

-}
idsContainingSource : String -> Document -> List String
idsContainingSource target (Internal.Document data) =
    let
        trimmed =
            String.trim target
    in
    if String.isEmpty trimmed then
        []

    else
        data.forest
            |> flattenForest
            |> List.filter (\block -> String.contains trimmed block.meta.sourceText)
            |> List.map (\block -> block.meta.id)


{-| Return the source text of the block with the given id, if any.
-}
sourceOfId : String -> Document -> Maybe String
sourceOfId id (Internal.Document data) =
    data.forest
        |> flattenForest
        |> List.filter (\block -> block.meta.id == id)
        |> List.head
        |> Maybe.map (\block -> block.meta.sourceText)


{-| Whether the document contains at least one `section` block. Used to decide
whether the rendered output includes a table of contents.
-}
hasSections : Document -> Bool
hasSections (Internal.Document data) =
    data.forest
        |> flattenForest
        |> List.any
            (\block ->
                case block.heading of
                    Ordinary "section" ->
                        True

                    _ ->
                        False
            )


{-| Return the document title (the text of its `title` block), or `""` if
there is no title block.
-}
title : Document -> String
title (Internal.Document data) =
    data.forest
        |> List.filterMap (findBlockByName "title")
        |> List.head
        |> Maybe.map blockText
        |> Maybe.withDefault ""


{-| Find the first block named `name` in a tree.
-}
findBlockByName : String -> Tree ExpressionBlock -> Maybe ExpressionBlock
findBlockByName name tree =
    let
        block =
            Tree.value tree

        here =
            case block.heading of
                Ordinary blockName ->
                    if blockName == name then
                        Just block

                    else
                        Nothing

                _ ->
                    Nothing
    in
    case here of
        Just b ->
            Just b

        Nothing ->
            Tree.children tree
                |> List.filterMap (findBlockByName name)
                |> List.head


{-| Extract the plain text content of a block.
-}
blockText : ExpressionBlock -> String
blockText block =
    case block.body of
        Left str ->
            str

        Right expressions ->
            expressions
                |> List.map exprText
                |> String.concat


exprText : V3.Types.Expression -> String
exprText expr =
    case expr of
        Text str _ ->
            str

        Fun _ args _ ->
            List.map exprText args |> String.concat

        VFun _ content _ ->
            content

        ExprList _ exprs _ ->
            List.map exprText exprs |> String.concat
