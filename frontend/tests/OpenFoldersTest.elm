module OpenFoldersTest exposing (suite)

import Expect
import Json.Encode as E
import OpenFolders
import Set
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "OpenFolders"
        [ test "toggle adds a path when absent" <|
            \_ ->
                OpenFolders.toggle "a/b" Set.empty
                    |> Set.member "a/b"
                    |> Expect.equal True
        , test "toggle removes a path when present" <|
            \_ ->
                Set.singleton "a/b"
                    |> OpenFolders.toggle "a/b"
                    |> Set.member "a/b"
                    |> Expect.equal False
        , test "toggle twice returns the original set" <|
            \_ ->
                let
                    start =
                        Set.fromList [ "x", "y" ]
                in
                start
                    |> OpenFolders.toggle "z"
                    |> OpenFolders.toggle "z"
                    |> Expect.equal start
        , test "fromValue decodes a JSON array of strings" <|
            \_ ->
                E.list E.string [ "a", "b/c" ]
                    |> OpenFolders.fromValue
                    |> Expect.equal (Set.fromList [ "a", "b/c" ])
        , test "fromValue of a malformed value is the empty set" <|
            \_ ->
                E.int 42
                    |> OpenFolders.fromValue
                    |> Expect.equal Set.empty
        ]
