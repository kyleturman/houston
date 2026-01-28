#!/bin/bash
# check_env.sh - Validates environment variables before starting Houston
# Exit codes: 0 = ready to start, 1 = missing required vars

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Houston Environment Check"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check if .env exists
if [ ! -f .env ]; then
    echo -e "  ${RED}✗${NC} No .env file found"
    echo ""
    echo "  Run 'make init' first to create .env and generate secrets."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    exit 1
fi

# Load .env file (handles values with spaces)
while IFS='=' read -r key value; do
    # Skip comments and empty lines
    [[ "$key" =~ ^#.*$ ]] && continue
    [[ -z "$key" ]] && continue
    # Remove leading/trailing whitespace from key
    key=$(echo "$key" | xargs)
    # Skip if key is empty after trimming
    [[ -z "$key" ]] && continue
    # Export the variable (value keeps its spaces)
    export "$key=$value"
done < .env

ERRORS=0
WARNINGS=0

# Helper function to check a required variable
check_required() {
    local var_name=$1
    local description=$2
    local value="${!var_name}"

    if [ -z "$value" ]; then
        echo -e "  ${RED}✗${NC} $var_name"
        echo -e "    ${YELLOW}$description${NC}"
        ERRORS=$((ERRORS + 1))
    else
        # Mask sensitive values
        if [[ "$var_name" == *"KEY"* ]] || [[ "$var_name" == *"SECRET"* ]] || [[ "$var_name" == *"PASSWORD"* ]] || [[ "$var_name" == *"TOKEN"* ]]; then
            echo -e "  ${GREEN}✓${NC} $var_name = ****${value: -4}"
        else
            echo -e "  ${GREEN}✓${NC} $var_name = $value"
        fi
    fi
}

# Helper function to check an optional variable (warning only)
check_optional() {
    local var_name=$1
    local description=$2
    local value="${!var_name}"

    if [ -z "$value" ]; then
        echo -e "  ${YELLOW}-${NC} $var_name not set"
        echo -e "    ${YELLOW}$description${NC}"
        WARNINGS=$((WARNINGS + 1))
    else
        if [[ "$var_name" == *"KEY"* ]] || [[ "$var_name" == *"SECRET"* ]] || [[ "$var_name" == *"PASSWORD"* ]] || [[ "$var_name" == *"TOKEN"* ]]; then
            echo -e "  ${GREEN}✓${NC} $var_name = ****${value: -4}"
        else
            echo -e "  ${GREEN}✓${NC} $var_name = $value"
        fi
    fi
}

# ============================================================================
# Secrets (auto-generated)
# ============================================================================
echo "▸ Secrets"
check_required "SECRET_KEY_BASE" "Run: make init"
check_required "USER_ENCRYPTION_KEY" "Run: make init"
echo ""

# ============================================================================
# Step 1: AI Configuration (required)
# ============================================================================
echo "▸ Step 1: AI Configuration"

LLM_OK=0
if [ -n "$ANTHROPIC_API_KEY" ]; then
    echo -e "  ${GREEN}✓${NC} LLM: Anthropic"
    LLM_OK=1
elif [ -n "$OPENAI_API_KEY" ]; then
    echo -e "  ${GREEN}✓${NC} LLM: OpenAI"
    LLM_OK=1
elif [ -n "$OPENROUTER_API_KEY" ]; then
    echo -e "  ${GREEN}✓${NC} LLM: OpenRouter"
    LLM_OK=1
elif [[ "$LLM_AGENTS_MODEL" == ollama:* ]] || [[ "$LLM_TASKS_MODEL" == ollama:* ]]; then
    echo -e "  ${GREEN}✓${NC} LLM: Ollama (local)"
    LLM_OK=1
fi

if [ $LLM_OK -eq 0 ]; then
    echo -e "  ${RED}✗${NC} LLM provider not configured"
    echo -e "    ${YELLOW}Set: ANTHROPIC_API_KEY, OPENAI_API_KEY, or OPENROUTER_API_KEY${NC}"
    ERRORS=$((ERRORS + 1))
fi

if [ -n "$BRAVE_API_KEY" ]; then
    echo -e "  ${GREEN}✓${NC} Web search: Brave"
else
    echo -e "  ${RED}✗${NC} Web search not configured"
    echo -e "    ${YELLOW}Set: BRAVE_API_KEY (get free key at brave.com/search/api)${NC}"
    ERRORS=$((ERRORS + 1))
fi
echo ""

# ============================================================================
# Step 2: Remote Access (for iOS outside local network)
# ============================================================================
echo "▸ Step 2: Remote Access"

if [ -n "$SERVER_PUBLIC_URL" ]; then
    echo -e "  ${GREEN}✓${NC} $SERVER_PUBLIC_URL"
elif [ -n "$NGROK_AUTHTOKEN" ] && [ -n "$NGROK_DOMAIN" ]; then
    echo -e "  ${GREEN}✓${NC} https://$NGROK_DOMAIN (ngrok)"
else
    echo -e "  ${YELLOW}-${NC} Not configured"
    echo -e "    ${YELLOW}iOS app will only work on your local WiFi${NC}"
    WARNINGS=$((WARNINGS + 1))
fi
echo ""

# ============================================================================
# Step 3: Email (optional)
# ============================================================================
echo "▸ Step 3: Email"

if [ -n "$EMAIL_PROVIDER" ]; then
    # All providers use SMTP - check the required fields
    SMTP_OK=1
    [ -z "$SMTP_ADDRESS" ] && SMTP_OK=0
    [ -z "$SMTP_USERNAME" ] && SMTP_OK=0
    [ -z "$SMTP_PASSWORD" ] && SMTP_OK=0

    if [ $SMTP_OK -eq 1 ]; then
        echo -e "  ${GREEN}✓${NC} $EMAIL_PROVIDER via $SMTP_ADDRESS"
    else
        echo -e "  ${YELLOW}!${NC} $EMAIL_PROVIDER incomplete"
        [ -z "$SMTP_ADDRESS" ] && echo -e "    ${YELLOW}Missing: SMTP_ADDRESS${NC}"
        [ -z "$SMTP_USERNAME" ] && echo -e "    ${YELLOW}Missing: SMTP_USERNAME${NC}"
        [ -z "$SMTP_PASSWORD" ] && echo -e "    ${YELLOW}Missing: SMTP_PASSWORD${NC}"
        WARNINGS=$((WARNINGS + 1))
    fi
else
    echo -e "  ${YELLOW}-${NC} Not configured"
    echo -e "    ${YELLOW}Using invite codes instead of magic links${NC}"
    WARNINGS=$((WARNINGS + 1))
fi
echo ""

# ============================================================================
# Step 4: Integrations (optional)
# ============================================================================
echo "▸ Step 4: Integrations"

if [ -n "$PLAID_CLIENT_ID" ] && [ -n "$PLAID_SECRET" ]; then
    echo -e "  ${GREEN}✓${NC} Financial data (Plaid)"
else
    echo -e "  ${YELLOW}-${NC} None configured"
fi
echo ""

# ============================================================================
# Summary
# ============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ $ERRORS -eq 0 ]; then
    if [ $WARNINGS -gt 0 ]; then
        echo -e "  ${GREEN}✓${NC} Ready to start (with $WARNINGS optional config(s) missing)"
    else
        echo -e "  ${GREEN}✓${NC} All configuration set"
    fi
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    exit 0
else
    echo -e "  ${RED}✗ Missing $ERRORS required configuration(s)${NC}"
    echo ""
    echo "  Edit .env to add the missing values, then run 'make start' again."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    exit 1
fi
