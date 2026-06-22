module ViewModeTest exposing (suite)

import Expect
import Test exposing (Test, describe, test)
import Types exposing (ViewMode(..), viewModeFromString)


suite : Test
suite =
    describe "Types.viewModeFromString"
        [ test "reader" <|
            \_ -> Expect.equal ViewReader (viewModeFromString "reader")
        , test "editor" <|
            \_ -> Expect.equal ViewEditor (viewModeFromString "editor")
        , test "both" <|
            \_ -> Expect.equal ViewBoth (viewModeFromString "both")
        , test "unknown falls back to Both" <|
            \_ -> Expect.equal ViewBoth (viewModeFromString "whatever")
        ]
