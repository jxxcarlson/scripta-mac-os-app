module View exposing (view)

import Editor
import Html exposing (Html, button, div, li, text, ul)
import Html.Attributes exposing (style)
import Html.Events exposing (onClick)
import Json.Decode as D
import Language
import Render
import SaveState
import Types exposing (Model, Msg(..))
import Workspace exposing (Node(..))


view : Model -> Html Msg
view model =
    div [ style "display" "flex", style "height" "100vh", style "font-family" "system-ui" ]
        [ div [ style "width" "260px", style "border-right" "1px solid #ddd", style "padding" "8px", style "overflow" "auto" ]
            (button [ onClick ClickedOpenVault ] [ text "Open Vault" ]
                :: errorBanner model
                ++ [ treeView model.tree
                   , div [ style "font-size" "12px", style "color" "#666", style "margin-top" "6px" ]
                        [ text (saveLabel model.saveState.saveStatus) ]
                   ]
            )
        , Html.node "codemirror-editor"
            [ Html.Attributes.attribute "text" model.content
            , Html.Events.on "text-change" (D.map EditorChanged Editor.textChangeDecoder)
            , style "flex" "1"
            , style "border-right" "1px solid #ddd"
            ]
            []
        , div
            [ Html.Attributes.id Editor.renderedTextId
            , style "flex" "1"
            , style "padding" "16px"
            , style "overflow" "auto"
            ]
            (previewBody model)
        ]


saveLabel : SaveState.SaveStatus -> String
saveLabel status =
    case status of
        SaveState.Saved ->
            "Saved"

        SaveState.Unsaved ->
            "Unsaved\u{2026}"

        SaveState.Saving ->
            "Saving\u{2026}"


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


previewBody : Model -> List (Html Msg)
previewBody model =
    case ( model.language, model.parsedDoc ) of
        ( Just Language.Scripta, Just doc ) ->
            let
                out =
                    Render.renderDocument model.isLight model.contentWidth doc
            in
            (out.title :: out.body)
                |> List.map (Html.map (\_ -> NoOpFromRender))

        ( Just lang, _ ) ->
            [ Html.text (Language.label lang ++ " rendering is not yet supported.") ]

        ( Nothing, _ ) ->
            [ Html.text "Open a .scripta file." ]
