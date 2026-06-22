module VaultShellLabelTest exposing (suite)

import Expect
import Test exposing (Test, describe, test)
import View


suite : Test
suite =
    describe "View.vaultShellLabel"
        [ test "uses the vault folder basename when a vault is open" <|
            \_ -> Expect.equal "kbase" (View.vaultShellLabel (Just "/Users/c/CloudDocs/kbase"))
        , test "uses the basename for a nested-looking root too" <|
            \_ -> Expect.equal "MyVault" (View.vaultShellLabel (Just "/a/b/MyVault"))
        , test "falls back to 'Shell 1' when no vault is open" <|
            \_ -> Expect.equal "Shell 1" (View.vaultShellLabel Nothing)
        ]
