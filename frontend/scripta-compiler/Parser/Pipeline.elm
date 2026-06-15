module Parser.Pipeline exposing (toExpressionBlock, toExpressionBlockCached, toExpressionBlockWithBody)

{-| Convert PrimitiveBlock to ExpressionBlock by parsing inline expressions.

    import Parser.Pipeline exposing (toExpressionBlock)

    primitiveBlock
        |> toExpressionBlock
        --> ExpressionBlock with parsed expressions in body

-}

import Dict
import Either exposing (Either(..))
import Parser.Expression as Expression
import Parser.Table
import V3.Types exposing (BlockMeta, Expr(..), ExprMeta, Expression, ExpressionBlock, ExpressionCache, Heading(..), PrimitiveBlock)


{-| Convert a PrimitiveBlock to an ExpressionBlock.

For Verbatim blocks, the body is preserved as raw text (Left String).
For all other blocks, the body is parsed into expressions (Right (List Expression)).

-}
toExpressionBlock : PrimitiveBlock -> ExpressionBlock


toExpressionBlock block =
    toExpressionBlockWithBody (parseBody block) block


{-| Build an ExpressionBlock with a pre-computed body.
-}
toExpressionBlockWithBody : Either String (List Expression) -> PrimitiveBlock -> ExpressionBlock
toExpressionBlockWithBody body block =
    { heading = transformBlockHeading block
    , indent = block.indent
    , args = block.args
    , properties = block.properties |> Dict.insert "id" block.meta.id
    , firstLine = block.firstLine
    , body = body
    , meta = block.meta
    , style = block.style
    }


{-| Convert a PrimitiveBlock to an ExpressionBlock, using the cache for expression parsing.
-}
toExpressionBlockCached : ExpressionCache -> PrimitiveBlock -> ExpressionBlock
toExpressionBlockCached cache block =
    case Dict.get block.meta.sourceText cache of
        Just cachedBody ->
            toExpressionBlockWithBody cachedBody block

        Nothing ->
            toExpressionBlock block


transformBlockHeading block =
    case block.heading of
        Verbatim "table" ->
            Ordinary "table"

        _ ->
            block.heading


{-| Parse the body based on block heading type.
-}
parseBody : PrimitiveBlock -> Either String (List Expression)
parseBody block =
    case block.heading of
        Paragraph ->
            Right (parseLines block.meta.lineNumber block.body)

        Ordinary "item" ->
            -- Single item: parse firstLine + body as one paragraph
            let
                content =
                    (stripListPrefix block.firstLine :: block.body)
                        |> String.join " "
            in
            Right [ ExprList block.indent (Expression.parse block.meta.lineNumber content) emptyExprMeta ]

        Ordinary "numbered" ->
            -- Single numbered item: parse firstLine + body as one paragraph
            let
                content =
                    (stripListPrefix block.firstLine :: block.body)
                        |> String.join " "
            in
            Right [ ExprList block.indent (Expression.parse block.meta.lineNumber content) emptyExprMeta ]

        Ordinary "itemList" ->
            -- Multiple items: parse firstLine + each body line as separate ExprList
            Right (parseListItems block.indent block.meta.lineNumber (block.firstLine :: block.body))

        Ordinary "numberedList" ->
            -- Multiple numbered items: parse firstLine + each body line as separate ExprList
            Right (parseListItems block.indent block.meta.lineNumber (block.firstLine :: block.body))

        Ordinary _ ->
            Right (parseLines block.meta.lineNumber block.body)

        Verbatim "table" ->
            Right (Parser.Table.parseTable 0 block.body)

        Verbatim _ ->
            Left (String.join "\n" block.body)


{-| Parse list items, each becoming an ExprList with its own indent level.
Lines that don't start with "- " or ". " are appended to the previous item.
-}
parseListItems : Int -> Int -> List String -> List Expression
parseListItems _ lineNumber items =
    items
        |> groupListItems
        |> List.map
            (\item ->
                let
                    itemIndent =
                        measureIndent item
                in
                ExprList itemIndent (Expression.parse lineNumber (stripListPrefix item)) emptyExprMeta
            )


{-| Measure the indentation of a line (number of leading spaces).
-}
measureIndent : String -> Int
measureIndent str =
    String.length str - String.length (String.trimLeft str)


{-| Group list items: lines without "- " or ". " prefix are appended to previous item.
-}
groupListItems : List String -> List String
groupListItems items =
    List.foldl
        (\line acc ->
            let
                trimmed =
                    String.trim line
            in
            if String.startsWith "- " trimmed || String.startsWith ". " trimmed then
                -- New list item
                line :: acc

            else
                -- Continuation: append to previous item
                case acc of
                    prev :: rest ->
                        (prev ++ " " ++ trimmed) :: rest

                    [] ->
                        [ line ]
        )
        []
        items
        |> List.reverse


{-| Strip list prefix ("- " or ". ") from a string.
-}
stripListPrefix : String -> String
stripListPrefix str =
    let
        trimmed =
            String.trim str
    in
    if String.startsWith "- " trimmed then
        String.dropLeft 2 trimmed

    else if String.startsWith ". " trimmed then
        String.dropLeft 2 trimmed

    else
        trimmed


{-| Parse multiple lines into a list of expressions.
-}
parseLines : Int -> List String -> List Expression
parseLines lineNumber lines =
    String.join "\n" lines |> Expression.parse lineNumber


{-| Empty expression metadata for synthetic expressions.
-}
emptyExprMeta : ExprMeta
emptyExprMeta =
    { begin = 0, end = 0, index = 0, id = "list" }
