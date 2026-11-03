#!/bin/bash
set -e

# ==============================================================================
# RemoteCompanion - Build Script
# Builds the companion application and packages the unified tweak for iOS.
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Defaults
THEOS="${THEOS:-/opt/theos}"
SCHEME="rootless"
BUILD_ALL=false
CLEAN=false

# Determine safe Make command and parallel flags
MAKE_CMD="make"
MAKE_FLAGS=""
if command -v gmake >/dev/null 2>&1; then
    MAKE_CMD="gmake"
    NCPU=$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)
    MAKE_FLAGS="-j$NCPU"
else
    # Stock Apple make is GNU Make 3.81 which deadlocks with -j in Theos subprojects
    MAKE_VER=$(make -v 2>/dev/null | head -n1 | grep -oE '[0-9]+\.[0-9]+' | head -n1 || echo "3.81")
    MAJOR_VER=$(echo "$MAKE_VER" | cut -d. -f1)
    if [ "$MAJOR_VER" -ge 4 ] 2>/dev/null; then
        NCPU=$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)
        MAKE_FLAGS="-j$NCPU"
    fi
fi

# Usage help
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --rootless    Build rootless package (default, iOS 15+ Dopamine / Palera1n)"
    echo "  --rootful     Build rootful package (iOS 14 / unc0ver / Taurine)"
    echo "  --roothide    Build roothide package"
    echo "  --all         Build all package schemes (rootless, rootful, roothide)"
    echo "  --clean       Clean build artifacts before building"
    echo "  -h, --help    Show this help message"
    exit 0
}

# Parse arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --rootless) SCHEME="rootless" ;;
        --rootful)  SCHEME="rootful" ;;
        --roothide) SCHEME="roothide" ;;
        --all)      BUILD_ALL=true ;;
        --clean)    CLEAN=true ;;
        -h|--help)  usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
    shift
done

echo "🚀 Building RemoteCompanion Unified Package..."

# 1. Clean if requested
if [ "$CLEAN" = true ]; then
    echo "🧹 Cleaning previous build artifacts..."
    rm -rf Tweak/.theos RemoteCompanion/.theos
    rm -rf Tweak/layout/Applications/*
    rm -rf Tweak/layout/usr/bin/*
fi

# 2. Sync version between control and Info.plist
VERSION=$(grep "^Version:" Tweak/control | awk '{print $2}')
echo "🔄 Target Version: $VERSION"

if command -v /usr/libexec/PlistBuddy >/dev/null 2>&1; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" RemoteCompanion/Info.plist 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" RemoteCompanion/Info.plist 2>/dev/null || true
fi

# 3. Build Companion App (Stage Only)
echo "🏗️  Building RemoteCompanion App (make stage)..."
(cd RemoteCompanion && $MAKE_CMD stage $MAKE_FLAGS)

# 4. Prepare Layout for Tweak
echo "📂 Bundling App, CLI tool, and Web UI into Tweak Package..."
mkdir -p Tweak/layout/Applications
mkdir -p Tweak/layout/usr/bin
mkdir -p "Tweak/layout/Library/Application Support/RemoteCompanion"

# Copy staged .app wrapper
cp -r RemoteCompanion/.theos/_/Applications/RemoteCompanion.app Tweak/layout/Applications/

# Copy CLI script
cp rc Tweak/layout/usr/bin/
chmod +x Tweak/layout/usr/bin/rc

# Copy Web UI & favicons
cp rc_webui.html "Tweak/layout/Library/Application Support/RemoteCompanion/"
if [ -d favicons ]; then
    cp favicons/* "Tweak/layout/Library/Application Support/RemoteCompanion/"
fi

# 5. Build Tweak Package(s)
build_scheme() {
    local target_scheme="$1"
    echo "🏗️  Building Tweak Package ($target_scheme)..."
    if [ "$target_scheme" = "rootless" ]; then
        (cd Tweak && $MAKE_CMD package THEOS_PACKAGE_SCHEME=rootless $MAKE_FLAGS)
    elif [ "$target_scheme" = "rootful" ]; then
        # Swap architecture to rootful
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' 's/Architecture: iphoneos-arm64/Architecture: iphoneos-arm/' Tweak/control
        else
            sed -i 's/Architecture: iphoneos-arm64/Architecture: iphoneos-arm/' Tweak/control
        fi

        (cd Tweak && $MAKE_CMD package THEOS_PACKAGE_SCHEME= $MAKE_FLAGS)

        # Restore architecture to rootless
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' 's/Architecture: iphoneos-arm/Architecture: iphoneos-arm64/' Tweak/control
        else
            sed -i 's/Architecture: iphoneos-arm/Architecture: iphoneos-arm64/' Tweak/control
        fi
    elif [ "$target_scheme" = "roothide" ]; then
        (cd Tweak && $MAKE_CMD package THEOS_PACKAGE_SCHEME=roothide $MAKE_FLAGS) || echo "⚠️ Roothide build failed (roothide support missing in Theos?), skipping..."
    fi
}

if [ "$BUILD_ALL" = true ]; then
    build_scheme "rootless"
    build_scheme "rootful"
    build_scheme "roothide"
else
    build_scheme "$SCHEME"
fi

# Every dylib and helper tool must retain an arm64 slice for A11 and older
# devices, alongside the arm64e slice for A12+ devices.
verify_arch() {
    echo "🔎 Verifying arch slices..."
    local bad=0 f archs
    while IFS= read -r f; do
        case "$f" in */RemoteCompanion.app/RemoteCompanion|*/rc-root) continue;; esac
        archs=$(lipo -archs "$f" 2>/dev/null) || continue
        case " $archs " in
            *" arm64 "*) ;;
            *) echo "❌ ${f#Tweak/.theos/_/} has no arm64 slice (A11 and older support lost)"; bad=1 ;;
        esac
    done < <(find Tweak/.theos/_ -type f \( -name "*.dylib" -o -name "rc-client" \))
    [ "$bad" -eq 0 ] || exit 1
}

verify_arch

echo ""
echo "✅ Build Complete! Packages are located in Tweak/packages/:"
ls -lh Tweak/packages/*"${VERSION}"*.deb 2>/dev/null || ls -lh Tweak/packages/*.deb 2>/dev/null || echo "No .deb files found in Tweak/packages/"
