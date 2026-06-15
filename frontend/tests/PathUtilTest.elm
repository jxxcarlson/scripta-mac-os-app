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
        ]
