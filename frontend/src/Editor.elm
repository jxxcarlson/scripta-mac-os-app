module Editor exposing (docBodyId, renderedTextId, textChangeDecoder)

import Json.Decode as D


{-| The DOM id for the rendered content container.
The R-to-L sync JS (in codemirror-element.js) looks for this id to attach
click and selection handlers. Must match the JS constant.
-}
renderedTextId : String
renderedTextId =
    "__RENDERED_TEXT__"


{-| The DOM id for the scrollable document body container.
This is the element with overflow-y: auto that we scroll.
-}
docBodyId : String
docBodyId =
    "__DOC_BODY__"


{-| Decode the `text-change` custom event from the CodeMirror custom element.
Shape: `{ detail: { position: Int, source: String } }`. We extract the source.
-}
textChangeDecoder : D.Decoder String
textChangeDecoder =
    D.at [ "detail", "source" ] D.string
