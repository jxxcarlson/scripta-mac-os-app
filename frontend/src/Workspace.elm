module Workspace exposing
    ( Entry, Node(..)
    , entryDecoder, toTree, filter
    , nodeName, nodePath, folderChildren, splitIndexFile
    , hasFile, hideCompactIndex
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


{-| True if any file node anywhere in the forest has exactly this path. Used to
check whether a sibling `_index-compact.md` exists.
-}
hasFile : String -> List Node -> Bool
hasFile path nodes =
    List.any
        (\node ->
            case node of
                FileNode r ->
                    r.path == path

                FolderNode r ->
                    hasFile path r.children
        )
        nodes


{-| Drop file nodes named `_index-compact.md` from the forest. Used to hide the
compact index files from the tree when `indexCompact` is on (they're substitutes
opened via the `_index.md` node, not navigated to directly).
-}
hideCompactIndex : List Node -> List Node
hideCompactIndex nodes =
    List.filterMap
        (\node ->
            case node of
                FileNode r ->
                    if r.name == "_index-compact.md" then
                        Nothing

                    else
                        Just node

                FolderNode r ->
                    Just (FolderNode { r | children = hideCompactIndex r.children })
        )
        nodes


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


{-| Split a folder's immediate children into its `_index.md` file (if any) and
the remaining children. Only a `FileNode` named exactly `_index.md` matches; a
folder of that name does not. The remaining children keep their order.
-}
splitIndexFile : List Node -> ( Maybe Node, List Node )
splitIndexFile children =
    let
        isIndex n =
            case n of
                FileNode r ->
                    r.name == "_index.md"

                FolderNode _ ->
                    False
    in
    case List.filter isIndex children of
        idx :: _ ->
            ( Just idx, List.filter (\n -> not (isIndex n)) children )

        [] ->
            ( Nothing, children )
