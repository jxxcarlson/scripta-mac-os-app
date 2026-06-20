module FlagsTest exposing (suite)

import AiConfig
import Expect
import Flags
import Json.Encode as E
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "Flags.decode"
        [ test "decodes a full flags object" <|
            \_ ->
                let
                    v =
                        E.object [ ( "lastVault", E.string "/Users/me/vault" ), ( "readerMode", E.bool True ) ]

                    f =
                        Flags.decode v
                in
                Expect.equal ( Just "/Users/me/vault", True ) ( f.lastVault, f.readerMode )
        , test "missing lastVault decodes to Nothing" <|
            \_ ->
                let
                    f =
                        Flags.decode (E.object [ ( "readerMode", E.bool False ) ])
                in
                Expect.equal Nothing f.lastVault
        , test "null lastVault decodes to Nothing" <|
            \_ ->
                let
                    f =
                        Flags.decode (E.object [ ( "lastVault", E.null ), ( "readerMode", E.bool False ) ])
                in
                Expect.equal Nothing f.lastVault
        , test "missing/garbage readerMode defaults to False" <|
            \_ ->
                let
                    f =
                        Flags.decode (E.object [ ( "readerMode", E.string "yes" ) ])
                in
                Expect.equal False f.readerMode
        , test "a non-object value yields defaults" <|
            \_ ->
                let
                    f =
                        Flags.decode (E.int 5)
                in
                Expect.equal ( Nothing, False ) ( f.lastVault, f.readerMode )
        , test "missing fullParse defaults to True" <|
            \_ ->
                Expect.equal True (Flags.decode (E.object [ ( "readerMode", E.bool False ) ])).fullParse
        , test "fullParse false decodes to False" <|
            \_ ->
                Expect.equal False (Flags.decode (E.object [ ( "fullParse", E.bool False ) ])).fullParse
        , test "fullParse true decodes to True" <|
            \_ ->
                Expect.equal True (Flags.decode (E.object [ ( "fullParse", E.bool True ) ])).fullParse
        , test "missing isLight defaults to True" <|
            \_ ->
                Expect.equal True (Flags.decode (E.object [ ( "readerMode", E.bool False ) ])).isLight
        , test "isLight false decodes to False" <|
            \_ ->
                Expect.equal False (Flags.decode (E.object [ ( "isLight", E.bool False ) ])).isLight
        , test "isLight true decodes to True" <|
            \_ ->
                Expect.equal True (Flags.decode (E.object [ ( "isLight", E.bool True ) ])).isLight
        , test "missing aiConfig decodes to AiConfig.init" <|
            \_ ->
                Expect.equal AiConfig.init (Flags.decode (E.object [])).aiConfig
        , test "aiConfig is decoded when present" <|
            \_ ->
                let
                    cfg =
                        AiConfig.setActiveProvider "gemini" AiConfig.init

                    v =
                        E.object [ ( "aiConfig", AiConfig.encode cfg ) ]
                in
                Expect.equal "gemini" (Flags.decode v).aiConfig.activeProvider
        , test "missing terminalVisible defaults to False" <|
            \_ -> Expect.equal False (Flags.decode (E.object [])).terminalVisible
        , test "terminalVisible true decodes to True" <|
            \_ -> Expect.equal True (Flags.decode (E.object [ ( "terminalVisible", E.bool True ) ])).terminalVisible
        , test "decodes scratchContent" <|
            \_ ->
                Flags.decode (E.object [ ( "scratchContent", E.string "hello" ) ])
                    |> .scratchContent
                    |> Expect.equal "hello"
        , test "missing scratchContent defaults to empty string" <|
            \_ ->
                Flags.decode (E.object [])
                    |> .scratchContent
                    |> Expect.equal ""
        ]
