module FileOpsTest exposing (suite)

import Expect
import FileOps exposing (FsResponse)
import Json.Decode as D
import Json.Encode as E
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "FileOps"
        [ test "encodes a readFile request with op, requestId, and args" <|
            \_ ->
                let
                    value =
                        FileOps.encodeRequest 7 "read_file" [ ( "path", E.string "a.scripta" ) ]

                    decoded =
                        D.decodeValue
                            (D.map3 (\a b c -> ( a, b, c ))
                                (D.field "requestId" D.int)
                                (D.field "op" D.string)
                                (D.at [ "args", "path" ] D.string)
                            )
                            value
                in
                Expect.equal (Ok ( 7, "read_file", "a.scripta" )) decoded
        , test "decodes a successful response" <|
            \_ ->
                let
                    json =
                        """{"requestId":7,"ok":true,"result":{"content":"hi","mtime":42}}"""
                in
                case D.decodeString FileOps.responseDecoder json of
                    Ok resp ->
                        Expect.equal 7 resp.requestId

                    Err e ->
                        Expect.fail (D.errorToString e)
        , test "decodes a failed response carrying the error" <|
            \_ ->
                let
                    json =
                        """{"requestId":9,"ok":false,"error":"ENOENT"}"""
                in
                case D.decodeString FileOps.responseDecoder json of
                    Ok resp ->
                        Expect.equal (Err "ENOENT") (FileOps.resultOf resp)

                    Err e ->
                        Expect.fail (D.errorToString e)
        ]
