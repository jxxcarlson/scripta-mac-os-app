module Render.Settings exposing (RenderSettings, defaultRenderSettings)

import Dict exposing (Dict)


type alias RenderSettings =
    { windowWidth : Int
    , properties : Dict String String
    , isStandaloneDocument : Bool
    }


defaultRenderSettings : RenderSettings
defaultRenderSettings =
    { windowWidth = 600
    , properties = Dict.empty
    , isStandaloneDocument = True
    }
