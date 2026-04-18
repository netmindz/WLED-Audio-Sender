#!/bin/bash
# muvm-flutter.sh - Run Flutter commands inside muvm (4K page size VM)
# Required on aarch64 systems with 16K page size kernels where Flutter won't run natively.
#
# Usage:
#   ./muvm-flutter.sh test                  # run flutter test
#   ./muvm-flutter.sh build apk --debug     # run flutter build
#   ./muvm-flutter.sh pub get               # run flutter pub get
#   ./muvm-flutter.sh <any flutter args>    # pass-through to flutter

set -euo pipefail

FLUTTER_DIR="$HOME/.local/share/flutter"
FLUTTER_BIN="$FLUTTER_DIR/bin/flutter"
FLUTTER_VERSION="3.27.4"
LOG_FILE="/tmp/muvm-flutter-output.txt"
DONE_FILE="/tmp/muvm-flutter-done"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Ensure we have arguments
if [ $# -eq 0 ]; then
    echo "Usage: $0 <flutter command> [args...]"
    echo "Example: $0 test"
    echo "         $0 build apk --debug"
    echo "         $0 pub get"
    exit 1
fi

FLUTTER_ARGS="$*"

# Clean up from previous run
rm -f "$LOG_FILE" "$DONE_FILE"

echo "Running 'flutter $FLUTTER_ARGS' inside muvm..."

# Build the script to run inside muvm
INNER_SCRIPT=$(cat <<'INNEREOF'
#!/bin/bash
set -euo pipefail

FLUTTER_DIR="$HOME/.local/share/flutter"
FLUTTER_BIN="$FLUTTER_DIR/bin/flutter"
FLUTTER_VERSION="__FLUTTER_VERSION__"
LOG_FILE="__LOG_FILE__"
DONE_FILE="__DONE_FILE__"
PROJECT_DIR="__PROJECT_DIR__"

# Use tee so output goes to both the log file and stdout (visible in real-time)
exec > >(tee "$LOG_FILE") 2>&1

# Install Flutter if not present or wrong version
install_flutter() {
    if [ -x "$FLUTTER_BIN" ]; then
        CURRENT=$("$FLUTTER_BIN" --version 2>/dev/null | head -1 | grep -oP '[\d]+\.[\d]+\.[\d]+' || echo "unknown")
        if [ "$CURRENT" = "$FLUTTER_VERSION" ]; then
            echo "Flutter $FLUTTER_VERSION already installed."
            return 0
        fi
        echo "Flutter version mismatch ($CURRENT != $FLUTTER_VERSION), reinstalling..."
        rm -rf "$FLUTTER_DIR"
    fi

    echo "Installing Flutter $FLUTTER_VERSION..."
    mkdir -p "$(dirname "$FLUTTER_DIR")"
    
    ARCH=$(uname -m)
    if [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
        FLUTTER_ARCH="arm64"
    else
        FLUTTER_ARCH="x64"
    fi
    
    URL="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"
    echo "Downloading from $URL ..."
    
    curl -fSL "$URL" | tar xJ -C "$(dirname "$FLUTTER_DIR")"
    
    echo "Flutter installed successfully."
}

install_flutter

# Disable analytics to avoid prompts
"$FLUTTER_BIN" config --no-analytics 2>/dev/null || true
"$FLUTTER_BIN" --disable-telemetry 2>/dev/null || true

# Run the requested command
cd "$PROJECT_DIR"
echo ""
echo "=== flutter __FLUTTER_ARGS__ ==="
echo ""
"$FLUTTER_BIN" __FLUTTER_ARGS__
EXIT_CODE=$?
echo ""
echo "=== Exit code: $EXIT_CODE ==="
echo "$EXIT_CODE" > "$DONE_FILE"
INNEREOF
)

# Substitute variables into the inner script
INNER_SCRIPT="${INNER_SCRIPT//__FLUTTER_VERSION__/$FLUTTER_VERSION}"
INNER_SCRIPT="${INNER_SCRIPT//__LOG_FILE__/$LOG_FILE}"
INNER_SCRIPT="${INNER_SCRIPT//__DONE_FILE__/$DONE_FILE}"
INNER_SCRIPT="${INNER_SCRIPT//__PROJECT_DIR__/$PROJECT_DIR}"
INNER_SCRIPT="${INNER_SCRIPT//__FLUTTER_ARGS__/$FLUTTER_ARGS}"

# Write the inner script
INNER_SCRIPT_FILE="/tmp/muvm-flutter-inner.sh"
echo "$INNER_SCRIPT" > "$INNER_SCRIPT_FILE"
chmod +x "$INNER_SCRIPT_FILE"

# Launch inside muvm
# Note: muvm dispatches to a VM daemon and exits immediately,
# so we cannot rely on its PID to track completion. Instead we
# poll for the done file written by the inner script.
muvm -- bash "$INNER_SCRIPT_FILE"

# Wait for the log file to appear
echo "Waiting for muvm to start..."
for i in $(seq 1 30); do
    if [ -f "$LOG_FILE" ]; then
        break
    fi
    sleep 1
done

if [ ! -f "$LOG_FILE" ]; then
    echo "ERROR: muvm did not produce output after 30s. Check muvm setup."
    exit 1
fi

# Stream log output in real-time using tail -f, so the user can see progress
tail -f "$LOG_FILE" &
TAIL_PID=$!

# Wait for the done file to appear (signals the inner script finished)
TIMEOUT=600  # 10 minute timeout (Flutter install can be slow)
for i in $(seq 1 $TIMEOUT); do
    if [ -f "$DONE_FILE" ]; then
        sleep 1  # Let tail catch up
        kill $TAIL_PID 2>/dev/null || true
        EXIT_CODE=$(cat "$DONE_FILE")
        rm -f "$INNER_SCRIPT_FILE" "$DONE_FILE"
        exit "${EXIT_CODE:-1}"
    fi
    sleep 1
done

kill $TAIL_PID 2>/dev/null || true
echo "ERROR: Timed out after ${TIMEOUT}s"
rm -f "$INNER_SCRIPT_FILE" "$DONE_FILE"
exit 1
