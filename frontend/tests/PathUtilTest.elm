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
        ]
