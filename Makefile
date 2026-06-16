.PHONY: elm dev build test test-elm test-rust icon

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

icon:
	cd src-tauri/icons && \
	rsvg-convert -w 1024 -h 1024 icon.svg -o icon.png && \
	rm -rf icon.iconset && mkdir icon.iconset && \
	sips -z 16 16     icon.png --out icon.iconset/icon_16x16.png && \
	sips -z 32 32     icon.png --out icon.iconset/icon_16x16@2x.png && \
	sips -z 32 32     icon.png --out icon.iconset/icon_32x32.png && \
	sips -z 64 64     icon.png --out icon.iconset/icon_32x32@2x.png && \
	sips -z 128 128   icon.png --out icon.iconset/icon_128x128.png && \
	sips -z 256 256   icon.png --out icon.iconset/icon_128x128@2x.png && \
	sips -z 256 256   icon.png --out icon.iconset/icon_256x256.png && \
	sips -z 512 512   icon.png --out icon.iconset/icon_256x256@2x.png && \
	sips -z 512 512   icon.png --out icon.iconset/icon_512x512.png && \
	cp icon.png icon.iconset/icon_512x512@2x.png && \
	iconutil -c icns icon.iconset -o icon.icns && \
	sips -z 32 32   icon.png --out 32x32.png && \
	sips -z 128 128 icon.png --out 128x128.png && \
	sips -z 256 256 icon.png --out 128x128@2x.png && \
	rm -rf icon.iconset
