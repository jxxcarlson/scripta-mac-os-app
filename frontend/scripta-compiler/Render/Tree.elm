module Render.Tree exposing (renderForest)

{-| Render a forest of ExpressionBlocks to HTML.
-}

import Html exposing (Html)
import Html.Attributes as HA
import Html.Keyed
import Html.Lazy
import Render.Block
import RoseTree.Tree as Tree exposing (Tree)
import V3.Types exposing (Accumulator, CompilerParameters, ExpressionBlock, Msg(..))


{-| Render a forest (list of trees) to HTML.
-}
renderForest : CompilerParameters -> Accumulator -> List (Tree ExpressionBlock) -> List (Html Msg)
renderForest params acc forest =
    List.map (renderTreeLazy params acc) forest


renderTreeLazy : CompilerParameters -> Accumulator -> Tree ExpressionBlock -> Html Msg
renderTreeLazy params acc tree =
    Html.Lazy.lazy3 renderTreeWrapped params acc tree


renderTreeWrapped : CompilerParameters -> Accumulator -> Tree ExpressionBlock -> Html Msg
renderTreeWrapped params acc tree =
    let
        block =
            Tree.value tree
    in
    Html.Keyed.node "div"
        [ HA.id ("tree-" ++ block.meta.id) ]
        [ ( block.meta.id
          , Html.div [] (renderTree params acc tree)
          )
        ]


{-| Render a single tree to HTML.

Recursively renders children first, then passes them to the block renderer.
This allows block renderers to wrap or incorporate child content as needed.

-}
renderTree : CompilerParameters -> Accumulator -> Tree ExpressionBlock -> List (Html Msg)
renderTree params acc tree =
    let
        block =
            Tree.value tree

        children =
            Tree.children tree

        renderedChildren =
            if List.isEmpty children then
                []

            else
                [ Html.div
                    [ HA.style "margin-left" "0px" ]
                    (List.concatMap (renderTree params acc) children)
                ]
    in
    Render.Block.renderBody params acc block renderedChildren
