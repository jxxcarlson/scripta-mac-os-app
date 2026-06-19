module ViewThemeTest exposing (suite)

import Expect
import Test exposing (Test, describe, test)
import View


suite : Test
suite =
    describe "View.themeName"
        [ test "light when isLight is True" <|
            \_ ->
                Expect.equal "light" (View.themeName True)
        , test "dark when isLight is False" <|
            \_ ->
                Expect.equal "dark" (View.themeName False)
        ]
