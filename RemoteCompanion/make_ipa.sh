#!/bin/bash
set -e

# Create IPA from companion app for TrollStore installation

APP_NAME="RemoteCompanion"
IPA_NAME="RemoteCompanion.ipa"
BUILD_DIR=".theos/obj/debug/arm64/$APP_NAME.app"

# Find the binary in the staging area (handles rootless/rootful differences)
STAGING_BUNDLE=$(find .theos/_ -name "$APP_NAME.app" -type d | head -n 1)

if [ -z "$STAGING_BUNDLE" ]; then
    echo "⚠️ Warning: Staging bundle not found. Using raw build artifacts and signing manually..."
    if [ ! -d "$BUILD_DIR" ]; then
        echo "❌ Error: Build directory $BUILD_DIR not found. Run 'make' first."
        exit 1
    fi
    STAGING_BUNDLE="$BUILD_DIR"
    # Sign it manually since we are using raw build artifact
    echo "🖋 Signing binary with ldid..."
    ldid -SEntitlements.plist "$STAGING_BUNDLE/$APP_NAME"
fi

echo "📦 Creating IPA using bundle: $STAGING_BUNDLE"

# Create temp Payload directory
rm -rf /tmp/Payload
mkdir -p /tmp/Payload/$APP_NAME.app

# Copy the entire bundle content
cp -R "$STAGING_BUNDLE/"* /tmp/Payload/$APP_NAME.app/

# Create IPA
CUR_DIR=$(pwd)
cd /tmp
rm -f $IPA_NAME
zip -r $IPA_NAME Payload > /dev/null
mv $IPA_NAME "$CUR_DIR/$IPA_NAME"
cd - > /dev/null

rm -rf /tmp/Payload

echo "✅ Created $IPA_NAME"
echo ""
echo "Install it with TrollStore (open the IPA on the device, or use TrollStore's Install IPA)."
