module PathUtilTest exposing (suite)

import Expect
import PathUtil
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "PathUtil"
        [ test "basename of an absolute path" <|
            \_ -> Expect.equal "c.scripta" (PathUtil.basename "/a/b/c.scripta")
        , test "basename of a bare filename" <|
            \_ -> Expect.equal "c.scripta" (PathUtil.basename "c.scripta")
        , test "parentDir of an absolute path" <|
            \_ -> Expect.equal "/a/b" (PathUtil.parentDir "/a/b/c.scripta")
        , test "parentDir of a bare filename is empty" <|
            \_ -> Expect.equal "" (PathUtil.parentDir "c.scripta")
        , test "parentDir of a relative path" <|
            \_ -> Expect.equal "sub" (PathUtil.parentDir "sub/c.scripta")
        , test "siblingPath with no reference returns the bare name" <|
            \_ -> Expect.equal "intro.scripta" (PathUtil.siblingPath Nothing "intro.scripta")
        , test "siblingPath beside a root-level doc returns the bare name" <|
            \_ -> Expect.equal "intro.scripta" (PathUtil.siblingPath (Just "notes.scripta") "intro.scripta")
        , test "siblingPath beside a nested doc keeps the folder" <|
            \_ -> Expect.equal "Physics/intro.scripta" (PathUtil.siblingPath (Just "Physics/notes.scripta") "intro.scripta")
        , test "siblingPath beside a deeply nested doc keeps the full folder" <|
            \_ -> Expect.equal "A/B/d.scripta" (PathUtil.siblingPath (Just "A/B/c.scripta") "d.scripta")
        , test "kbaseRoot returns the vault path when it ends in kbase" <|
            \_ ->
                Expect.equal (Just "/Users/c/CloudDocs/kbase")
                    (PathUtil.kbaseRoot "/Users/c/CloudDocs/kbase")
        , test "kbaseRoot truncates a kbase descendant to the kbase root" <|
            \_ ->
                Expect.equal (Just "/Users/c/CloudDocs/kbase")
                    (PathUtil.kbaseRoot "/Users/c/CloudDocs/kbase/Subjects/Physics")
        , test "kbaseRoot is Nothing when there is no kbase segment" <|
            \_ ->
                Expect.equal Nothing (PathUtil.kbaseRoot "/Users/c/projects/notes")
        , test "kbaseRoot requires an exact segment match (not a prefix)" <|
            \_ ->
                Expect.equal Nothing (PathUtil.kbaseRoot "/Users/c/kbase-backup/x")
        , test "ancestorDirs of a nested path lists each ancestor folder" <|
            \_ -> Expect.equal [ "a", "a/b" ] (PathUtil.ancestorDirs "a/b/c.md")
        , test "ancestorDirs of a single-folder path" <|
            \_ -> Expect.equal [ "Inbox" ] (PathUtil.ancestorDirs "Inbox/foo.md")
        , test "ancestorDirs of a root-level file is empty" <|
            \_ -> Expect.equal [] (PathUtil.ancestorDirs "foo.md")
        , test "withDefaultExtension appends when there is no extension" <|
            \_ -> Expect.equal "notes.md" (PathUtil.withDefaultExtension "md" "notes")
        , test "withDefaultExtension keeps an existing extension" <|
            \_ -> Expect.equal "notes.scripta" (PathUtil.withDefaultExtension "md" "notes.scripta")
        , test "withDefaultExtension keeps a multi-dot name unchanged" <|
            \_ -> Expect.equal "a.b.md" (PathUtil.withDefaultExtension "md" "a.b.md")
        , test "withDefaultExtension only inspects the basename" <|
            \_ -> Expect.equal "Inbox/notes.md" (PathUtil.withDefaultExtension "md" "Inbox/notes")
        ]
