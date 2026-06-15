module WorkspaceTest exposing (suite)

import Expect
import Json.Decode as D
import Test exposing (Test, describe, test)
import Workspace exposing (Entry, Node(..))


flatJson : String
flatJson =
    """
    [ {"path":"a.scripta","name":"a.scripta","is_dir":false,"mtime":10}
    , {"path":"sub","name":"sub","is_dir":true,"mtime":0}
    , {"path":"sub/b.scripta","name":"b.scripta","is_dir":false,"mtime":20}
    ]
    """


suite : Test
suite =
    describe "Workspace"
        [ test "decodes a flat entry list" <|
            \_ ->
                case D.decodeString (D.list Workspace.entryDecoder) flatJson of
                    Ok entries ->
                        Expect.equal 3 (List.length entries)

                    Err e ->
                        Expect.fail (D.errorToString e)
        , test "builds a tree with sub-folder nesting" <|
            \_ ->
                case D.decodeString (D.list Workspace.entryDecoder) flatJson of
                    Ok entries ->
                        let
                            roots =
                                Workspace.toTree entries
                        in
                        Expect.equal [ "a.scripta", "sub" ] (List.map Workspace.nodeName roots)

                    Err e ->
                        Expect.fail (D.errorToString e)
        , test "folder node contains its child file" <|
            \_ ->
                case D.decodeString (D.list Workspace.entryDecoder) flatJson of
                    Ok entries ->
                        let
                            childNames =
                                Workspace.toTree entries
                                    |> List.filterMap Workspace.folderChildren
                                    |> List.concat
                                    |> List.map Workspace.nodeName
                        in
                        Expect.equal [ "b.scripta" ] childNames

                    Err e ->
                        Expect.fail (D.errorToString e)
        ]
