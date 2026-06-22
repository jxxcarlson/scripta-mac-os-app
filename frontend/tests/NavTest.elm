module NavTest exposing (suite)

import Expect
import Nav
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "Nav"
        [ test "prev pops history head and pushes current onto future" <|
            \_ ->
                Expect.equal
                    (Just { target = "a", history = [], future = [ "b" ] })
                    (Nav.prev (Just "b") [ "a" ] [])
        , test "prev with empty history is Nothing" <|
            \_ -> Expect.equal Nothing (Nav.prev (Just "b") [] [])
        , test "prev with no current does not push onto future" <|
            \_ ->
                Expect.equal
                    (Just { target = "a", history = [], future = [] })
                    (Nav.prev Nothing [ "a" ] [])
        , test "next pops future head and pushes current onto history" <|
            \_ ->
                Expect.equal
                    (Just { target = "b", history = [ "a" ], future = [] })
                    (Nav.next (Just "a") [] [ "b" ])
        , test "next with empty future is Nothing" <|
            \_ -> Expect.equal Nothing (Nav.next (Just "a") [] [])
        , test "prev then next round-trips back to the starting document" <|
            \_ ->
                -- At B with history [A]: Prev -> target A, future [B]
                case Nav.prev (Just "B") [ "A" ] [] of
                    Just afterPrev ->
                        -- Now at A (target) with history [], future [B]: Next -> target B, history [A]
                        Expect.equal
                            (Just { target = "B", history = [ "A" ], future = [] })
                            (Nav.next (Just afterPrev.target) afterPrev.history afterPrev.future)

                    Nothing ->
                        Expect.fail "prev should have produced a step"
        ]
