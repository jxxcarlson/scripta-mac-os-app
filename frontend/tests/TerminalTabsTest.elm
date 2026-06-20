module TerminalTabsTest exposing (suite)

import Expect
import Test exposing (Test, describe, test)
import View


suite : Test
suite =
    describe "View.rightTabs"
        [ test "lists shell1, shell2, scratch in order" <|
            \_ ->
                Expect.equal
                    [ ( "shell1", "Shell 1" ), ( "shell2", "Shell 2" ), ( "scratch", "Scratch" ) ]
                    View.rightTabs
        , test "does not include an AI tab" <|
            \_ ->
                View.rightTabs
                    |> List.map Tuple.first
                    |> List.member "ai"
                    |> Expect.equal False
        ]
