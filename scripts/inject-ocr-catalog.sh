#!/bin/zsh
# 给已组装好的 .app 注入 OCR 增强包清单配置。
#
# 用法：scripts/inject-ocr-catalog.sh <APP_BUNDLE_DIR> [PROJECT_ROOT]
#
# 为什么要抽成脚本：`scripts/build-app.sh`（本机构建）和 `.github/workflows/build-macos.yml`
# （CI 出包）是两条独立的组装路径，逻辑只写在其中一条里就会出现「本机有、CI 没有」的偏差
# —— 曾经就这样导致 CI 产物的 TaOCRCatalogURL 是空的。
#
# 环境变量：
#   TA_OCR_CATALOG_URL            远端清单地址（必须是 https）；空则不动 Info.plist
#   TA_OCR_BUNDLE_LOCAL_CATALOG=1 是否把 <PROJECT_ROOT>/artifacts/ocr-packs/catalog.json 打进包体
#
# 刻意不读 UserDefaults：`ocrPackCatalogURL` 那个设置项任何本地程序都能用 defaults write
# 改写，能把下载源指到攻击者服务器，等于以用户权限执行任意代码。这里改成构建期写进
# Info.plist —— 改它需要重签名。
set -euo pipefail

APP_BUNDLE_DIR="${1:?用法: inject-ocr-catalog.sh <APP_BUNDLE_DIR> [PROJECT_ROOT]}"
PROJECT_ROOT="${2:-${0:A:h:h}}"
PLIST="$APP_BUNDLE_DIR/Contents/Info.plist"

[[ -f "$PLIST" ]] || { echo "找不到 Info.plist：$PLIST" >&2; exit 1; }

OCR_CATALOG_LOCAL="$PROJECT_ROOT/artifacts/ocr-packs/catalog.json"
if [[ "${TA_OCR_BUNDLE_LOCAL_CATALOG:-0}" == "1" && -f "$OCR_CATALOG_LOCAL" ]]; then
    mkdir -p "$APP_BUNDLE_DIR/Contents/Resources/OCRPacks"
    cp "$OCR_CATALOG_LOCAL" "$APP_BUNDLE_DIR/Contents/Resources/OCRPacks/catalog.json"
    echo "已内置本地增强包清单：$OCR_CATALOG_LOCAL"
fi

OCR_CATALOG_URL="${TA_OCR_CATALOG_URL:-}"
if [[ -n "$OCR_CATALOG_URL" ]]; then
    case "$OCR_CATALOG_URL" in
        https://*) ;;
        *) echo "TA_OCR_CATALOG_URL 必须是 https 地址：$OCR_CATALOG_URL" >&2; exit 1 ;;
    esac
    /usr/libexec/PlistBuddy -c "Set :TaOCRCatalogURL $OCR_CATALOG_URL" "$PLIST"
    echo "已烘入远端增强包清单：$OCR_CATALOG_URL"
elif [[ -z "$( /usr/libexec/PlistBuddy -c 'Print :TaOCRCatalogURL' "$PLIST" 2>/dev/null )" && ! -f "$APP_BUNDLE_DIR/Contents/Resources/OCRPacks/catalog.json" ]]; then
    if [[ -f "$OCR_CATALOG_LOCAL" ]]; then
        echo "提示：检测到 artifacts/ocr-packs/catalog.json，但未内置（默认关闭）。"
        echo "      本地分发只需把 catalog.json 与压缩包放到 .app 同级的 ocr-packs/ 目录。"
    else
        echo "提示：未设置 TA_OCR_CATALOG_URL 且没有本地 catalog —— 「下载增强包」会提示清单缺失。"
    fi
fi