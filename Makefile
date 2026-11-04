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

.PHONY: all gen build install run test clean doctor open-data team

all: build

gen:
	@xcodegen generate --quiet

# 小组件扩展必须带 app-sandbox entitlement 才会被系统收录；
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

build: gen $(WIDGET_ENT)
	@CONFIG=$(CONFIG) ./scripts/build.sh

install: build
	@mkdir -p $(INSTALL_DIR)
	@rm -rf $(INSTALLED_APP)
	@cp -R $(PRODUCT_DIR)/$(APP_NAME).app $(INSTALL_DIR)/
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
	@pkill -f "$(INSTALLED_APP)/Contents/MacOS/Memo" 2>/dev/null || true
	@sleep 1
	@open $(INSTALLED_APP)

team:
	@security find-identity -v -p codesigning | sed -n 's/.*Apple Development: \([^(]*\)(\([A-Z0-9]*\)).*/team=\2  identity=\1/p' || true

doctor:
	@echo "=== 证书 ==="
	@$(MAKE) --no-print-directory team || echo "(没有 Apple Development 证书 → 小组件不会被系统加载)"
	@echo "=== bundle ==="
	@ls -d $(INSTALLED_APP) 2>/dev/null || echo "app not installed"
	@echo "=== 签名 ==="
	@codesign -dv "$(INSTALLED_APP)/Contents/PlugIns/MemoWidget.appex" 2>&1 | grep -E "Identifier|TeamIdentifier|Signature" || true
	@echo "=== entitlements (widget) ==="
	@codesign -d --entitlements - "$(WIDGET_APPEX)" 2>/dev/null | tail -12 || echo "appex missing"
	@echo "=== pluginkit ==="
	@pluginkit -m -v -i com.hengji.memo.widget 2>/dev/null || true
	@echo "=== data dir ==="
	@ls -la "$(HOME)/Library/Application Support/Memo" 2>/dev/null || echo "(no data yet)"

open-data:
	@open "$(HOME)/Library/Application Support/Memo"

test: gen
	@set -o pipefail; xcodebuild \
		-project Memo.xcodeproj \
		-scheme Memo \
		-configuration $(CONFIG) \
		-derivedDataPath $(DERIVED) \
		CODE_SIGN_IDENTITY="-" \
		CODE_SIGNING_REQUIRED=YES \
		test 2>&1 | tee $(BUILD_DIR)/test.log | grep -E "error:|Test Suite|Executed|^\*\*" || true

clean:
	@rm -rf $(BUILD_DIR) Memo.xcodeproj
