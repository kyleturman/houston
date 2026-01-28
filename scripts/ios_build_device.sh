#!/bin/bash

# iOS Device Build & Deploy Script
# Builds and deploys the iOS app to a physical device
# Usage: ./scripts/ios_build_device.sh [--verbose] [--clean] [--device "Device Name"]

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
IOS_PROJECT_PATH="ios/Houston.xcodeproj"
SCHEME_NAME="Houston"
BUILD_DIR="ios/build"
VERBOSE=false
CLEAN_BUILD=false
DEVICE_NAME=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --clean|-c)
            CLEAN_BUILD=true
            shift
            ;;
        --device|-d)
            DEVICE_NAME="$2"
            shift 2
            ;;
        --help|-h)
            echo "iOS Device Build & Deploy Script"
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --verbose, -v          Show detailed build output"
            echo "  --clean, -c            Clean build directory before building"
            echo "  --device, -d NAME      Device name to deploy to (overrides .env)"
            echo "  --help, -h             Show this help message"
            echo ""
            echo "The device name can be set in three ways (in order of precedence):"
            echo "  1. Command line: --device \"Device Name\""
            echo "  2. Environment variable: IOS_DEVICE_NAME"
            echo "  3. .env file: IOS_DEVICE_NAME=Device Name"
            echo ""
            echo "To list available devices, run:"
            echo "  xcrun xctrace list devices"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Helper functions
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Check if we're in the project root
if [[ ! -d "$IOS_PROJECT_PATH" ]]; then
    log_error "iOS project not found at $IOS_PROJECT_PATH"
    log_error "Please run this script from the project root directory"
    exit 1
fi

log_info "Starting iOS device build & deploy..."

# Check if Xcode is installed
if ! command -v xcodebuild &> /dev/null; then
    log_error "xcodebuild not found. Please install Xcode and command line tools."
    exit 1
fi

# Check if we have full Xcode or just Command Line Tools
DEVELOPER_DIR=$(xcode-select -p 2>/dev/null || echo "")
if [[ "$DEVELOPER_DIR" == *"CommandLineTools"* ]]; then
    log_error "Full Xcode application is required for iOS device builds."
    log_error "Current developer directory: $DEVELOPER_DIR"
    log_error ""
    log_error "Please install Xcode from the Mac App Store, then run:"
    log_error "  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
    exit 1
fi

# Get Xcode version
XCODE_VERSION=$(xcodebuild -version 2>/dev/null | head -n1)
if [[ -z "$XCODE_VERSION" ]]; then
    log_error "Unable to get Xcode version. Please ensure Xcode is properly installed."
    exit 1
fi
log_info "Using $XCODE_VERSION"

# Determine device name from .env, environment, or command line
if [[ -z "$DEVICE_NAME" ]]; then
    # Check environment variable first
    if [[ -n "$IOS_DEVICE_NAME" ]]; then
        DEVICE_NAME="$IOS_DEVICE_NAME"
        log_info "Using device from environment: $DEVICE_NAME"
    # Then check .env file
    elif [[ -f ".env" ]]; then
        DEVICE_NAME=$(grep "^IOS_DEVICE_NAME=" .env | cut -d= -f2- | tr -d '"' | tr -d "'" || echo "")
        if [[ -n "$DEVICE_NAME" ]]; then
            log_info "Using device from .env: $DEVICE_NAME"
        fi
    fi
fi

# If still no device name, show error with available devices
if [[ -z "$DEVICE_NAME" ]]; then
    log_error "No device name specified!"
    log_error ""
    log_error "Set device name in one of these ways:"
    log_error "  1. Command line: $0 --device \"Your Device Name\""
    log_error "  2. .env file: IOS_DEVICE_NAME=Your Device Name"
    log_error "  3. Environment: export IOS_DEVICE_NAME=\"Your Device Name\""
    log_error ""
    log_error "Available devices:"
    xcrun xctrace list devices 2>&1 | grep -E "^\w" | head -20
    exit 1
fi

# Verify device exists and is available
log_info "Checking if device '$DEVICE_NAME' is available..."
DEVICE_LIST=$(xcrun xctrace list devices 2>&1)

# Check if device exists in the list
if ! echo "$DEVICE_LIST" | grep -q "$DEVICE_NAME"; then
    log_error "Device '$DEVICE_NAME' not found!"
    log_error ""
    log_error "Available devices:"
    echo "$DEVICE_LIST" | grep -E "^\w" | head -20
    exit 1
fi

# Extract device ID - can be either UUID format or 24-character hex format
# Format examples:
#   UUID: (D9A19E46-FF61-5FEA-A8BA-6F34F2236E7F)
#   Hex:  (00008130-001640811A98001C)
DEVICE_LINE=$(echo "$DEVICE_LIST" | grep "$DEVICE_NAME")
DEVICE_ID=$(echo "$DEVICE_LINE" | grep -o '([A-F0-9-]\{36\})' | tr -d '()' | head -1 || echo "")

# If UUID format didn't match, try the shorter hex format (physical devices)
if [[ -z "$DEVICE_ID" ]]; then
    DEVICE_ID=$(echo "$DEVICE_LINE" | grep -o '([0-9A-F]\{8\}-[0-9A-F]\{16\})' | tr -d '()' | head -1 || echo "")
fi

if [[ -z "$DEVICE_ID" ]]; then
    log_error "Could not determine device ID for '$DEVICE_NAME'"
    log_error "Device line found: $DEVICE_LINE"
    log_error "Make sure your device is connected and trusted"
    exit 1
fi

log_success "Found device: $DEVICE_NAME ($DEVICE_ID)"

# Clean build directory if requested
if [[ "$CLEAN_BUILD" == true ]]; then
    log_info "Cleaning build directory..."
    if [[ -d "$BUILD_DIR" ]]; then
        rm -rf "$BUILD_DIR"
        log_success "Build directory cleaned"
    fi
fi

# Create build directory for logs
mkdir -p "$BUILD_DIR"

# Build settings for device - minimal settings to avoid conflicts
BUILD_SETTINGS=(
    "ONLY_ACTIVE_ARCH=YES"
    # Code signing is required for device builds
    # Xcode will use automatic signing from project settings
)

# Physical device destination
DESTINATION="platform=iOS,id=$DEVICE_ID"

# Determine output verbosity
if [[ "$VERBOSE" == true ]]; then
    log_info "Running in verbose mode - showing detailed build output"
else
    log_info "Running in quiet mode - use --verbose for detailed output"
fi

# Function to run xcodebuild with proper error handling
run_xcodebuild() {
    local action=$1
    local log_file="$BUILD_DIR/build_${action}.log"
    local result_bundle="$BUILD_DIR/result.xcresult"

    log_info "Running $action for device..."

    # Build the command with result bundle for diagnostics
    local cmd="xcodebuild -project $IOS_PROJECT_PATH -scheme $SCHEME_NAME -destination '$DESTINATION'"
    for setting in "${BUILD_SETTINGS[@]}"; do
        cmd="$cmd $setting"
    done
    cmd="$cmd -resultBundlePath '$result_bundle' $action"

    if [[ "$VERBOSE" == true ]]; then
        # Show output in real-time
        if eval "$cmd"; then
            log_success "$action completed successfully"
            return 0
        else
            log_error "$action failed"
            return 1
        fi
    else
        # Capture output to log file
        if eval "$cmd > $log_file 2>&1"; then
            log_success "$action completed successfully"
            return 0
        else
            log_error "$action failed"
            log_error "Build log saved to: $log_file"
            log_error "Last 30 lines of build output:"
            echo "----------------------------------------"
            tail -30 "$log_file"
            echo "----------------------------------------"
            return 1
        fi
    fi
}

# Start timing
START_TIME=$(date +%s)

# Remove existing result bundle if it exists (xcodebuild won't overwrite)
RESULT_BUNDLE="$BUILD_DIR/result.xcresult"
if [[ -d "$RESULT_BUNDLE" ]]; then
    rm -rf "$RESULT_BUNDLE"
fi

# Build the app for device
log_info "Building app for device: $DEVICE_NAME"
log_info "This will compile, sign, and prepare the app..."

if ! run_xcodebuild "build"; then
    log_error "Build failed!"
    log_error ""
    log_error "Common issues:"
    log_error "  1. Code signing - Open project in Xcode and configure signing"
    log_error "  2. Provisioning profile - Ensure you have valid developer certificate"
    log_error "  3. Stale build cache - Try running with --clean flag"
    log_error ""
    log_error "Full build log: $BUILD_DIR/build_build.log"
    log_error ""
    log_error "If you see Swift macro errors, try:"
    log_error "  rm -rf ~/Library/Developer/Xcode/DerivedData/Houston-*"
    exit 1
fi

# Find the built app
log_info "Locating built app..."
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData/Houston-*/Build/Products/Debug-iphoneos/Houston.app -maxdepth 0 2>/dev/null | head -1)

if [[ -z "$APP_PATH" ]]; then
    log_error "Could not find built app!"
    log_error "Expected location: ~/Library/Developer/Xcode/DerivedData/Houston-*/Build/Products/Debug-iphoneos/Houston.app"
    exit 1
fi

log_success "Found app at: $APP_PATH"

# Install to device using devicectl
log_info "Installing app to device..."
INSTALL_LOG="$BUILD_DIR/install.log"

if xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH" > "$INSTALL_LOG" 2>&1; then
    log_success "App installed successfully!"
else
    log_error "Installation failed!"
    log_error ""
    log_error "Common issues:"
    log_error "  1. Device not trusted - Check 'Trust This Computer' on device"
    log_error "  2. Device locked - Unlock your device during installation"
    log_error "  3. Storage full - Free up space on device"
    log_error ""
    log_error "Installation log:"
    cat "$INSTALL_LOG"
    exit 1
fi

# Calculate build time
END_TIME=$(date +%s)
BUILD_TIME=$((END_TIME - START_TIME))

# Extract and display warnings from result bundle
if [[ -d "$RESULT_BUNDLE" ]]; then
    BUILD_RESULTS=$(xcrun xcresulttool get build-results --path "$RESULT_BUNDLE" 2>/dev/null || echo "{}")
    WARNING_COUNT=$(echo "$BUILD_RESULTS" | grep -o '"warningCount" : [0-9]*' | grep -o '[0-9]*' || echo "0")

    if [[ "$WARNING_COUNT" -gt 0 ]]; then
        echo ""
        log_warning "Build completed with $WARNING_COUNT warnings"
        log_info "Full build log: $BUILD_DIR/build_build.log"
    fi
else
    WARNING_COUNT=0
fi

# Success summary
echo ""
log_success "🎉 App successfully installed on $DEVICE_NAME!"
log_info "Build time: ${BUILD_TIME}s"
log_info "Build artifacts saved to: $BUILD_DIR"

# Show some build statistics
if [[ -d "$BUILD_DIR" ]]; then
    SWIFT_FILES_COUNT=$(find ios/Sources -name "*.swift" 2>/dev/null | wc -l | tr -d ' ')
    BUILD_SIZE=$(du -sh "$BUILD_DIR" 2>/dev/null | cut -f1)
    log_info "Swift files compiled: $SWIFT_FILES_COUNT"
    log_info "Build directory size: $BUILD_SIZE"
    if [[ "$WARNING_COUNT" -gt 0 ]]; then
        log_info "Warnings: $WARNING_COUNT"
    fi
fi

echo ""
log_success "✨ You can now launch the app on your device!"
log_info "Look for 'Houston' on your home screen"

# Cleanup suggestion
if [[ "$CLEAN_BUILD" != true ]]; then
    echo ""
    log_info "💡 Tip: Use --clean flag for a fresh build if you encounter issues"
    log_info "💡 Tip: Use --verbose flag to see detailed build output"
fi
