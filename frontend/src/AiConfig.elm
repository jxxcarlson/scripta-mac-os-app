module AiConfig exposing
    ( AiConfig
    , init, providers, providerLabel, modelsFor, defaultModel, last4
    , activeProvider, modelFor, keyHint, agentDefault, effectiveAgentCommand
    , setActiveProvider, setModel, setHint, clearHint, setAgentCommand
    , encode, decoder
    )

{-| Non-secret AI provider configuration: which provider is active, the chosen
model per provider, and a last-4 hint per provider (presence ⇔ a key is stored
in the Keychain). The secret keys themselves live in the macOS Keychain and are
never represented here.
-}

import Dict exposing (Dict)
import Json.Decode as D
import Json.Encode as E


type alias AiConfig =
    { activeProvider : String
    , models : Dict String String
    , keyHints : Dict String String
    , agentCommand : String
    }


init : AiConfig
init =
    { activeProvider = "anthropic", models = Dict.empty, keyHints = Dict.empty, agentCommand = "" }


providers : List String
providers =
    [ "anthropic", "openai", "gemini" ]


providerLabel : String -> String
providerLabel p =
    case p of
        "anthropic" ->
            "Anthropic"

        "openai" ->
            "OpenAI"

        "gemini" ->
            "Gemini"

        _ ->
            p


modelsFor : String -> List String
modelsFor p =
    case p of
        "anthropic" ->
            [ "claude-opus-4-8", "claude-sonnet-4-6", "claude-haiku-4-5" ]

        "openai" ->
            [ "gpt-4o", "gpt-4o-mini", "gpt-4.1" ]

        "gemini" ->
            [ "gemini-2.0-flash", "gemini-1.5-pro", "gemini-1.5-flash" ]

        _ ->
            []


defaultModel : String -> String
defaultModel p =
    case p of
        "anthropic" ->
            "claude-sonnet-4-6"

        "openai" ->
            "gpt-4o"

        "gemini" ->
            "gemini-1.5-pro"

        _ ->
            ""


last4 : String -> String
last4 =
    String.right 4


activeProvider : AiConfig -> String
activeProvider cfg =
    cfg.activeProvider


modelFor : String -> AiConfig -> String
modelFor p cfg =
    Dict.get p cfg.models |> Maybe.withDefault (defaultModel p)


keyHint : String -> AiConfig -> Maybe String
keyHint p cfg =
    Dict.get p cfg.keyHints


{-| The default CLI agent command for a provider. -}
agentDefault : String -> String
agentDefault p =
    case p of
        "anthropic" ->
            "claude"

        "openai" ->
            "codex"

        "gemini" ->
            "gemini"

        _ ->
            "claude"


{-| The agent command to run: the explicit override when set (trimmed),
otherwise the active provider's default. -}
effectiveAgentCommand : AiConfig -> String
effectiveAgentCommand cfg =
    let
        trimmed =
            String.trim cfg.agentCommand
    in
    if trimmed == "" then
        agentDefault cfg.activeProvider

    else
        trimmed


setActiveProvider : String -> AiConfig -> AiConfig
setActiveProvider p cfg =
    { cfg | activeProvider = p }


setModel : String -> String -> AiConfig -> AiConfig
setModel p m cfg =
    { cfg | models = Dict.insert p m cfg.models }


setHint : String -> String -> AiConfig -> AiConfig
setHint p h cfg =
    { cfg | keyHints = Dict.insert p h cfg.keyHints }


clearHint : String -> AiConfig -> AiConfig
clearHint p cfg =
    { cfg | keyHints = Dict.remove p cfg.keyHints }


setAgentCommand : String -> AiConfig -> AiConfig
setAgentCommand cmd cfg =
    { cfg | agentCommand = cmd }


encode : AiConfig -> E.Value
encode cfg =
    E.object
        [ ( "activeProvider", E.string cfg.activeProvider )
        , ( "models", E.dict identity E.string cfg.models )
        , ( "keyHints", E.dict identity E.string cfg.keyHints )
        , ( "agentCommand", E.string cfg.agentCommand )
        ]


decoder : D.Decoder AiConfig
decoder =
    D.map4 AiConfig
        (D.oneOf [ D.field "activeProvider" D.string, D.succeed "anthropic" ])
        (D.oneOf [ D.field "models" (D.dict D.string), D.succeed Dict.empty ])
        (D.oneOf [ D.field "keyHints" (D.dict D.string), D.succeed Dict.empty ])
        (D.oneOf [ D.field "agentCommand" D.string, D.succeed "" ])
