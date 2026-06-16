module Types exposing (Model, Msg(..), PendingOp(..), Pane(..))

import Dict exposing (Dict)
import Json.Decode as D
import Language
import Render
import SaveState
import Scripta
import Set exposing (Set)
import Workspace exposing (Node)


type alias Model =
    { vaultRoot : Maybe String
    , tree : List Node
    , selectedPath : Maybe String
    , nextRequestId : Int
    , pending : Dict Int PendingOp
    , error : Maybe String
    , content : String
    , loadedContent : String
    , loadedMtime : Int
    , externalConflict : Bool
    , parsedDoc : Maybe Scripta.Document
    , language : Maybe Language.Language
    , isLight : Bool
    , contentWidth : Int
    , saveState : SaveState.SaveState
    , newName : String
    , openFolders : Set String
    , searchQuery : String
    , readerMode : Bool
    , initialLastVault : Maybe String
    }


{-| What a given requestId is waiting for, so the response can be interpreted.
-}
type PendingOp
    = PPickWorkspace
    | PListWorkspace
    | PReadFile String
    | PWriteFile String
    | PCreateFile String
    | PCreateDir String
    | PRename String String
    | PDelete String
    | PExportSave
    | PNoop
    | PLaunchFile


type Pane
    = TreePane
    | EditorPane
    | PreviewPane


type Msg
    = ClickedOpenVault
    | ClickedTreeNode String
    | GotFsResponse D.Value
    | GotFileChanged D.Value
    | DismissError
    | NoOpFromRender
    | GotRenderMsg Render.RenderMsg
    | EditorChanged String
    | DebounceFired Int
    | GotSaveResult Int
    | SetNewName String
    | ClickedNewFile
    | ClickedDeleteSelected
    | ClickedChangeVault
    | ClickedRename
    | ClickedReloadExternal
    | ClickedKeepMine
    | ClickedExportHtml
    | ClickedExportLatex
    | GotOpenFile D.Value
    | ToggledFolder String
    | GotOpenFolders D.Value
    | SetSearchQuery String
    | ToggledReaderMode
