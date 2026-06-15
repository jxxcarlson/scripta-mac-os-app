module View exposing (view)

import Html exposing (Html, button, div, li, text, ul)
import Html.Attributes exposing (style)
import Html.Events exposing (onClick)
import Types exposing (Model, Msg(..))
import Workspace exposing (Node(..))


view : Model -> Html Msg
view model =
    div [ style "display" "flex", style "height" "100vh", style "font-family" "system-ui" ]
        [ div [ style "width" "260px", style "border-right" "1px solid #ddd", style "padding" "8px", style "overflow" "auto" ]
            (button [ onClick ClickedOpenVault ] [ text "Open Vault" ]
                :: errorBanner model
                ++ [ treeView model.tree ]
            )
        , div [ style "flex" "1", style "padding" "8px" ]
            [ text (Maybe.withDefault "No file selected" model.selectedPath) ]
        ]


errorBanner : Model -> List (Html Msg)
errorBanner model =
    case model.error of
        Just e ->
            [ div
                [ style "background" "#fee", style "color" "#900", style "padding" "6px", onClick DismissError ]
                [ text ("Error: " ++ e ++ " (click to dismiss)") ]
            ]

        Nothing ->
            []


treeView : List Node -> Html Msg
treeView nodes =
    ul [ style "list-style" "none", style "padding-left" "12px" ]
        (List.map nodeView nodes)


nodeView : Node -> Html Msg
nodeView node =
    case node of
        FileNode r ->
            li [ onClick (ClickedTreeNode r.path), style "cursor" "pointer" ] [ text r.name ]

        FolderNode r ->
            li []
                [ text ("\u{1F4C1} " ++ r.name)
                , treeView r.children
                ]
