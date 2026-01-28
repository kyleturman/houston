#!/bin/bash
# Houston - TestFlight Deployment Script
# Usage: ./testflight.sh [--dry-run]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory (ios/scripts)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS_DIR="$(dirname "$SCRIPT_DIR")"
ROOT_DIR="$(dirname "$IOS_DIR")"

# Configuration files
CONFIG_FILE="$IOS_DIR/config/testflight.yml"
FASTLANE_ENV="$IOS_DIR/fastlane/.env"
ROOT_ENV="$ROOT_DIR/.env"
INFO_PLIST="$IOS_DIR/Resources/Info.plist"
API_HELPER="$IOS_DIR/fastlane/asc_api.rb"

# Parse arguments
DRY_RUN=false
for arg in "$@"; do
    case $arg in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
    esac
done

# Helper: Print colored output
print_header() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "  $1"
}

# Helper: Read YAML value (simple parser for flat keys)
yaml_get() {
    local file="$1"
    local key="$2"
    grep "^${key}:" "$file" 2>/dev/null | sed "s/^${key}:[[:space:]]*//" | sed 's/^"//' | sed 's/"$//'
}

# Helper: Read nested YAML value
yaml_get_nested() {
    local file="$1"
    local parent="$2"
    local key="$3"
    awk "/^${parent}:/{found=1} found && /^  ${key}:/{print; exit}" "$file" | sed "s/^  ${key}:[[:space:]]*//" | sed 's/^"//' | sed 's/"$//'
}

# Helper: Read env value
env_get() {
    local file="$1"
    local key="$2"
    grep "^${key}=" "$file" 2>/dev/null | cut -d= -f2-
}

# Step 1: Load configuration
print_header "Loading Configuration"

# Check config file exists
if [ ! -f "$CONFIG_FILE" ]; then
    print_error "Config file not found: $CONFIG_FILE"
    exit 1
fi

# Check fastlane .env exists
if [ ! -f "$FASTLANE_ENV" ]; then
    print_error "Fastlane .env not found: $FASTLANE_ENV"
    print_info "Copy from .env.example and fill in your credentials"
    exit 1
fi

# Load config values
APP_ID=$(yaml_get "$CONFIG_FILE" "app_id")
BUNDLE_ID=$(yaml_get "$CONFIG_FILE" "bundle_id")
EXTERNAL_GROUP=$(yaml_get "$CONFIG_FILE" "external_group")
CONTACT_EMAIL=$(yaml_get_nested "$CONFIG_FILE" "contact" "email")
CONTACT_FIRST_NAME=$(yaml_get_nested "$CONFIG_FILE" "contact" "first_name")
CONTACT_LAST_NAME=$(yaml_get_nested "$CONFIG_FILE" "contact" "last_name")
CONTACT_PHONE=$(yaml_get_nested "$CONFIG_FILE" "contact" "phone")
DEMO_EMAIL=$(yaml_get "$CONFIG_FILE" "demo_email")

# Load secrets from fastlane/.env
ASC_KEY_ID=$(env_get "$FASTLANE_ENV" "ASC_KEY_ID")
ASC_ISSUER_ID=$(env_get "$FASTLANE_ENV" "ASC_ISSUER_ID")
ASC_KEY_PATH_REL=$(env_get "$FASTLANE_ENV" "ASC_KEY_PATH")
ASC_KEY_PATH="$IOS_DIR/fastlane/$ASC_KEY_PATH_REL"
APPLE_TEAM_ID=$(env_get "$FASTLANE_ENV" "APPLE_TEAM_ID")

# Get server URL from root .env
if [ -f "$ROOT_ENV" ]; then
    SERVER_URL=$(env_get "$ROOT_ENV" "SERVER_PUBLIC_URL")
    if [ -z "$SERVER_URL" ]; then
        NGROK_DOMAIN=$(env_get "$ROOT_ENV" "NGROK_DOMAIN")
        if [ -n "$NGROK_DOMAIN" ]; then
            SERVER_URL="https://$NGROK_DOMAIN"
        fi
    fi
fi

print_success "Config loaded from $CONFIG_FILE"
print_info "App ID: $APP_ID"
print_info "Bundle ID: $BUNDLE_ID"

# Step 2: Get current version from Info.plist
CURRENT_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST" 2>/dev/null)
print_info "Current version: $CURRENT_VERSION"

# Step 3: Prompt for version
print_header "Version Configuration"
echo ""
echo -n "Marketing version [$CURRENT_VERSION]: "
read -r NEW_VERSION
NEW_VERSION=${NEW_VERSION:-$CURRENT_VERSION}

if [ "$NEW_VERSION" != "$CURRENT_VERSION" ]; then
    print_info "Version will be updated: $CURRENT_VERSION → $NEW_VERSION"
fi

# Step 4: Prompt for changelog
DEFAULT_CHANGELOG="Bug fixes and improvements"
echo ""
echo -n "What's new? [$DEFAULT_CHANGELOG]: "
read -r CHANGELOG
CHANGELOG=${CHANGELOG:-$DEFAULT_CHANGELOG}

# Step 5: Generate build number
BUILD_NUMBER=$(date +%Y%m%d%H%M)
print_info "Build number: $BUILD_NUMBER"

# Step 6: Validate prerequisites
print_header "Validating Prerequisites"

# Check Xcode
if ! command -v xcodebuild &> /dev/null; then
    print_error "xcodebuild not found. Install Xcode from the App Store."
    exit 1
fi
print_success "Xcode installed"

# Check API key
if [ ! -f "$ASC_KEY_PATH" ]; then
    print_error "API key not found: $ASC_KEY_PATH"
    print_info "Download your App Store Connect API key and place it in ios/fastlane/"
    exit 1
fi
print_success "API key found"

# Check server URL
if [ -z "$SERVER_URL" ]; then
    print_error "No SERVER_PUBLIC_URL or NGROK_DOMAIN found in .env"
    print_info "Apple reviewers need a public URL to test against."
    exit 1
fi
print_success "Server URL: $SERVER_URL"

# Check Docker/backend (for demo account)
if ! docker compose ps 2>/dev/null | grep -q "backend.*running"; then
    print_warning "Backend not running - demo account creation may fail"
fi

# Install Ruby dependencies
print_info "Checking Ruby dependencies..."
cd "$IOS_DIR/fastlane"
if ! bundle check &>/dev/null; then
    bundle install --quiet
fi
cd "$IOS_DIR"
print_success "Ruby dependencies ready"

# Step 7: Show summary
print_header "Deployment Summary"
echo ""
print_info "Version:      $NEW_VERSION"
print_info "Build:        $BUILD_NUMBER"
print_info "Changelog:    $CHANGELOG"
print_info "Server:       $SERVER_URL"
print_info "Contact:      $CONTACT_FIRST_NAME $CONTACT_LAST_NAME <$CONTACT_EMAIL>"
print_info "Demo Account: $DEMO_EMAIL"
print_info "Beta Group:   $EXTERNAL_GROUP"
echo ""

if [ "$DRY_RUN" = true ]; then
    print_header "DRY RUN - No changes made"
    print_info "Run without --dry-run to build and upload"
    exit 0
fi

# Step 8: Confirm before proceeding
echo -n "Proceed with build and upload? [Y/n]: "
read -r CONFIRM
CONFIRM=${CONFIRM:-Y}
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    print_info "Aborted"
    exit 0
fi

# Step 9: Create demo account
print_header "Creating Demo Account"

cd "$ROOT_DIR"
DEMO_RESULT=$(docker compose exec -T -e EMAIL="$DEMO_EMAIL" -e SERVER_URL="$SERVER_URL" backend bundle exec rails runner "
    require 'cgi'
    email = ENV.fetch('EMAIL').strip.downcase
    server_url = ENV.fetch('SERVER_URL')
    user = User.find_or_create_by!(email: email)
    user.invite_tokens.destroy_all
    invite = user.invite_tokens.build
    code = invite.set_token!
    invite.save!
    invite_link = \"heyhouston://signin?url=#{CGI.escape(server_url)}&email=#{CGI.escape(email)}&token=#{CGI.escape(code)}&name=Houston&type=invite\"
    puts \"CODE:#{code}\"
    puts \"LINK:#{invite_link}\"
" 2>/dev/null | grep -v 'Sidekiq\|INFO\|pid=' | tr -d '\r')

INVITE_CODE=$(echo "$DEMO_RESULT" | grep "^CODE:" | cut -d: -f2-)
INVITE_LINK=$(echo "$DEMO_RESULT" | grep "^LINK:" | cut -d: -f2-)

if [ -z "$INVITE_LINK" ]; then
    print_error "Failed to create demo account. Is the backend running?"
    exit 1
fi
print_success "Demo account created"
print_info "Invite link: $INVITE_LINK"

# Step 10: Update version in Info.plist
print_header "Updating Version"

cd "$IOS_DIR"

if [ "$NEW_VERSION" != "$CURRENT_VERSION" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $NEW_VERSION" "$INFO_PLIST"
    print_success "Marketing version updated to $NEW_VERSION"
fi

/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$INFO_PLIST"
print_success "Build number updated to $BUILD_NUMBER"

# Step 11: Build archive
print_header "Building Archive"

ARCHIVE_PATH="$IOS_DIR/build/Houston.xcarchive"
IPA_PATH="$IOS_DIR/build/Houston.ipa"

rm -rf "$IOS_DIR/build"
mkdir -p "$IOS_DIR/build"

print_info "Building... (this may take a few minutes)"

xcodebuild archive \
    -project "$IOS_DIR/Houston.xcodeproj" \
    -scheme Houston \
    -archivePath "$ARCHIVE_PATH" \
    -destination "generic/platform=iOS" \
    -allowProvisioningUpdates \
    CODE_SIGN_STYLE=Automatic \
    DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
    2>&1 | while read -r line; do
        if [[ "$line" == *"error:"* ]]; then
            echo "$line"
        elif [[ "$line" == *"ARCHIVE SUCCEEDED"* ]]; then
            echo "$line"
        fi
    done

if [ ! -d "$ARCHIVE_PATH" ]; then
    print_error "Archive failed. Check build logs."
    exit 1
fi
print_success "Archive created"

# Step 12: Export IPA
print_header "Exporting IPA"

# Create export options plist
EXPORT_OPTIONS="$IOS_DIR/build/ExportOptions.plist"
cat > "$EXPORT_OPTIONS" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store</string>
    <key>teamID</key>
    <string>$APPLE_TEAM_ID</string>
    <key>uploadSymbols</key>
    <true/>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>
EOF

xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$IOS_DIR/build" \
    -exportOptionsPlist "$EXPORT_OPTIONS" \
    -allowProvisioningUpdates \
    2>&1 | while read -r line; do
        if [[ "$line" == *"error:"* ]]; then
            echo "$line"
        elif [[ "$line" == *"EXPORT SUCCEEDED"* ]]; then
            echo "$line"
        fi
    done

if [ ! -f "$IPA_PATH" ]; then
    print_error "Export failed. Check build logs."
    exit 1
fi
print_success "IPA exported"

# Step 13: Setup API key for altool
print_header "Uploading to App Store Connect"

mkdir -p ~/private_keys
cp "$ASC_KEY_PATH" ~/private_keys/AuthKey_${ASC_KEY_ID}.p8

print_info "Uploading IPA... (this may take several minutes)"

UPLOAD_OUTPUT=$(xcrun altool --upload-app \
    --file "$IPA_PATH" \
    --type ios \
    --apiKey "$ASC_KEY_ID" \
    --apiIssuer "$ASC_ISSUER_ID" \
    2>&1)

UPLOAD_STATUS=$?

if [ $UPLOAD_STATUS -ne 0 ]; then
    print_error "Upload failed:"
    echo "$UPLOAD_OUTPUT"
    exit 1
fi
print_success "Build uploaded successfully"

# Step 14: Wait for build to process and configure via API
print_header "Configuring TestFlight"

print_info "Waiting for build to process..."

# Use the Ruby API helper
cd "$IOS_DIR/fastlane"

# Export credentials for Ruby script
export ASC_KEY_ID
export ASC_ISSUER_ID
export ASC_KEY_PATH

# Wait for build to be processed
BUILD_JSON=$(bundle exec ruby "$API_HELPER" get-build \
    --app-id "$APP_ID" \
    --version "$NEW_VERSION" \
    --build-number "$BUILD_NUMBER" \
    --timeout 600 2>&1) || {
    print_warning "Could not get build from API (it may still be processing)"
    print_info "Complete the following steps manually in App Store Connect:"
    print_info "1. Wait for build to finish processing"
    print_info "2. Add build to '$EXTERNAL_GROUP' group"
    print_info "3. Set demo account and review notes"
    print_info "4. Submit for beta review"
    BUILD_JSON=""
}

if [ -n "$BUILD_JSON" ] && [ "$BUILD_JSON" != "{}" ]; then
    BUILD_ID=$(echo "$BUILD_JSON" | ruby -rjson -e 'puts JSON.parse(STDIN.read)["id"]')
    print_success "Build processed: $BUILD_ID"

    # Generate review notes from template
    REVIEW_NOTES=$(awk '/^review_notes_template:/{found=1; next} found && /^[^ ]/{exit} found{print}' "$CONFIG_FILE" | \
        sed "s|{{invite_link}}|$INVITE_LINK|g" | \
        sed "s|{{server_url}}|$SERVER_URL|g")

    # Get beta app description
    BETA_DESCRIPTION=$(awk '/^beta_description:/{found=1; next} found && /^[^ ]/{exit} found{print}' "$CONFIG_FILE")

    # Set beta app description (first build only - won't fail if already set)
    print_info "Setting beta app description..."
    bundle exec ruby "$API_HELPER" set-description \
        --app-id "$APP_ID" \
        --description "$BETA_DESCRIPTION" 2>/dev/null || true

    # Set changelog
    print_info "Setting changelog..."
    bundle exec ruby "$API_HELPER" set-changelog \
        --build-id "$BUILD_ID" \
        --changelog "$CHANGELOG" 2>/dev/null || print_warning "Could not set changelog"

    # Set review info
    print_info "Setting review info..."
    bundle exec ruby "$API_HELPER" set-review-info \
        --app-id "$APP_ID" \
        --demo-name "$DEMO_EMAIL" \
        --demo-password "$INVITE_LINK" \
        --contact-email "$CONTACT_EMAIL" \
        --contact-first-name "$CONTACT_FIRST_NAME" \
        --contact-last-name "$CONTACT_LAST_NAME" \
        --contact-phone "$CONTACT_PHONE" \
        --notes "$REVIEW_NOTES" 2>/dev/null || print_warning "Could not set review info"

    # Get or create beta group
    print_info "Configuring beta group..."
    GROUP_JSON=$(bundle exec ruby "$API_HELPER" get-or-create-group \
        --app-id "$APP_ID" \
        --group-name "$EXTERNAL_GROUP" 2>&1) || print_warning "Could not configure beta group"

    if [ -n "$GROUP_JSON" ] && [ "$GROUP_JSON" != "{}" ]; then
        GROUP_ID=$(echo "$GROUP_JSON" | ruby -rjson -e 'puts JSON.parse(STDIN.read)["id"]')

        # Add build to group
        print_info "Adding build to group..."
        bundle exec ruby "$API_HELPER" add-to-group \
            --build-id "$BUILD_ID" \
            --group-id "$GROUP_ID" 2>/dev/null || print_warning "Could not add build to group"

        # Submit for beta review
        print_info "Submitting for beta review..."
        bundle exec ruby "$API_HELPER" submit-review \
            --build-id "$BUILD_ID" 2>/dev/null || print_warning "Could not submit for review (may require manual submission)"

        # Get public link
        PUBLIC_LINK=$(bundle exec ruby "$API_HELPER" get-public-link \
            --group-id "$GROUP_ID" 2>/dev/null | ruby -rjson -e 'puts JSON.parse(STDIN.read)' 2>/dev/null) || true
    fi
fi

# Step 15: Print summary
print_header "Deployment Complete!"

echo ""
print_success "Version $NEW_VERSION ($BUILD_NUMBER) uploaded to TestFlight"
echo ""
print_info "Demo Account:"
print_info "  Email: $DEMO_EMAIL"
print_info "  Invite Link: $INVITE_LINK"
echo ""

if [ -n "$PUBLIC_LINK" ] && [ "$PUBLIC_LINK" != "null" ]; then
    print_info "TestFlight Public Link:"
    print_info "  $PUBLIC_LINK"
    echo ""
fi

print_info "App Store Connect:"
print_info "  https://appstoreconnect.apple.com/apps/$APP_ID/testflight"
echo ""

# Clean up
rm -rf "$ARCHIVE_PATH"
rm -f "$EXPORT_OPTIONS"

print_success "Done!"
