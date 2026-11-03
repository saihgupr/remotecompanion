#!/bin/bash
set -e

# Configuration
IP="${RC_IPHONE_IP:-192.168.1.2}"
SSH_OPTS="-o ConnectTimeout=5 -o StrictHostKeyChecking=no"
SSH_CMD="ssh $SSH_OPTS mobile@$IP"
REMOTE_PATH="export PATH=/var/jb/usr/local/bin:/var/jb/usr/bin:/usr/local/bin:/usr/bin:/bin"

# Help
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    echo "RemoteCompanion Studio Screenshot Capture"
    echo "Usage: ./tools/capture_screen.sh [screen] [output_path]"
    echo ""
    echo "Available screens:"
    echo "  triggers       - Main Triggers dashboard"
    echo "  add            - Add Trigger menu (NFC, WiFi, BT, Apps, etc.)"
    echo "  settings       - Main Settings panel"
    echo "  integrations   - Integrations hub"
    echo "  ha             - Home Assistant integration settings"
    echo "  km             - Keyboard Maestro settings"
    echo "  mqtt           - MQTT settings"
    echo "  advanced       - Advanced settings"
    echo "  testkit        - TestKit diagnostics"
    echo "  webui          - WebUI access settings"
    echo "  --suite        - Capture full showcase release suite"
    echo ""
    exit 0
fi

capture_panel() {
    local panel="$1"
    local output="$2"
    
    echo "📸 Capturing '$panel'..."
    
    # 1. Ensure phone is unlocked
    local is_locked=$($SSH_CMD "$REMOTE_PATH; rc is-locked 2>/dev/null || true" | tr -d '\r\n')
    if [[ "$is_locked" == *"Locked"* || "$is_locked" == *"locked"* ]]; then
        echo "🔓 Unlocking device..."
        $SSH_CMD "$REMOTE_PATH; rc unlock" >/dev/null 2>&1 || true
        sleep 1
    fi
    
    # 2. Navigate to screen
    echo "🧭 Navigating to '$panel'..."
    $SSH_CMD "$REMOTE_PATH; rc nav '$panel'" >/dev/null 2>&1
    sleep 2
    
    # 3. Take screenshot & stream PNG back to Mac
    echo "📷 Snapping screenshot..."
    mkdir -p "$(dirname "$output")"
    $SSH_CMD "$REMOTE_PATH; rc screenshot >/dev/null && sleep 4 && cat \"\$(ls -t /var/mobile/Media/DCIM/*APPLE/*.PNG 2>/dev/null | head -n 1)\"" > "$output"
    
    if [ -s "$output" ]; then
        echo "✅ Saved to: $output ($(du -h "$output" | cut -f1))"
    else
        echo "❌ Capture failed or empty file: $output"
        rm -f "$output"
        return 1
    fi
}

mkdir -p images/screenshots

if [[ "$1" == "--suite" || "$1" == "--all" ]]; then
    echo "🌟 Starting full showcase release suite capture..."
    capture_panel "triggers" "images/screenshots/01_main_interface.png"
    capture_panel "add" "images/screenshots/02_add_trigger.png"
    capture_panel "trigger?key=volume_up_then_down" "images/screenshots/03_action_conditions.png"
    capture_panel "settings" "images/screenshots/04_settings.png"
    capture_panel "ha" "images/screenshots/05_home_assistant.png"
    echo "🎉 Showcase suite capture complete! Files saved in images/screenshots/"
    exit 0
fi

PANEL="${1:-triggers}"
if [[ "$PANEL" == "actions" || "$PANEL" == "conditions" ]]; then
    PANEL="trigger?key=volume_up_then_down"
fi
OUTPUT="${2:-images/screenshots/${1:-triggers}.png}"

capture_panel "$PANEL" "$OUTPUT"

