.PHONY: elm dev build install test test-elm test-rust icon

elm:
	cd frontend && elm make src/Main.elm --output=dist/elm.js

dev: elm
	npx tauri dev

build:
	npx tauri build

# Build the release app and install it into /Applications, replacing any
# existing copy. `make build` only writes to src-tauri/target/release/bundle;
# this is what makes a double-clicked /Applications/Scripta.app reflect new code.
# Quits a running instance first so the bundle can be replaced cleanly.
install: build
	@osascript -e 'tell application "Scripta" to quit' 2>/dev/null || true
	@sleep 1
	@rm -rf "/Applications/Scripta.app"
	@ditto "src-tauri/target/release/bundle/macos/Scripta.app" "/Applications/Scripta.app"
	@echo "Installed Scripta.app -> /Applications"

test: test-elm test-rust

test-elm:
	cd frontend && elm-test

test-rust:
	cd src-tauri && cargo test

# Regenerate the app icon set from icon.svg (requires rsvg-convert).
# The generated icon.png/.icns + PNG sizes are committed so `make build`
# works without rsvg-convert installed; re-run this after editing icon.svg.
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
