#!/bin/bash

# iOS Build Check Script
# Validates that iOS code changes will compile successfully
# Usage: ./scripts/ios_build_check.sh [--verbose] [--clean]

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
        --help|-h)
            echo "iOS Build Check Script"
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --verbose, -v    Show detailed build output"
            echo "  --clean, -c      Clean build directory before building"
            echo "  --help, -h       Show this help message"
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

log_info "Starting iOS build validation..."

# Check if Xcode is installed
if ! command -v xcodebuild &> /dev/null; then
    log_error "xcodebuild not found. Please install Xcode and command line tools."
    exit 1
fi

# Check if we have full Xcode or just Command Line Tools
DEVELOPER_DIR=$(xcode-select -p 2>/dev/null || echo "")
if [[ "$DEVELOPER_DIR" == *"CommandLineTools"* ]]; then
    log_error "Full Xcode application is required for iOS compilation validation."
    log_error "Current developer directory: $DEVELOPER_DIR"
    log_error ""
    log_error "Please install Xcode from the Mac App Store, then run:"
    log_error "  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
    log_error ""
    log_error "Alternatively, if Xcode is installed in a different location:"
    log_error "  sudo xcode-select -s /path/to/Xcode.app/Contents/Developer"
    exit 1
fi

# Get Xcode version
XCODE_VERSION=$(xcodebuild -version 2>/dev/null | head -n1)
if [[ -z "$XCODE_VERSION" ]]; then
    log_error "Unable to get Xcode version. Please ensure Xcode is properly installed."
    exit 1
fi
log_info "Using $XCODE_VERSION"

# Clean build directory if requested
if [[ "$CLEAN_BUILD" == true ]]; then
    log_info "Cleaning build directory..."
    if [[ -d "$BUILD_DIR" ]]; then
        rm -rf "$BUILD_DIR"
        log_success "Build directory cleaned"
    fi
fi

# Create build directory
mkdir -p "$BUILD_DIR"

# Build settings
BUILD_SETTINGS=(
    "CONFIGURATION_BUILD_DIR=$PWD/$BUILD_DIR"
    "SYMROOT=$PWD/$BUILD_DIR"
    "ONLY_ACTIVE_ARCH=YES"
    "CODE_SIGNING_ALLOWED=NO"
    "CODE_SIGN_IDENTITY="
    "PROVISIONING_PROFILE="
    # Note: SWIFT_STRICT_CONCURRENCY=complete is already set in project file for our target
    # Don't override it here or it will apply to dependencies too and break the build
)

# iOS Simulator destination (use specific iPhone simulator for iOS 26)
DESTINATION="platform=iOS Simulator,name=iPhone 17,OS=26.0"

# Determine output verbosity
if [[ "$VERBOSE" == true ]]; then
    OUTPUT_REDIRECT=""
    log_info "Running in verbose mode - showing detailed build output"
else
    OUTPUT_REDIRECT="2>&1"
    log_info "Running in quiet mode - use --verbose for detailed output"
fi

# Function to run xcodebuild with proper error handling
run_xcodebuild() {
    local action=$1
    local log_file="$BUILD_DIR/build_${action}.log"
    local result_bundle="$BUILD_DIR/result.xcresult"

    log_info "Running $action..."

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
            log_error "Last 20 lines of build output:"
            echo "----------------------------------------"
            tail -20 "$log_file"
            echo "----------------------------------------"
            return 1
        fi
    fi
}

# Start timing
START_TIME=$(date +%s)

# Step 1: Clean (if not already done)
if [[ "$CLEAN_BUILD" == true ]]; then
    # Skip xcodebuild clean since we're using a custom build directory
    # The build directory was already cleaned above
    log_info "Skipping xcodebuild clean (using custom build directory)"
fi

# Step 2: Build
log_info "Building iOS project for compilation validation..."
BUILD_LOG="$BUILD_DIR/build_build.log"

# Remove existing result bundle if it exists (xcodebuild won't overwrite)
RESULT_BUNDLE="$BUILD_DIR/result.xcresult"
if [[ -d "$RESULT_BUNDLE" ]]; then
    rm -rf "$RESULT_BUNDLE"
fi

if ! run_xcodebuild "build"; then
    log_error "Build failed - there are compilation errors in your iOS code"
    log_error "Please fix the compilation errors and try again"
    exit 1
fi

# Calculate build time
END_TIME=$(date +%s)
BUILD_TIME=$((END_TIME - START_TIME))

# Extract and display warnings from result bundle
RESULT_BUNDLE="$BUILD_DIR/result.xcresult"
if [[ -d "$RESULT_BUNDLE" ]]; then
    # Extract build warnings using xcresulttool
    BUILD_RESULTS=$(xcrun xcresulttool get build-results --path "$RESULT_BUNDLE" 2>/dev/null || echo "{}")

    # Parse warning count from JSON (simple grep approach)
    WARNING_COUNT=$(echo "$BUILD_RESULTS" | grep -o '"warningCount" : [0-9]*' | grep -o '[0-9]*' || echo "0")
    ERROR_COUNT=$(echo "$BUILD_RESULTS" | grep -o '"errorCount" : [0-9]*' | grep -o '[0-9]*' || echo "0")

    if [[ "$WARNING_COUNT" -gt 0 || "$ERROR_COUNT" -gt 0 ]]; then
        echo ""
        if [[ "$ERROR_COUNT" -gt 0 ]]; then
            log_error "Found $ERROR_COUNT errors in build"
        fi
        if [[ "$WARNING_COUNT" -gt 0 ]]; then
            log_warning "Found $WARNING_COUNT warnings in build (Swift concurrency, deprecations, etc.)"

            # Extract sample warnings from build log for our source files
            if [[ -f "$BUILD_LOG" ]]; then
                SAMPLE_WARNINGS=$(grep -E "^/.*ios/Sources/.*\.swift:[0-9]+:[0-9]+: warning:" "$BUILD_LOG" | head -5 || true)
                if [[ -n "$SAMPLE_WARNINGS" ]]; then
                    echo ""
                    log_info "Sample warnings:"
                    echo "$SAMPLE_WARNINGS" | while IFS= read -r line; do
                        # Extract file:line and message
                        FILE_LINE=$(echo "$line" | grep -o "/.*\.swift:[0-9]*:[0-9]*")
                        MESSAGE=$(echo "$line" | sed 's|^.*/ios/Sources/\(.*\.swift:[0-9]*:[0-9]*:\) warning: \(.*\)$|\1 \2|')
                        echo "  - $MESSAGE"
                    done
                    if [[ "$WARNING_COUNT" -gt 5 ]]; then
                        echo ""
                        log_info "... and $((WARNING_COUNT - 5)) more warnings"
                    fi
                fi
            fi
        fi
        echo ""
        log_info "Full build log: $BUILD_DIR/build_build.log"
    fi
else
    WARNING_COUNT=0
fi

# Success summary
echo ""
log_success "🎉 iOS build validation completed successfully!"
log_info "Build time: ${BUILD_TIME}s"
log_info "Build artifacts saved to: $BUILD_DIR"

# Show some build statistics
if [[ -d "$BUILD_DIR" ]]; then
    SWIFT_FILES_COUNT=$(find ios/Sources -name "*.swift" | wc -l | tr -d ' ')
    BUILD_SIZE=$(du -sh "$BUILD_DIR" | cut -f1)
    log_info "Swift files compiled: $SWIFT_FILES_COUNT"
    log_info "Build directory size: $BUILD_SIZE"
    if [[ "$WARNING_COUNT" -gt 0 ]]; then
        log_info "Warnings: $WARNING_COUNT"
    fi
fi

echo ""
log_success "✨ Your iOS code changes are ready to compile!"
if [[ "$WARNING_COUNT" -gt 0 ]]; then
    log_warning "Note: Build succeeded but there are $WARNING_COUNT warnings to address"
    log_info "   Review warnings above or check full log: $BUILD_DIR/build_build.log"
fi
log_info "You can now safely commit your iOS changes"

# Note about live issues vs compilation warnings
echo ""
log_info "📝 Note: This script checks compilation errors and warnings from xcodebuild"
log_info "   Xcode IDE also shows 'Live Issues' from static analysis (Swift concurrency, etc.)"
log_info "   Live Issues appear in Xcode but are NOT captured by command-line builds"
log_info "   Check Xcode IDE's Issue Navigator for the full list of live issues"

# Cleanup suggestion
if [[ "$CLEAN_BUILD" != true ]]; then
    echo ""
    log_info "💡 Tip: Use --clean flag to ensure a completely fresh build"
    log_info "💡 Tip: Use --verbose flag to see detailed build output"
fi
