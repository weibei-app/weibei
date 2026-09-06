#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
PACKAGE_ONLY=false
if [[ "$MODE" == "--package" || "$MODE" == "package" ]]; then
  MODE="package"
  PACKAGE_ONLY=true
fi
if [[ "$MODE" == "--verify" || "$MODE" == "verify" ]]; then
  MODE="verify"
  PACKAGE_ONLY=true
fi
CHECK_ONLY=false
if [[ "$MODE" == "--check" || "$MODE" == "check" ]]; then
  MODE="check"
  CHECK_ONLY=true
fi
PRODUCT_NAME="WeiBei"
APP_DISPLAY_NAME="魏碑"
BUNDLE_ID="com.changfenhuang.weibei"
MIN_SYSTEM_VERSION="14.0"
BUILD_CONFIGURATION="release"
if [[ "$MODE" == "check" || "$MODE" == "--debug" || "$MODE" == "debug" ]]; then
  BUILD_CONFIGURATION="debug"
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOST_ARCH="$(uname -m)"
TARGET_ARCH="${WEIBEI_TARGET_ARCH:-$HOST_ARCH}"
case "$TARGET_ARCH" in
  arm64|x86_64) ;;
  *)
    echo "build failed: WEIBEI_TARGET_ARCH must be arm64 or x86_64" >&2
    exit 32
    ;;
esac
if [[ "$HOST_ARCH" != "$TARGET_ARCH" ]]; then
  echo "build failed: native $TARGET_ARCH package requires a $TARGET_ARCH runner (host is $HOST_ARCH)" >&2
  exit 33
fi
VERSION_FILE="$ROOT_DIR/VERSION"
FINAL_DIST_DIR="$ROOT_DIR/dist"
FINAL_APP_BUNDLE="$FINAL_DIST_DIR/$APP_DISPLAY_NAME.app"
FINAL_APP_BINARY="$FINAL_APP_BUNDLE/Contents/MacOS/$PRODUCT_NAME"
# Always assemble + codesign outside the repo tree. Projects under ~/Documents
# (iCloud / File Provider) get com.apple.FinderInfo and related xattrs stamped
# onto the bundle; codesign then fails with "resource fork, Finder information,
# or similar detritus not allowed".
if [[ "$PACKAGE_ONLY" == true ]]; then
  DIST_DIR="${TMPDIR%/}/weibei-package-$UID"
else
  DIST_DIR="${TMPDIR%/}/weibei-run-$UID"
fi
APP_BUNDLE="$DIST_DIR/$APP_DISPLAY_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_FRAMEWORKS="$APP_CONTENTS/Frameworks"
APP_HELPERS="$APP_CONTENTS/Helpers"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_ICON_SOURCE="$ROOT_DIR/DesignSystem/assets/app-icon/AppIcon.icon"
APP_ICON_BUILD_DIR="$DIST_DIR/app-icon-resources"
APP_ICON_PARTIAL_PLIST="$APP_ICON_BUILD_DIR/partial.plist"
# Current pre-release packages ship only active legal notices. Future release
# plans such as Docs/releases/v1.0.0.md stay in the repo and are not packaged.
LEGAL_SOURCE_FILES=(
  "$ROOT_DIR/PRIVACY.md"
  "$ROOT_DIR/THIRD_PARTY_NOTICES.md"
  "$ROOT_DIR/ASSET_ATTRIBUTIONS.md"
)
APP_BINARY="$APP_MACOS/$PRODUCT_NAME"
FINAL_AUDIT_DIR="$DIST_DIR/final-audit"
FINAL_AUDIT_APP_BUNDLE="$FINAL_AUDIT_DIR/$APP_DISPLAY_NAME.app"
FINAL_AUDIT_APP_BINARY="$FINAL_AUDIT_APP_BUNDLE/Contents/MacOS/$PRODUCT_NAME"
PDF_TEXT_WORKER_NAME="WeiBeiPDFTextWorker"
PDF_TEXT_WORKER="$APP_HELPERS/$PDF_TEXT_WORKER_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
SPARKLE_TEST_PUBLIC_KEY="eRFPLZuNM6m8bltmtpPX4fzKbufI1z6rKJHtgIIsllk="
SPARKLE_PUBLIC_KEY="${WEIBEI_SPARKLE_PUBLIC_KEY:-$SPARKLE_TEST_PUBLIC_KEY}"
SPARKLE_FEED_URL="${WEIBEI_SPARKLE_FEED_URL:-https://github.com/WroughtMind/weibei/releases/latest/download/appcast-$TARGET_ARCH.xml}"

target_app_is_running() {
  local pid command target_binary="$APP_BINARY"
  if [[ "$PACKAGE_ONLY" == true ]]; then
    target_binary="$FINAL_APP_BINARY"
  fi
  while IFS= read -r pid; do
    [[ -n "$pid" ]] || continue
    command="$(ps -p "$pid" -o command= 2>/dev/null || true)"
    if [[ "$command" == "$target_binary" || "$command" == "$target_binary "* ]]; then
      return 0
    fi
  done < <(pgrep -x "$PRODUCT_NAME" 2>/dev/null || true)
  return 1
}

if [[ "$CHECK_ONLY" == true ]]; then
  :
elif [[ "$PACKAGE_ONLY" == true ]]; then
  if target_app_is_running; then
    echo "package blocked: $APP_DISPLAY_NAME is running; quit it first so dist can be replaced without touching the active window." >&2
    exit 6
  fi
else
  # 只退出本构建目录跑起来的实例,不碰 /Applications 等正式版;
  # SIGTERM 由 App 的信号处理同步落盘后退出。
  # staged 实例的特征是路径含专用目录名;/var 是 /private/var 的符号链接,
  # ps 返回归一化路径,不能用字面前缀比较,用子串匹配。
  staged_marker="weibei-run-$UID"
  for pid in $(pgrep -x "$PRODUCT_NAME"); do
    exe_path=$(ps -o comm= -p "$pid" 2>/dev/null)
    if [[ "$exe_path" == *"$staged_marker"* ]]; then
      kill -TERM "$pid" >/dev/null 2>&1 || true
    fi
  done
  # SIGTERM 后 App 同步落盘最长约 60 秒,等它退净再开新实例,避免新旧并存双写数据。
  for _ in {1..650}; do
    found=false
    for pid in $(pgrep -x "$PRODUCT_NAME"); do
      exe_path=$(ps -o comm= -p "$pid" 2>/dev/null)
      if [[ "$exe_path" == *"$staged_marker"* ]]; then
        found=true
        break
      fi
    done
    [[ "$found" == false ]] && break
    sleep 0.1
  done
fi

if [[ -d "$ROOT_DIR/node_modules" ]]; then
  npm run build:editor >/dev/null
elif [[ "$CHECK_ONLY" == true || "$PACKAGE_ONLY" == true ]]; then
  echo "build failed: run npm ci first" >&2
  exit 25
fi

if [[ "$CHECK_ONLY" != true ]]; then
  if [[ ! -f "$VERSION_FILE" ]]; then
    echo "build failed: missing VERSION" >&2
    exit 19
  fi
  APP_VERSION="$(/usr/bin/tr -d '\r\n' <"$VERSION_FILE")"
  if [[ ! "$APP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "build failed: VERSION must use numeric major.minor.patch" >&2
    exit 20
  fi
  if [[ "$(git -C "$ROOT_DIR" rev-parse --is-shallow-repository)" == "true" ]]; then
    echo "build failed: full Git history is required for a stable build number" >&2
    exit 21
  fi
  GIT_COMMIT="$(git -C "$ROOT_DIR" rev-parse --verify HEAD)"
  BUILD_NUMBER="$(git -C "$ROOT_DIR" rev-list --count "$GIT_COMMIT")"
  DSYM_NAME="$PRODUCT_NAME-$APP_VERSION-$TARGET_ARCH-build-$BUILD_NUMBER-$GIT_COMMIT.dSYM"
  DSYM_PATH="$FINAL_DIST_DIR/$DSYM_NAME"
  SOURCE_DIRTY=false
  if [[ -n "$(git -C "$ROOT_DIR" status --porcelain=v1 --untracked-files=normal)" ]]; then
    SOURCE_DIRTY=true
  fi
fi

# SwiftPM's generated lookup targets command-line layouts. The native libraries
# must also find their resource bundles in a signed macOS App's Contents/Resources.
swift package resolve
git apply --directory=.build/checkouts --check script/native-bundle-resources.patch 2>/dev/null && {
  git apply --directory=.build/checkouts script/native-bundle-resources.patch
} || git apply --directory=.build/checkouts --reverse --check script/native-bundle-resources.patch

swift build -c "$BUILD_CONFIGURATION"

if [[ "$CHECK_ONLY" != true ]]; then
  BUILD_DIR="$(swift build -c "$BUILD_CONFIGURATION" --show-bin-path)"
  BUILD_BINARY="$BUILD_DIR/$PRODUCT_NAME"
  RESOURCE_BUNDLES=(
    "$BUILD_DIR/${PRODUCT_NAME}_${PRODUCT_NAME}.bundle"
    "$BUILD_DIR/${PRODUCT_NAME}_WeiBeiCore.bundle"
    "$BUILD_DIR/SwiftMath_SwiftMath.bundle"
  )

  rm -rf "$APP_BUNDLE"
  mkdir -p "$APP_MACOS" "$APP_FRAMEWORKS" "$APP_HELPERS" "$APP_RESOURCES"
  if [[ ! -d "$APP_ICON_SOURCE" ]]; then
    echo "package failed: missing App Icon at $APP_ICON_SOURCE" >&2
    exit 22
  fi
  rm -rf "$APP_ICON_BUILD_DIR"
  mkdir -p "$APP_ICON_BUILD_DIR"
  xcrun actool \
    --compile "$APP_ICON_BUILD_DIR" \
    --platform macosx \
    --minimum-deployment-target "$MIN_SYSTEM_VERSION" \
    --target-device mac \
    --app-icon AppIcon \
    --output-partial-info-plist "$APP_ICON_PARTIAL_PLIST" \
    --standalone-icon-behavior all \
    "$APP_ICON_SOURCE" >/dev/null
  if [[ "$(head -c 8 "$APP_ICON_BUILD_DIR/Assets.car")" != "BOMStore" ]] || \
     [[ "$(head -c 4 "$APP_ICON_BUILD_DIR/AppIcon.icns")" != "icns" ]] || \
     [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconName' "$APP_ICON_PARTIAL_PLIST")" != "AppIcon" ]]; then
    echo "package failed: Xcode did not compile the macOS 27 App Icon resources" >&2
    exit 22
  fi
  cp "$BUILD_BINARY" "$APP_BINARY"
  if ! /usr/bin/cmp -s "$BUILD_BINARY" "$APP_BINARY"; then
    echo "package failed: copied app binary does not match the current Swift build" >&2
    exit 10
  fi
  chmod +x "$APP_BINARY"
  BUILD_UUID="$(/usr/bin/dwarfdump --uuid "$BUILD_BINARY" | /usr/bin/awk 'NR == 1 {print $2}')"
  if [[ "$PACKAGE_ONLY" == true ]]; then
    mkdir -p "$FINAL_DIST_DIR"
    rm -rf "$DSYM_PATH"
    /usr/bin/dsymutil "$BUILD_BINARY" -o "$DSYM_PATH"
    if [[ ! -d "$DSYM_PATH" || ! -s "$DSYM_PATH/Contents/Resources/DWARF/$PRODUCT_NAME" ]]; then
      echo "package failed: dSYM is missing usable DWARF data at $DSYM_PATH" >&2
      exit 28
    fi
    DSYM_UUID="$(/usr/bin/dwarfdump --uuid "$DSYM_PATH" | /usr/bin/awk 'NR == 1 {print $2}')"
    if [[ -z "$BUILD_UUID" || "$DSYM_UUID" != "$BUILD_UUID" ]]; then
      echo "package failed: dSYM UUID does not match the unstripped build binary" >&2
      exit 29
    fi
    PRE_STRIP_BYTES="$(/usr/bin/stat -f '%z' "$APP_BINARY")"
    /usr/bin/strip -x "$APP_BINARY"
    POST_STRIP_BYTES="$(/usr/bin/stat -f '%z' "$APP_BINARY")"
    if (( POST_STRIP_BYTES >= PRE_STRIP_BYTES )); then
      echo "package failed: strip -x did not reduce the app binary" >&2
      exit 30
    fi
    STRIPPED_UUID="$(/usr/bin/dwarfdump --uuid "$APP_BINARY" | /usr/bin/awk 'NR == 1 {print $2}')"
    if [[ "$STRIPPED_UUID" != "$BUILD_UUID" ]]; then
      echo "package failed: strip -x changed the app binary UUID" >&2
      exit 31
    fi
  fi
  SPARKLE_FRAMEWORK="$BUILD_DIR/Sparkle.framework"
  if [[ ! -d "$SPARKLE_FRAMEWORK" ]]; then
    echo "package failed: missing Sparkle.framework" >&2
    exit 26
  fi
  /usr/bin/ditto --norsrc --noextattr "$SPARKLE_FRAMEWORK" "$APP_FRAMEWORKS/Sparkle.framework"
  /usr/bin/install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_BINARY"
  BUILD_PDF_TEXT_WORKER="$BUILD_DIR/$PDF_TEXT_WORKER_NAME"
  if [[ ! -x "$BUILD_PDF_TEXT_WORKER" ]]; then
    echo "package failed: missing bounded PDF text worker" >&2
    exit 12
  fi
  cp "$BUILD_PDF_TEXT_WORKER" "$PDF_TEXT_WORKER"
  if ! /usr/bin/cmp -s "$BUILD_PDF_TEXT_WORKER" "$PDF_TEXT_WORKER"; then
    echo "package failed: copied PDF text worker does not match the current Swift build" >&2
    exit 13
  fi
  chmod +x "$PDF_TEXT_WORKER"
  for resource_bundle in "${RESOURCE_BUNDLES[@]}"; do
    if [[ ! -d "$resource_bundle" ]]; then
      echo "package failed: missing resource bundle $resource_bundle" >&2
      exit 7
    fi
    cp -R "$resource_bundle" "$APP_RESOURCES/"
  done
  cp "$APP_ICON_BUILD_DIR/Assets.car" "$APP_RESOURCES/Assets.car"
  cp "$APP_ICON_BUILD_DIR/AppIcon.icns" "$APP_RESOURCES/AppIcon.icns"
  mkdir -p "$APP_RESOURCES/Legal"
  for legal_source in "${LEGAL_SOURCE_FILES[@]}"; do
    if [[ ! -f "$legal_source" ]]; then
      echo "package failed: missing legal/release notice $legal_source" >&2
      exit 24
    fi
    cp "$legal_source" "$APP_RESOURCES/Legal/$(basename "$legal_source")"
  done
  # SwiftPM dependencies can carry read-only resource modes into this copy.
  chmod -R u+w "$APP_RESOURCES"
  # Native chat uses only Latin Modern; keep its complete font/table and all licenses.
  /usr/bin/find "$APP_RESOURCES/SwiftMath_SwiftMath.bundle/mathFonts.bundle" -type f \
    \( -name '*.otf' -o -name '*.plist' -o -name 'math_table_to_plist.py' \) \
    ! -name 'latinmodern-math.otf' ! -name 'latinmodern-math.plist' -delete
  # Clear inherited provenance/quarantine metadata before first launch.
  # Downloaded DMGs receive a fresh quarantine marker on the user's Mac.
  /usr/bin/xattr -cr "$APP_BUNDLE"

  cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$PRODUCT_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_DISPLAY_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_DISPLAY_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIconName</key>
  <string>AppIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>WeiBeiGitCommit</key>
  <string>$GIT_COMMIT</string>
  <key>WeiBeiArchitecture</key>
  <string>$TARGET_ARCH</string>
  <key>WeiBeiSourceDirty</key>
  <$SOURCE_DIRTY/>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>SUFeedURL</key>
  <string>$SPARKLE_FEED_URL</string>
  <key>SUPublicEDKey</key>
  <string>$SPARKLE_PUBLIC_KEY</string>
  <key>SUEnableAutomaticChecks</key>
  <true/>
  <key>SUAutomaticallyUpdate</key>
  <false/>
  <key>SUEnableSystemProfiling</key>
  <false/>
  <key>SURequireSignedFeed</key>
  <true/>
  <key>SUVerifyUpdateBeforeExtraction</key>
  <true/>
  <key>SUScheduledCheckInterval</key>
  <integer>3600</integer>
</dict>
</plist>
PLIST
  if [[ "$(/usr/bin/printf '%s' "$SPARKLE_PUBLIC_KEY" | /usr/bin/base64 -D 2>/dev/null | /usr/bin/wc -c | /usr/bin/tr -d ' ')" != "32" ]]; then
    echo "package failed: WEIBEI_SPARKLE_PUBLIC_KEY must be a base64-encoded 32-byte Ed25519 public key" >&2
    exit 27
  fi
  /usr/bin/codesign --force --deep --sign - --timestamp=none "$APP_FRAMEWORKS/Sparkle.framework" >/dev/null
  /usr/bin/codesign --force --sign - --timestamp=none "$PDF_TEXT_WORKER" >/dev/null
  /usr/bin/codesign --force --sign - --timestamp=none "$APP_BUNDLE" >/dev/null
  if ! /usr/bin/codesign --verify --deep --strict "$APP_BUNDLE" >/dev/null; then
    echo "package failed: staged app signature is invalid at $APP_BUNDLE" >&2
    /usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE" 2>&1 | tail -20 >&2 || true
    exit 19
  fi
  PACKAGED_UUID="$(/usr/bin/dwarfdump --uuid "$APP_BINARY" | /usr/bin/awk 'NR == 1 {print $2}')"
  if [[ -z "$BUILD_UUID" || "$PACKAGED_UUID" != "$BUILD_UUID" ]]; then
    echo "package failed: signed app binary UUID does not match the current Swift build" >&2
    exit 11
  fi
  # Mirror a clean copy into repo dist/ for inspection. Launch always uses the
  # staged /tmp bundle (valid signature); Documents copies can re-acquire
  # File Provider xattrs that invalidate codesign verification.
  rm -rf "$FINAL_APP_BUNDLE"
  mkdir -p "$FINAL_DIST_DIR"
  /usr/bin/ditto --norsrc --noextattr "$APP_BUNDLE" "$FINAL_APP_BUNDLE"
  /usr/bin/xattr -cr "$FINAL_APP_BUNDLE" 2>/dev/null || true
  if ! /usr/bin/cmp -s "$APP_BINARY" "$FINAL_APP_BINARY"; then
    echo "package failed: final app binary changed while copying from signed staging" >&2
    exit 15
  fi
  if [[ "$PACKAGE_ONLY" == true ]]; then
    if ! /usr/bin/codesign --verify --deep "$FINAL_APP_BUNDLE" >/dev/null 2>&1; then
      # Documents may stamp FinderInfo onto the published copy; re-seal in place
      # after stripping attrs so release consumers still get a verifiable dist/.
      /usr/bin/xattr -cr "$FINAL_APP_BUNDLE" 2>/dev/null || true
      /usr/bin/codesign --force --deep --sign - --timestamp=none "$FINAL_APP_BUNDLE/Contents/Frameworks/Sparkle.framework" >/dev/null 2>&1 || true
      /usr/bin/codesign --force --sign - --timestamp=none "$FINAL_APP_BUNDLE/Contents/Helpers/$PDF_TEXT_WORKER_NAME" >/dev/null 2>&1 || true
      /usr/bin/codesign --force --sign - --timestamp=none "$FINAL_APP_BUNDLE" >/dev/null
    fi
    /usr/bin/codesign --verify --deep "$FINAL_APP_BUNDLE"
    FINAL_UUID="$(/usr/bin/dwarfdump --uuid "$FINAL_APP_BINARY" | /usr/bin/awk 'NR == 1 {print $2}')"
    if [[ -z "$FINAL_UUID" || "$FINAL_UUID" != "$PACKAGED_UUID" ]]; then
      echo "package failed: final app binary UUID changed while copying from signed staging" >&2
      exit 16
    fi
    rm -rf "$FINAL_AUDIT_DIR"
    mkdir -p "$FINAL_AUDIT_DIR"
    /usr/bin/ditto --norsrc --noextattr "$FINAL_APP_BUNDLE" "$FINAL_AUDIT_APP_BUNDLE"
    /usr/bin/xattr -cr "$FINAL_AUDIT_APP_BUNDLE"
    /usr/bin/codesign --verify --deep --strict "$FINAL_AUDIT_APP_BUNDLE"
    if ! /usr/bin/cmp -s "$FINAL_APP_BINARY" "$FINAL_AUDIT_APP_BINARY"; then
      echo "package failed: strict-audit copy changed the final app binary" >&2
      exit 17
    fi
    AUDITED_UUID="$(/usr/bin/dwarfdump --uuid "$FINAL_AUDIT_APP_BINARY" | /usr/bin/awk 'NR == 1 {print $2}')"
    if [[ -z "$AUDITED_UUID" || "$AUDITED_UUID" != "$FINAL_UUID" ]]; then
      echo "package failed: strict-audit copy changed the final app binary UUID" >&2
      exit 18
    fi
    (cd "$ROOT_DIR" && swift run WeiBeiDev verify-release-metadata "$FINAL_APP_BUNDLE")
    (cd "$ROOT_DIR" && swift run WeiBeiDev verify-release-architecture "$TARGET_ARCH" "$FINAL_APP_BUNDLE")
    (cd "$ROOT_DIR" && swift run WeiBeiDev verify-production-hygiene "$FINAL_APP_BUNDLE")
  fi
fi

open_app() {
  # Launch the staged, validly signed bundle — not dist/ under Documents.
  if ! /usr/bin/codesign --verify --deep --strict "$APP_BUNDLE" >/dev/null 2>&1; then
    echo "open blocked: staged app signature invalid at $APP_BUNDLE" >&2
    exit 20
  fi
  /usr/bin/open "$APP_BUNDLE"
}

run_verifiers() {
  swift run -c "$BUILD_CONFIGURATION" WeiBeiSelfCheck
  swift test -c "$BUILD_CONFIGURATION" --filter WeiBeiSafetyTests
  swift run -c "$BUILD_CONFIGURATION" WeiBeiWebEditorCheck
  swift run -c "$BUILD_CONFIGURATION" WeiBeiNativeCheck --authentication-status
}

verify_launch() {
  local pid="" exe_path="" staged_marker="weibei-package-$UID"
  open_app
  for _ in {1..120}; do
    while IFS= read -r candidate; do
      [[ -n "$candidate" ]] || continue
      exe_path="$(ps -p "$candidate" -o comm= 2>/dev/null || true)"
      if [[ "$exe_path" == *"$staged_marker"* ]]; then
        pid="$candidate"
        break 2
      fi
    done < <(pgrep -x "$PRODUCT_NAME" 2>/dev/null || true)
    sleep 0.25
  done
  if [[ -z "$pid" ]]; then
    echo "verify failed: packaged app did not stay running after launch" >&2
    exit 34
  fi
  kill -TERM "$pid" 2>/dev/null || true
  for _ in {1..260}; do
    if ! kill -0 "$pid" 2>/dev/null; then
      echo "verify_launch=passed"
      return 0
    fi
    sleep 0.25
  done
  echo "verify failed: packaged app did not exit after SIGTERM" >&2
  exit 35
}

case "$MODE" in
  check)
    run_verifiers
    ;;
  package)
    ;;
  verify)
    verify_launch
    ;;
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$PRODUCT_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  *)
    echo "usage: $0 [run|check|package|verify|--debug|--logs|--telemetry]" >&2
    exit 2
    ;;
esac
