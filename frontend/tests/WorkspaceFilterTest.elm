module WorkspaceFilterTest exposing (suite)

import Expect
import Test exposing (Test, describe, test)
import Workspace exposing (Node(..))


tree : List Node
tree =
    [ FileNode { path = "avogadro.md", name = "avogadro.md", mtime = 1 }
    , FolderNode
        { path = "Courses"
        , name = "Courses"
        , children =
            [ FileNode { path = "Courses/composition.md", name = "composition.md", mtime = 2 }
            , FileNode { path = "Courses/index.md", name = "index.md", mtime = 3 }
            ]
        }
    , FolderNode
        { path = "Empty"
        , name = "Empty"
        , children =
            [ FileNode { path = "Empty/notes.md", name = "notes.md", mtime = 4 } ]
        }
    ]


names : List Node -> List String
names ns =
    List.map Workspace.nodeName ns


suite : Test
suite =
    describe "Workspace.filter"
        [ test "keeps matching files and their ancestor folders" <|
            \_ ->
                let
                    result =
                        Workspace.filter "composition" tree
                in
                Expect.equal [ "Courses" ] (names result)
        , test "is case-insensitive" <|
            \_ ->
                Workspace.filter "AVOGADRO" tree
                    |> names
                    |> Expect.equal [ "avogadro.md" ]
        , test "drops folders with no matching descendant" <|
            \_ ->
                Workspace.filter "composition" tree
                    |> List.filterMap Workspace.folderChildren
                    |> List.concat
                    |> names
                    |> Expect.equal [ "composition.md" ]
        , test "no match yields empty list" <|
            \_ ->
                Workspace.filter "zzzznotfound" tree
                    |> Expect.equal []
        , test "does not match on folder names" <|
            \_ ->
                Workspace.filter "Courses" tree
                    |> Expect.equal []
        ]
