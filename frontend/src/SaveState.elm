module SaveState exposing
    ( SaveState, SaveStatus(..), Action(..)
    , init, textChanged, debounceFired, saveSucceeded, saveFailed
    )

{-| Pure debounced-save state machine for a single local writer.

Guarantees:
  - At most one write is in flight (`inFlight`).
  - If the user types while a write is in flight, exactly one follow-up write
    fires after it completes, capturing the latest content (debounceId /= savingId).

Trimmed from scripta-app-v4's SaveState: the 403 (baton) and 409 (version
conflict) recovery paths are removed — there is only one local writer. External
edits are handled separately via the file watcher.
-}


type SaveStatus
    = Saved
    | Unsaved
    | Saving


type alias SaveState =
    { saveStatus : SaveStatus
    , debounceId : Int
    , hasUnsavedContent : Bool
    , inFlight : Bool
    , savingId : Int
    }


type Action
    = NoAction
    | ScheduleDebounce Int Float
    | PerformSave Int


init : SaveState
init =
    { saveStatus = Saved
    , debounceId = 0
    , hasUnsavedContent = False
    , inFlight = False
    , savingId = 0
    }


textChanged : Float -> SaveState -> ( SaveState, Action )
textChanged debounceDelayMs state =
    let
        newId =
            state.debounceId + 1

        newStatus =
            if state.inFlight then
                Saving

            else
                Unsaved
    in
    ( { state | saveStatus = newStatus, debounceId = newId, hasUnsavedContent = True }
    , ScheduleDebounce newId debounceDelayMs
    )


debounceFired : Int -> SaveState -> ( SaveState, Action )
debounceFired firedId state =
    if firedId == state.debounceId && state.hasUnsavedContent && not state.inFlight then
        ( { state | saveStatus = Saving, inFlight = True, savingId = firedId }
        , PerformSave firedId
        )

    else
        ( state, NoAction )


saveSucceeded : SaveState -> ( SaveState, Action )
saveSucceeded state =
    if state.debounceId /= state.savingId then
        ( { state | saveStatus = Saving, inFlight = True, savingId = state.debounceId }
        , PerformSave state.debounceId
        )

    else
        ( { state | saveStatus = Saved, hasUnsavedContent = False, inFlight = False }
        , NoAction
        )


saveFailed : SaveState -> ( SaveState, Action )
saveFailed state =
    ( { state | saveStatus = Unsaved, inFlight = False }, NoAction )
