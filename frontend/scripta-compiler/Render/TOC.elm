module Render.TOC exposing (build)

{-| Build table of contents from expression blocks.
-}

import Dict
import Either exposing (Either(..))
import Html exposing (Html)
import Html.Attributes as HA
import Html.Events as HE
import RoseTree.Tree as Tree exposing (Tree)
import V3.Types exposing (Accumulator, CompilerParameters, Expr(..), Expression, ExpressionBlock, Heading(..), Msg(..), Theme(..))


{-| Section data for TOC entry.
-}
type alias TocEntry =
    { id : String
    , level : Int
    , title : String
    , sectionNumber : String
    }


{-| Build table of contents HTML from a forest.
-}
build : CompilerParameters -> Accumulator -> List (Tree ExpressionBlock) -> List (Html Msg)
build params acc forest =
    let
        sections =
            extractSections acc forest
    in
    if List.isEmpty sections then
        []

    else
        [ Html.div
            [ HA.style "margin-bottom" "2em"
            , HA.style "padding" "1em"
            , HA.style "border" "1px solid #ccc"
            , HA.style "border-radius" "4px"
            , HA.style "background-color"
                (case params.theme of
                    Light ->
                        "#f9f9f9"

                    Dark ->
                        "#1a1a1a"
                )
            ]
            (Html.div
                [ HA.style "font-weight" "bold"
                , HA.style "margin-bottom" "0.5em"
                ]
                [ Html.text "Contents" ]
                :: List.map (buildTocItem params) sections
            )
        ]


{-| Extract section entries from forest.
-}
extractSections : Accumulator -> List (Tree ExpressionBlock) -> List TocEntry
extractSections acc forest =
    List.concatMap (extractSectionsFromTree acc) forest


{-| Extract sections from a tree.
-}
extractSectionsFromTree : Accumulator -> Tree ExpressionBlock -> List TocEntry
extractSectionsFromTree acc tree =
    let
        block =
            Tree.value tree

        thisEntry =
            case block.heading of
                Ordinary "section" ->
                    [ blockToTocEntry acc block ]

                Ordinary "index" ->
                    [ { id = block.meta.id
                      , level = 1
                      , title = "Index"
                      , sectionNumber = ""
                      }
                    ]

                _ ->
                    []

        childEntries =
            List.concatMap (extractSectionsFromTree acc) (Tree.children tree)
    in
    thisEntry ++ childEntries


{-| Convert a section block to a TOC entry.
-}
blockToTocEntry : Accumulator -> ExpressionBlock -> TocEntry
blockToTocEntry acc block =
    let
        level =
            Dict.get "level" block.properties |> Maybe.andThen String.toInt |> Maybe.withDefault 1

        numberToLevel =
            Dict.get "number-to-level" acc.keyValueDict
                |> Maybe.andThen String.toInt
                |> Maybe.withDefault 0

        label =
            Dict.get "label" block.properties |> Maybe.withDefault ""

        -- Only include section number if level <= numberToLevel
        sectionNum =
            if level <= numberToLevel then
                label

            else
                ""
    in
    { id = block.meta.id
    , level = level
    , title = extractTitle block
    , sectionNumber = sectionNum
    }


{-| Extract title text from block content.
-}
extractTitle : ExpressionBlock -> String
extractTitle block =
    case block.body of
        Left str ->
            str

        Right expressions ->
            expressions
                |> List.map extractTextFromExpr
                |> String.concat


{-| Extract text from an expression.
-}
extractTextFromExpr : Expression -> String
extractTextFromExpr expr =
    case expr of
        Text str _ ->
            str

        Fun _ args _ ->
            List.map extractTextFromExpr args |> String.concat

        VFun _ content _ ->
            content

        ExprList _ exprs _ ->
            List.map extractTextFromExpr exprs |> String.concat


{-| Build a single TOC item HTML.
-}
buildTocItem : CompilerParameters -> TocEntry -> Html Msg
buildTocItem params entry =
    let
        indent =
            (entry.level - 1) * 20

        prefix =
            if entry.sectionNumber /= "" then
                entry.sectionNumber ++ ". "

            else
                ""
    in
    Html.div
        [ HA.style "margin-left" (String.fromInt indent ++ "px")
        , HA.style "margin-bottom" "0.25em"
        , HA.style "overflow" "hidden"
        , HA.style "white-space" "nowrap"
        , HA.style "text-overflow" "ellipsis"
        , HA.title (prefix ++ entry.title)
        ]
        [ Html.a
            [ HA.href ("#" ++ entry.id)
            , HE.onClick (SelectId entry.id)
            , HA.style "color"
                (case params.theme of
                    Light ->
                        "#0066cc"

                    Dark ->
                        "#66b3ff"
                )
            , HA.style "text-decoration" "none"
            ]
            [ Html.text (prefix ++ entry.title) ]
        ]
