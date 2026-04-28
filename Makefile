# KyroVoice — familiar targets similar to https://github.com/zachlatta/freeflow
# Prefer `swift build` + bundle step over raw swiftc because of WhisperKit / SPM.

.PHONY: all build run clean icon

BUILD_DIR := build

all: build

build:
	@./build.sh

run: build
	@./run.sh

clean:
	rm -rf .build "$(BUILD_DIR)"

ICON_SOURCE ?= Resources/AppIcon-Source.png
ICON_ICNS = Resources/AppIcon.icns

icon: $(ICON_ICNS)

$(ICON_ICNS): $(ICON_SOURCE)
	@test -f "$(ICON_SOURCE)" || (echo "Missing $(ICON_SOURCE). Add a 1024×1024 PNG (your app artwork), then run make icon."; exit 1)
	@mkdir -p "$(BUILD_DIR)/AppIcon.iconset"
	@sips -z 16 16 $< --out $(BUILD_DIR)/AppIcon.iconset/icon_16x16.png > /dev/null
	@sips -z 32 32 $< --out $(BUILD_DIR)/AppIcon.iconset/icon_16x16@2x.png > /dev/null
	@sips -z 32 32 $< --out $(BUILD_DIR)/AppIcon.iconset/icon_32x32.png > /dev/null
	@sips -z 64 64 $< --out $(BUILD_DIR)/AppIcon.iconset/icon_32x32@2x.png > /dev/null
	@sips -z 128 128 $< --out $(BUILD_DIR)/AppIcon.iconset/icon_128x128.png > /dev/null
	@sips -z 256 256 $< --out $(BUILD_DIR)/AppIcon.iconset/icon_128x128@2x.png > /dev/null
	@sips -z 256 256 $< --out $(BUILD_DIR)/AppIcon.iconset/icon_256x256.png > /dev/null
	@sips -z 512 512 $< --out $(BUILD_DIR)/AppIcon.iconset/icon_256x256@2x.png > /dev/null
	@sips -z 512 512 $< --out $(BUILD_DIR)/AppIcon.iconset/icon_512x512.png > /dev/null
	@sips -z 1024 1024 $< --out $(BUILD_DIR)/AppIcon.iconset/icon_512x512@2x.png > /dev/null
	@iconutil -c icns -o $@ $(BUILD_DIR)/AppIcon.iconset
	@rm -rf $(BUILD_DIR)/AppIcon.iconset
	@echo "Generated $@ — rebuild the app with ./build.sh or make build"
