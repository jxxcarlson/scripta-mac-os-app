module Types exposing (Model, Msg(..), PendingOp(..), Pane(..))

import AiConfig
import Chat
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
    , history : List String
    , future : List String
    , nextRequestId : Int
    , pending : Dict Int PendingOp
    , error : Maybe String
    , content : String
    , loadedContent : String
    , loadedMtime : Int
    , externalConflict : Bool
    , parsedDoc : Maybe Scripta.Document
    , imageSrc : Maybe String
    , language : Maybe Language.Language
    , isLight : Bool
    , contentWidth : Int
    , saveState : SaveState.SaveState
    , newName : String
    , openFolders : Set String
    , searchQuery : String
    , readerMode : Bool
    , fullParse : Bool
    , initialLastVault : Maybe String
    , aiConfig : AiConfig.AiConfig
    , aiKeyInput : Dict String String
    , showSettings : Bool
    , terminalVisible : Bool
    , terminalEverOpened : Bool
    , terminalTab : String
    , scratchContent : String
    , chatMessages : List Chat.ChatMessage
    , chatInput : String
    , chatPending : Bool
    , chatFileTitles : Dict Int String
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
    | PExportPdf
    | PNoop
    | PLaunchFile
    | PReadImage String
    | POpenExternal
    | PResolveDocLink
    | PSetApiKey String String
    | PDeleteApiKey String
    | PChatReply


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
    | ClickedExportPdf
    | GotOpenFile D.Value
    | ToggledFolder String
    | GotOpenFolders D.Value
    | SetSearchQuery String
    | ToggledReaderMode
    | ToggledParseMode
    | ToggledTheme
    | ClickedPrev
    | ClickedNext
    | ToggledSettings
    | SetActiveProvider String
    | SetProviderModel String String
    | AiKeyInput String String
    | SubmitApiKey String
    | DeleteApiKey String
    | ToggledTerminal
    | SelectTerminalTab String
    | CopyReply String
    | ClickedReload
    | ChatInput String
    | SendChat
    | ChatFileTitleInput Int String
    | ClickedChatFile Int String
