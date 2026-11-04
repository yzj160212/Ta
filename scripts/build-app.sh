#!/bin/zsh

set -euo pipefail

PROJECT_ROOT_DIR="${0:A:h:h}"
PRODUCT_NAME="拓"
EXECUTABLE_NAME="AIScreenshotApp"
APP_BUNDLE_DIR="$PROJECT_ROOT_DIR/artifacts/$PRODUCT_NAME.app"

cd "$PROJECT_ROOT_DIR"

swift build -c release --product "$EXECUTABLE_NAME"
SWIFT_BIN_DIR="$(swift build -c release --show-bin-path)"

mkdir -p "$APP_BUNDLE_DIR/Contents/MacOS" "$APP_BUNDLE_DIR/Contents/Resources"
rm -f \
    "$APP_BUNDLE_DIR/Contents/Resources/Tuo.icns" \
    "$APP_BUNDLE_DIR/Contents/Resources/Brand/Tuo-AppIcon.png" \
    "$APP_BUNDLE_DIR/Contents/Resources/TaMenuBar.png"
cp "$SWIFT_BIN_DIR/$EXECUTABLE_NAME" "$APP_BUNDLE_DIR/Contents/MacOS/$EXECUTABLE_NAME"
cp "$PROJECT_ROOT_DIR/Resources/Info.plist" "$APP_BUNDLE_DIR/Contents/Info.plist"
cp "$PROJECT_ROOT_DIR/Resources/Ta.icns" "$APP_BUNDLE_DIR/Contents/Resources/Ta.icns"
mkdir -p "$APP_BUNDLE_DIR/Contents/Resources/Brand"
cp "$PROJECT_ROOT_DIR/Resources/Brand/Ta-AppIcon.png" "$APP_BUNDLE_DIR/Contents/Resources/Brand/Ta-AppIcon.png"
rm -rf "$APP_BUNDLE_DIR/Contents/Resources/Brand/Providers"
cp -R "$PROJECT_ROOT_DIR/Resources/Brand/Providers" "$APP_BUNDLE_DIR/Contents/Resources/Brand/Providers"

chmod 755 "$APP_BUNDLE_DIR/Contents/MacOS/$EXECUTABLE_NAME"
# OCR 增强包清单（远端地址烘进 Info.plist / 可选内置本地清单）。
# 逻辑在 scripts/inject-ocr-catalog.sh —— CI 出包走同一段，避免两条组装路径各写一套。
"$PROJECT_ROOT_DIR/scripts/inject-ocr-catalog.sh" "$APP_BUNDLE_DIR" "$PROJECT_ROOT_DIR"

plutil -lint "$APP_BUNDLE_DIR/Contents/Info.plist"

# 签名身份解析顺序：
#   1. AI_SCREENSHOT_SIGNING_IDENTITY 显式指定
#   2. Developer ID Application（发行用，最稳）
#   3. Apple Development（有开发者账号时的开发证书）
#   4. 本机其它有效的 codesigning 身份 —— 例如自己创建的自签证书（"Koe Dev"）
#   5. 都找不到才回落到 ad-hoc
#
# 前四种签名稳定，系统「屏幕录制」授权会跟到同一个签名身份上，
# 重建 App 不会要求重新授权；ad-hoc 每次重建 cdhash 都变，授权必失效。
resolve_signing_identity() {
    if [[ -n "${AI_SCREENSHOT_SIGNING_IDENTITY:-}" ]]; then
        printf '%s' "${AI_SCREENSHOT_SIGNING_IDENTITY}"
        return
    fi

    local identities
    identities="$(security find-identity -v -p codesigning 2>/dev/null \
        | sed -n 's/.*"\(.*\)"$/\1/p')"
    [[ -n "$identities" ]] || return 0

    local kind hit
    for kind in "Developer ID Application:" "Apple Development:"; do
        hit="$(printf '%s\n' "$identities" | grep -F "$kind" 2>/dev/null | head -n 1)" || true
        if [[ -n "$hit" ]]; then
            printf '%s' "$hit"
            return 0
        fi
    done

    printf '%s' "$(printf '%s\n' "$identities" | head -n 1)"
    return 0
}

SIGNING_IDENTITY="$(resolve_signing_identity)"

if [[ -n "$SIGNING_IDENTITY" ]]; then
    echo "签名身份：$SIGNING_IDENTITY"
    echo "（签名稳定：重建 App 不需要重新授予屏幕录制权限）"
    codesign --force --deep --sign "$SIGNING_IDENTITY" "$APP_BUNDLE_DIR"
else
    echo "警告：没有找到可用的代码签名身份，本次使用 ad-hoc 签名。"
    echo "       ad-hoc 签名每次重建都会变，macOS 的屏幕录制授权会失效，需要重新授予。"
    echo "       想一次解决：在「钥匙串访问 → 证书助理 → 创建证书」建一个代码签名证书（代码签名 + 自签名），"
    echo "       或跳到 https://developer.apple.com 申请 Apple Development 证书。"
    codesign --force --deep --sign - "$APP_BUNDLE_DIR"
fi

codesign --verify --deep --strict "$APP_BUNDLE_DIR"

# 打印指定要求（designated requirement），签名是否稳定看这里：两次构建应完全一致。
if DESIGNATED_REQUIREMENT="$(codesign -d -r- "$APP_BUNDLE_DIR" 2>&1 | tail -n 1)"; then
    echo "designated requirement: $DESIGNATED_REQUIREMENT"
fi

echo "$APP_BUNDLE_DIR"
