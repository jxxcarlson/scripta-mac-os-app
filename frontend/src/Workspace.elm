module Workspace exposing
    ( Entry, Node(..)
    , entryDecoder, toTree, filter
    , nodeName, nodePath, folderChildren
    )

{-| Workspace (vault) file tree. The Rust shell sends a flat list of `Entry`;
`toTree` nests them by path. A node's id is its workspace-relative `path`.
-}

import Json.Decode as D


type alias Entry =
    { path : String
    , name : String
    , isDir : Bool
    , mtime : Int
    }


type Node
    = FileNode { path : String, name : String, mtime : Int }
    | FolderNode { path : String, name : String, children : List Node }


entryDecoder : D.Decoder Entry
entryDecoder =
    D.map4 Entry
        (D.field "path" D.string)
        (D.field "name" D.string)
        (D.field "is_dir" D.bool)
        (D.field "mtime" D.int)


{-| Build top-level nodes from the flat entry list. Entries may arrive in any
order; we sort by path first so parents precede children.
-}
toTree : List Entry -> List Node
toTree entries =
    buildLevel "" (List.sortBy .path entries)


parentOf : String -> String
parentOf path =
    case path |> String.split "/" |> List.reverse of
        _ :: rest ->
            rest |> List.reverse |> String.join "/"

        [] ->
            ""


{-| Build all nodes whose parent path equals `parent`.
-}
buildLevel : String -> List Entry -> List Node
buildLevel parent entries =
    entries
        |> List.filter (\e -> parentOf e.path == parent)
        |> List.map
            (\e ->
                if e.isDir then
                    FolderNode
                        { path = e.path
                        , name = e.name
                        , children = buildLevel e.path entries
                        }

                else
                    FileNode { path = e.path, name = e.name, mtime = e.mtime }
            )


{-| Keep only file nodes whose name contains `query` (case-insensitive), plus
the folders on the path to any such file. Folders are matched only through their
descendants — a folder name itself never matches. An empty result means nothing
matched.
-}
filter : String -> List Node -> List Node
filter query nodes =
    let
        q =
            String.toLower query
    in
    List.filterMap (filterNode q) nodes


filterNode : String -> Node -> Maybe Node
filterNode q node =
    case node of
        FileNode r ->
            if String.contains q (String.toLower r.name) then
                Just node

            else
                Nothing

        FolderNode r ->
            case List.filterMap (filterNode q) r.children of
                [] ->
                    Nothing

                kept ->
                    Just (FolderNode { r | children = kept })


nodeName : Node -> String
nodeName node =
    case node of
        FileNode r ->
            r.name

        FolderNode r ->
            r.name


nodePath : Node -> String
nodePath node =
    case node of
        FileNode r ->
            r.path

        FolderNode r ->
            r.path


folderChildren : Node -> Maybe (List Node)
folderChildren node =
    case node of
        FolderNode r ->
            Just r.children

        FileNode _ ->
            Nothing
