SHELL := /bin/bash
APP_NAME        := Memo
CONFIG          ?= Debug
BUILD_DIR       := build
DERIVED         := $(BUILD_DIR)/DerivedData
PRODUCT_DIR     := $(DERIVED)/Build/Products/$(CONFIG)
INSTALL_DIR     := $(HOME)/Applications
INSTALLED_APP   := $(INSTALL_DIR)/$(APP_NAME).app
WIDGET_APPEX    := $(INSTALLED_APP)/Contents/PlugIns/MemoWidget.appex
LOG             := $(BUILD_DIR)/xcodebuild.log
WIDGET_ENT      := $(BUILD_DIR)/MemoWidget.entitlements
DATA_DIR        := $(HOME)/Library/Application Support/Memo

.PHONY: all gen build install run test clean widget-register open-data doctor

# widget 扩展必须带 app-sandbox entitlement 才会被 pkd 收录；
# 同时用 temporary-exception 放行共享数据目录（App 本身不沙盒）。
$(WIDGET_ENT):
	@mkdir -p $(BUILD_DIR)
	@printf '%s\n' \
	  '<?xml version="1.0" encoding="UTF-8"?>' \
	  '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
	  '<plist version="1.0">' \
	  '<dict>' \
	  '  <key>com.apple.security.app-sandbox</key>' \
	  '  <true/>' \
	  '  <key>com.apple.security.temporary-exception.files.absolute-path.read-write</key>' \
	  '  <array>' \
	  '    <string>$(HOME)/Library/Application Support/Memo/</string>' \
	  '  </array>' \
	  '</dict>' \
	  '</plist>' > $@

all: build

gen:
	@xcodegen generate --quiet

build: gen
	@mkdir -p $(BUILD_DIR)
	@set -o pipefail; xcodebuild \
		-project Memo.xcodeproj \
		-scheme Memo \
		-configuration $(CONFIG) \
		-derivedDataPath $(DERIVED) \
		CODE_SIGN_IDENTITY="-" \
		CODE_SIGNING_REQUIRED=YES \
		build 2>&1 | tee $(LOG) | grep -E "error:|warning:|^BUILD|^\*\*" || true
	@if grep -q "^\*\* BUILD SUCCEEDED" $(LOG); then echo "✅ build ok"; else echo "❌ build failed (see $(LOG))"; exit 1; fi

install: build $(WIDGET_ENT)
	@mkdir -p $(INSTALL_DIR)
	@rm -rf $(INSTALLED_APP)
	@cp -R $(PRODUCT_DIR)/$(APP_NAME).app $(INSTALL_DIR)/
	@# 先签内层 appex（带 sandbox entitlement），再签外层 app
	@codesign --force --sign - --entitlements $(WIDGET_ENT) "$(WIDGET_APPEX)"
	@codesign --force --sign - "$(INSTALLED_APP)"
	@/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f $(INSTALLED_APP) || true
	@echo "✅ installed to $(INSTALLED_APP)"
	@$(MAKE) --no-print-directory widget-register

widget-register:
	@if [ -d "$(WIDGET_APPEX)" ]; then \
		pluginkit -a "$(WIDGET_APPEX)" 2>/dev/null || true; \
		echo "✅ widget registered: $(WIDGET_APPEX)"; \
		pluginkit -m -v -i com.hengji.memo.widget 2>/dev/null || true; \
	else \
		echo "⚠️  widget appex not found at $(WIDGET_APPEX)"; \
	fi

run: install
	@open $(INSTALLED_APP)

open-data:
	@open "$(HOME)/Library/Application Support/Memo"

doctor:
	@echo "=== bundle =="
	@ls -d $(INSTALLED_APP) 2>/dev/null || echo "app not installed"
	@echo "=== entitlements (widget) ==="
	@codesign -d --entitlements - "$(WIDGET_APPEX)" 2>/dev/null | tail -12 || echo "appex missing"
	@echo "=== pluginkit ==="
	@pluginkit -m -v -i com.hengji.memo.widget 2>/dev/null || true
	@echo "=== data dir ==="
	@ls -la "$(DATA_DIR)" 2>/dev/null || echo "(no data yet)"

test: gen
	@set -o pipefail; xcodebuild \
		-project Memo.xcodeproj \
		-scheme Memo \
		-configuration $(CONFIG) \
		-derivedDataPath $(DERIVED) \
		CODE_SIGN_IDENTITY="-" \
		CODE_SIGNING_REQUIRED=YES \
		test 2>&1 | tee $(BUILD_DIR)/test.log | grep -E "error:|Test Suite|Executed|^BUILD|^\*\*|✔|✘|passed|failed" || true

clean:
	@rm -rf $(BUILD_DIR) Memo.xcodeproj
