module View exposing (view)

import Editor
import Html exposing (Html, button, div, li, text, ul)
import Html.Attributes exposing (style)
import Html.Events exposing (onClick, onInput)
import Json.Decode as D
import Language
import Render
import SaveState
import Types exposing (Model, Msg(..))
import Workspace exposing (Node(..))


view : Model -> Html Msg
view model =
    let
        threePaneRow =
            div [ style "display" "flex", style "flex" "1", style "min-height" "0" ]
                [ div [ style "width" "260px", style "border-right" "1px solid #ddd", style "padding" "8px", style "overflow" "auto" ]
                    (button [ onClick ClickedOpenVault ] [ text "Open Vault" ]
                        :: errorBanner model
                        ++ [ treeView model.tree
                           , div [ style "font-size" "12px", style "color" "#666", style "margin-top" "6px" ]
                                [ text (saveLabel model.saveState.saveStatus) ]
                           , div [ style "margin-top" "8px" ]
                                [ Html.input
                                    [ Html.Attributes.placeholder "new-file-name"
                                    , Html.Attributes.value model.newName
                                    , onInput SetNewName
                                    , style "width" "150px"
                                    ]
                                    []
                                , button [ onClick ClickedNewFile ] [ text "New" ]
                                , button [ onClick ClickedRename ] [ text "Rename" ]
                                ]
                           , div [ style "margin-top" "4px" ]
                                [ button [ onClick ClickedDeleteSelected ] [ text "Delete" ]
                                , button [ onClick ClickedChangeVault ] [ text "Change Vault" ]
                                ]
                           ]
                    )
                , Html.node "codemirror-editor"
                    [ Html.Attributes.attribute "text" model.loadedContent
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
    in
    div [ style "display" "flex", style "flex-direction" "column", style "height" "100vh", style "font-family" "system-ui" ]
        (conflictBanner model ++ [ threePaneRow ])


conflictBanner : Model -> List (Html Msg)
conflictBanner model =
    if model.externalConflict then
        [ div [ style "background" "#ffd", style "padding" "8px", style "border-bottom" "1px solid #cc0" ]
            [ text "This file changed on disk. "
            , button [ onClick ClickedReloadExternal ] [ text "Reload" ]
            , button [ onClick ClickedKeepMine ] [ text "Keep mine" ]
            ]
        ]

    else
        []


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
