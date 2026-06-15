module Types exposing (Model, Msg(..), PendingOp(..), Pane(..))

import Dict exposing (Dict)
import Json.Decode as D
import Language
import SaveState
import Scripta
import Workspace exposing (Node)


type alias Model =
    { vaultRoot : Maybe String
    , tree : List Node
    , selectedPath : Maybe String
    , nextRequestId : Int
    , pending : Dict Int PendingOp
    , error : Maybe String
    , content : String
    , parsedDoc : Maybe Scripta.Document
    , language : Maybe Language.Language
    , isLight : Bool
    , contentWidth : Int
    , saveState : SaveState.SaveState
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
    | EditorChanged String
    | DebounceFired Int
    | GotSaveResult Int
