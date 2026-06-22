module AiConfigTest exposing (suite)

import AiConfig
import Dict
import Expect
import Json.Decode as D
import Json.Encode as E
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "AiConfig"
        [ test "providers are anthropic, openai, gemini" <|
            \_ -> Expect.equal [ "anthropic", "openai", "gemini" ] AiConfig.providers
        , test "defaultModel per provider" <|
            \_ ->
                Expect.equal [ "claude-sonnet-4-6", "gpt-4o", "gemini-1.5-pro" ]
                    (List.map AiConfig.defaultModel [ "anthropic", "openai", "gemini" ])
        , test "last4 takes the last four chars" <|
            \_ -> Expect.equal "1234" (AiConfig.last4 "sk-abc1234")
        , test "last4 of a short string is the whole string" <|
            \_ -> Expect.equal "ab" (AiConfig.last4 "ab")
        , test "modelFor falls back to the provider default" <|
            \_ -> Expect.equal "gpt-4o" (AiConfig.modelFor "openai" AiConfig.init)
        , test "setModel then modelFor returns the set model" <|
            \_ ->
                Expect.equal "gpt-4o-mini"
                    (AiConfig.modelFor "openai" (AiConfig.setModel "openai" "gpt-4o-mini" AiConfig.init))
        , test "setHint / keyHint / clearHint" <|
            \_ ->
                let
                    c1 = AiConfig.setHint "anthropic" "1234" AiConfig.init
                    c2 = AiConfig.clearHint "anthropic" c1
                in
                Expect.equal ( Just "1234", Nothing )
                    ( AiConfig.keyHint "anthropic" c1, AiConfig.keyHint "anthropic" c2 )
        , test "encode then decode round-trips" <|
            \_ ->
                let
                    cfg =
                        AiConfig.init
                            |> AiConfig.setActiveProvider "gemini"
                            |> AiConfig.setModel "gemini" "gemini-2.0-flash"
                            |> AiConfig.setHint "gemini" "9999"
                in
                Expect.equal (Ok cfg) (D.decodeValue AiConfig.decoder (AiConfig.encode cfg))
        , test "agentDefault maps anthropic to claude" <|
            \_ -> Expect.equal "claude" (AiConfig.agentDefault "anthropic")
        , test "agentDefault maps openai to codex" <|
            \_ -> Expect.equal "codex" (AiConfig.agentDefault "openai")
        , test "agentDefault maps gemini to gemini" <|
            \_ -> Expect.equal "gemini" (AiConfig.agentDefault "gemini")
        , test "agentDefault falls back to claude for unknown" <|
            \_ -> Expect.equal "claude" (AiConfig.agentDefault "whatever")
        , test "effectiveAgentCommand uses the active provider default when unset" <|
            \_ -> Expect.equal "claude" (AiConfig.effectiveAgentCommand AiConfig.init)
        , test "effectiveAgentCommand uses a non-empty override" <|
            \_ -> Expect.equal "my-agent" (AiConfig.effectiveAgentCommand (AiConfig.setAgentCommand "my-agent" AiConfig.init))
        , test "effectiveAgentCommand trims the override" <|
            \_ -> Expect.equal "my-agent" (AiConfig.effectiveAgentCommand (AiConfig.setAgentCommand "  my-agent  " AiConfig.init))
        , test "effectiveAgentCommand falls back to default for whitespace override" <|
            \_ -> Expect.equal "claude" (AiConfig.effectiveAgentCommand (AiConfig.setAgentCommand "   " AiConfig.init))
        , test "encode/decode round-trips agentCommand" <|
            \_ ->
                AiConfig.setAgentCommand "codex" AiConfig.init
                    |> AiConfig.encode
                    |> D.decodeValue AiConfig.decoder
                    |> Result.map .agentCommand
                    |> Expect.equal (Ok "codex")
        , test "decoding without agentCommand yields empty string" <|
            \_ ->
                E.object [ ( "activeProvider", E.string "openai" ) ]
                    |> D.decodeValue AiConfig.decoder
                    |> Result.map .agentCommand
                    |> Expect.equal (Ok "")
        ]
