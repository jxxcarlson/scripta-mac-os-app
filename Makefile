.PHONY: elm dev build test test-elm test-rust

elm:
	cd frontend && elm make src/Main.elm --output=dist/elm.js

dev: elm
	npx tauri dev

build:
	npx tauri build

test: test-elm test-rust

test-elm:
	cd frontend && elm-test

test-rust:
	cd src-tauri && cargo test
