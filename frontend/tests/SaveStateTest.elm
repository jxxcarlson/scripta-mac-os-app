module SaveStateTest exposing (suite)

import Expect
import SaveState exposing (Action(..), SaveStatus(..))
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "SaveState"
        [ test "textChanged bumps debounceId and schedules a debounce" <|
            \_ ->
                let
                    ( s, action ) =
                        SaveState.textChanged 1000 SaveState.init
                in
                Expect.equal ( s.debounceId, action ) ( 1, ScheduleDebounce 1 1000 )
        , test "debounceFired for the latest id starts a save" <|
            \_ ->
                let
                    ( s1, _ ) =
                        SaveState.textChanged 1000 SaveState.init

                    ( _, action ) =
                        SaveState.debounceFired s1.debounceId s1
                in
                Expect.equal (PerformSave 1) action
        , test "a stale debounce id does nothing" <|
            \_ ->
                let
                    ( s1, _ ) =
                        SaveState.textChanged 1000 SaveState.init
                in
                Expect.equal NoAction (Tuple.second (SaveState.debounceFired 0 s1))
        , test "no overlapping saves: debounceFired is a no-op while in flight" <|
            \_ ->
                let
                    ( s1, _ ) =
                        SaveState.textChanged 1000 SaveState.init

                    ( s2, _ ) =
                        SaveState.debounceFired s1.debounceId s1

                    ( s3, _ ) =
                        SaveState.textChanged 1000 s2

                    ( _, action ) =
                        SaveState.debounceFired s3.debounceId s3
                in
                Expect.equal NoAction action
        , test "saveSucceeded resaves latest if user typed during the save" <|
            \_ ->
                let
                    ( s1, _ ) =
                        SaveState.textChanged 1000 SaveState.init

                    ( s2, _ ) =
                        SaveState.debounceFired s1.debounceId s1

                    ( s3, _ ) =
                        SaveState.textChanged 1000 s2

                    ( _, action ) =
                        SaveState.saveSucceeded s3
                in
                Expect.equal (PerformSave s3.debounceId) action
        , test "saveSucceeded settles to Saved when nothing changed" <|
            \_ ->
                let
                    ( s1, _ ) =
                        SaveState.textChanged 1000 SaveState.init

                    ( s2, _ ) =
                        SaveState.debounceFired s1.debounceId s1

                    ( s3, action ) =
                        SaveState.saveSucceeded s2
                in
                Expect.equal ( Saved, NoAction ) ( s3.saveStatus, action )
        ]
