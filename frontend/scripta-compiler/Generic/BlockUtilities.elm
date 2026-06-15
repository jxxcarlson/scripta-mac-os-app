module Generic.BlockUtilities exposing (condenseUrls, getExpressionBlockName, updateMeta)

import Either
import V3.Types exposing (BlockMeta, Expr(..), Expression, ExpressionBlock, Heading(..))


getExpressionBlockName : ExpressionBlock -> Maybe String
getExpressionBlockName block =
    case block.heading of
        Paragraph ->
            Nothing

        Ordinary name ->
            Just name

        Verbatim name ->
            Just name


condenseUrls : ExpressionBlock -> ExpressionBlock
condenseUrls block =
    case block.body of
        Either.Left _ ->
            block

        Either.Right exprList ->
            { block | body = Either.Right (List.map condenseUrl exprList) }


condenseUrl : Expression -> Expression
condenseUrl expr =
    case expr of
        Fun "image" ((Text url meta1) :: rest) meta2 ->
            Fun "image" (Text (smashUrl url) meta1 :: rest) meta2

        _ ->
            expr


smashUrl : String -> String
smashUrl url =
    url |> String.replace "https://" "" |> String.replace "http://" ""


updateMeta : (BlockMeta -> BlockMeta) -> { a | meta : BlockMeta } -> { a | meta : BlockMeta }
updateMeta transformMeta block =
    let
        oldMeta =
            block.meta

        newMeta =
            transformMeta oldMeta
    in
    { block | meta = newMeta }
