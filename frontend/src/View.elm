module View exposing (view)

import Editor
import Html exposing (Html, button, div, li, text, ul)
import Html.Attributes exposing (style)
import Html.Events exposing (onClick, onInput)
import Json.Decode as D
import Language
import Render
import SaveState
import Set exposing (Set)
import Svg
import Svg.Attributes as SA
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
                        ++ [ treeView model.openFolders model.tree
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
                           , div [ style "margin-top" "4px" ]
                                [ button [ onClick ClickedExportHtml ] [ text "Export HTML" ]
                                , button [ onClick ClickedExportLatex ] [ text "Export LaTeX" ]
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


{-| A small folder glyph: filled black when closed, outline-only when open.
-}
folderIcon : Bool -> Html msg
folderIcon isOpen =
    Svg.svg
        [ SA.width "13"
        , SA.height "13"
        , SA.viewBox "0 0 16 16"
        , SA.style "vertical-align: middle; margin-right: 5px;"
        ]
        [ Svg.path
            [ SA.d "M1.5 4 H6 L7.5 5.5 H14.5 V13 H1.5 Z"
            , SA.stroke "#000"
            , SA.strokeWidth "1"
            , SA.fill
                (if isOpen then
                    "none"

                 else
                    "#000"
                )
            ]
            []
        ]


treeView : Set String -> List Node -> Html Msg
treeView openFolders nodes =
    ul
        [ style "list-style" "none"
        , style "padding-left" "12px"
        , style "font-size" "13px"
        ]
        (List.map (nodeView openFolders) nodes)


nodeView : Set String -> Node -> Html Msg
nodeView openFolders node =
    case node of
        FileNode r ->
            li
                [ onClick (ClickedTreeNode r.path)
                , style "cursor" "pointer"
                , style "margin-bottom" "4px"
                , style "padding-left" "2em"
                , style "text-indent" "-2em"
                ]
                [ text r.name ]

        FolderNode r ->
            let
                isOpen =
                    Set.member r.path openFolders
            in
            li []
                (div
                    [ onClick (ToggledFolder r.path)
                    , style "cursor" "pointer"
                    , style "margin-bottom" "4px"
                    , style "padding-left" "2em"
                    , style "text-indent" "-2em"
                    ]
                    [ folderIcon isOpen, text r.name ]
                    :: (if isOpen then
                            [ treeView openFolders r.children ]

                        else
                            []
                       )
                )


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
