module Parser.Forest exposing (IncrementalResult, parse, parseIncrementally, parseIncrementallySkipAcc, parseToForestWithAccumulator)

{-| Parse source lines into a forest of ExpressionBlocks.

    import Parser.Forest

    lines
        |> Parser.Forest.parse
        --> Forest ExpressionBlock

    params
        |> Parser.Forest.parseToForestWithAccumulator lines
        --> ( Accumulator, Forest ExpressionBlock )

-}

import Dict
import Either exposing (Either(..))
import Generic.Acc
import Generic.BlockUtilities
import Generic.ForestTransform
import Parser.Pipeline
import Parser.PrimitiveBlock
import RoseTree.Tree as Tree exposing (Tree)
import V3.Types exposing (Accumulator, CompilerParameters, Expr(..), ExprMeta, Expression, ExpressionBlock, ExpressionCache, Filter(..), Heading(..), PrimitiveBlock)


{-| Parse source lines into a forest of expression blocks.

Pipeline:

1.  Parse lines into PrimitiveBlocks
2.  Build forest structure based on indentation
3.  Convert each PrimitiveBlock to ExpressionBlock

-}
parse : List String -> List (Tree ExpressionBlock)
parse lines =
    lines
        |> Parser.PrimitiveBlock.parse
        |> Generic.ForestTransform.forestFromBlocks .indent
        |> mapForest Parser.Pipeline.toExpressionBlock


{-| Parse source lines into a forest with accumulator.

Pipeline:

1.  Parse lines into forest of ExpressionBlocks
2.  Filter forest based on CompilerParameters
3.  Transform with accumulator (numbering, references, etc.)

-}
parseToForestWithAccumulator : CompilerParameters -> List String -> ( Accumulator, List (Tree ExpressionBlock) )
parseToForestWithAccumulator params lines =
    let
        initialData_ =
            Generic.Acc.initialData

        initialData =
            { initialData_ | maxLevel = initialData_.maxLevel }
    in
    lines
        |> parse
        |> filterForest params.filter
        |> Generic.Acc.transformAccumulate initialData


{-| Filter the forest based on filter settings.
-}
filterForest : Filter -> List (Tree ExpressionBlock) -> List (Tree ExpressionBlock)
filterForest filter forest =
    case filter of
        NoFilter ->
            forest

        SuppressDocumentBlocks ->
            forest
                |> filterForestOnName (\name -> name /= Just "document")
                |> filterForestOnName (\name -> name /= Just "title")


{-| Filter forest by block name predicate.
-}
filterForestOnName : (Maybe String -> Bool) -> List (Tree ExpressionBlock) -> List (Tree ExpressionBlock)
filterForestOnName predicate forest =
    List.filter (\tree -> predicate (Generic.BlockUtilities.getExpressionBlockName (Tree.value tree))) forest


{-| Parse source lines incrementally, reusing cached expression parse results.
-}
parseIncrementally :
    CompilerParameters
    -> ExpressionCache
    -> List String
    -> ( ExpressionCache, Accumulator, List (Tree ExpressionBlock) )
parseIncrementally params cache lines =
    let
        initialData_ =
            Generic.Acc.initialData

        initialData =
            { initialData_ | maxLevel = initialData_.maxLevel }

        exprForest =
            lines
                |> Parser.PrimitiveBlock.parse
                |> Generic.ForestTransform.forestFromBlocks .indent
                |> mapForest (Parser.Pipeline.toExpressionBlockCached cache)

        ( acc, finalForest ) =
            exprForest
                |> filterForest params.filter
                |> Generic.Acc.transformAccumulate initialData

        newCache =
            buildExpressionCache finalForest
    in
    ( newCache, acc, finalForest )


{-| Result of an incremental parse with accumulator skip optimization.
-}
type alias IncrementalResult =
    { cache : ExpressionCache
    , acc : Accumulator
    , forest : List (Tree ExpressionBlock)
    , accWasSkipped : Bool
    }


{-| Parse incrementally, skipping the accumulator pass when safe.

If the forest structure hasn't changed and the only modified blocks are
accumulator-independent (plain text paragraphs, code blocks, etc.),
reuse the previous Accumulator and splice the new block content into
the previous forest. Otherwise fall back to the full accumulator pass.

-}
parseIncrementallySkipAcc :
    CompilerParameters
    -> ExpressionCache
    -> ( Accumulator, List (Tree ExpressionBlock) )
    -> List String
    -> IncrementalResult
parseIncrementallySkipAcc params cache ( prevAcc, prevForest ) lines =
    let
        newExprForest =
            lines
                |> Parser.PrimitiveBlock.parse
                |> Generic.ForestTransform.forestFromBlocks .indent
                |> mapForest (Parser.Pipeline.toExpressionBlockCached cache)
                |> filterForest params.filter
    in
    if forestStructureMatches prevForest newExprForest && allChangedBlocksAreAccIndependent prevForest newExprForest then
        let
            splicedForest =
                spliceForest prevForest newExprForest

            newCache =
                buildExpressionCache splicedForest
        in
        { cache = newCache, acc = prevAcc, forest = splicedForest, accWasSkipped = True }

    else
        let
            initialData_ =
                Generic.Acc.initialData

            initialData =
                { initialData_ | maxLevel = initialData_.maxLevel }

            ( acc, finalForest ) =
                newExprForest
                    |> Generic.Acc.transformAccumulate initialData

            newCache =
                buildExpressionCache finalForest
        in
        { cache = newCache, acc = acc, forest = finalForest, accWasSkipped = False }


{-| Check if two forests have the same structure (same headings and indents at each position).
-}
forestStructureMatches : List (Tree ExpressionBlock) -> List (Tree ExpressionBlock) -> Bool
forestStructureMatches oldForest newForest =
    List.length oldForest
        == List.length newForest
        && List.all identity (List.map2 treeStructureMatches oldForest newForest)


treeStructureMatches : Tree ExpressionBlock -> Tree ExpressionBlock -> Bool
treeStructureMatches oldTree newTree =
    let
        oldBlock =
            Tree.value oldTree

        newBlock =
            Tree.value newTree
    in
    oldBlock.heading
        == newBlock.heading
        && oldBlock.indent
        == newBlock.indent
        && List.length (Tree.children oldTree)
        == List.length (Tree.children newTree)
        && List.all identity (List.map2 treeStructureMatches (Tree.children oldTree) (Tree.children newTree))


{-| Check that all changed blocks between old and new forests are accumulator-independent.
-}
allChangedBlocksAreAccIndependent : List (Tree ExpressionBlock) -> List (Tree ExpressionBlock) -> Bool
allChangedBlocksAreAccIndependent oldForest newForest =
    List.all identity (List.map2 treeChangesAreAccIndependent oldForest newForest)


treeChangesAreAccIndependent : Tree ExpressionBlock -> Tree ExpressionBlock -> Bool
treeChangesAreAccIndependent oldTree newTree =
    let
        oldBlock =
            Tree.value oldTree

        newBlock =
            Tree.value newTree

        thisBlockOk =
            if oldBlock.meta.sourceText == newBlock.meta.sourceText then
                True

            else
                isAccumulatorIndependent newBlock
    in
    thisBlockOk
        && List.all identity (List.map2 treeChangesAreAccIndependent (Tree.children oldTree) (Tree.children newTree))


{-| A block is accumulator-independent if it neither updates nor consumes
accumulator state. Currently: paragraphs without footnote/term/cite/ref/etc.,
and code blocks.
-}
isAccumulatorIndependent : ExpressionBlock -> Bool
isAccumulatorIndependent block =
    case block.heading of
        Paragraph ->
            case block.body of
                Left _ ->
                    True

                Right exprs ->
                    not (List.any exprUsesAccumulator exprs)

        Verbatim "code" ->
            True

        _ ->
            False


{-| Function names that interact with the accumulator during rendering or updating.
-}
accDependentNames : List String
accDependentNames =
    [ "footnote", "term", "index", "cite", "ref", "eqref", "label" ]


{-| Check if an expression tree references any accumulator-dependent functions.
-}
exprUsesAccumulator : Expression -> Bool
exprUsesAccumulator expr =
    case expr of
        Fun name children _ ->
            List.member name accDependentNames
                || List.any exprUsesAccumulator children

        Text _ _ ->
            False

        VFun _ _ _ ->
            False

        ExprList _ children _ ->
            List.any exprUsesAccumulator children


{-| Splice changed blocks from the new forest into the old forest.
Unchanged blocks keep their accumulator-derived properties from the old forest.
Changed blocks use the freshly parsed version (safe because they are acc-independent).
-}
spliceForest : List (Tree ExpressionBlock) -> List (Tree ExpressionBlock) -> List (Tree ExpressionBlock)
spliceForest oldForest newForest =
    List.map2 spliceTree oldForest newForest


spliceTree : Tree ExpressionBlock -> Tree ExpressionBlock -> Tree ExpressionBlock
spliceTree oldTree newTree =
    let
        oldBlock =
            Tree.value oldTree

        newBlock =
            Tree.value newTree

        resultBlock =
            if oldBlock.meta.sourceText == newBlock.meta.sourceText then
                oldBlock

            else
                newBlock

        resultChildren =
            List.map2 spliceTree (Tree.children oldTree) (Tree.children newTree)
    in
    Tree.branch resultBlock resultChildren


{-| Build an expression cache from a forest of ExpressionBlocks.
-}
buildExpressionCache : List (Tree ExpressionBlock) -> ExpressionCache
buildExpressionCache forest =
    forest
        |> List.concatMap flattenTree
        |> List.map (\block -> ( block.meta.sourceText, block.body ))
        |> Dict.fromList


{-| Flatten a tree into a list of all blocks.
-}
flattenTree : Tree ExpressionBlock -> List ExpressionBlock
flattenTree tree =
    Tree.value tree
        :: List.concatMap flattenTree (Tree.children tree)


{-| Map a function over all values in a forest.
-}
mapForest : (a -> b) -> List (Tree a) -> List (Tree b)
mapForest f forest =
    List.map (Tree.mapValues f) forest
