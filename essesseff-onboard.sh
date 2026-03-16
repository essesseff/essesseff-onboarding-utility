#!/bin/bash

# essesseff-onboard.sh
# essesseff Onboarding Utility
# Automates the process of creating a new essesseff app and configuring Argo CD deployments

set -euo pipefail

# Check for required dependencies
check_dependencies() {
  local missing_deps=()

  for cmd in curl git jq; do
    if ! command -v "$cmd" &> /dev/null; then
      missing_deps+=("$cmd")
    fi
  done

  if [ ${#missing_deps[@]} -gt 0 ]; then
    error "Missing required dependencies: ${missing_deps[*]}"
    error "Please install the missing dependencies before running this script"
    exit 1
  fi
}

# Check dependencies at startup
check_dependencies

# Colors for output (defined early for use in trap)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Capture start time (UTC)
SCRIPT_START_TIME=$(date -u +%s)
SCRIPT_START_TIMESTAMP=$(date -u +"%Y-%m-%d %H:%M:%S UTC")
echo ""
echo "================================================================================"
echo "essesseff Onboarding Utility"
echo "Started: $SCRIPT_START_TIMESTAMP"
echo "================================================================================"
echo ""

# Function to display completion timestamp and elapsed time
display_completion_info() {
  local exit_code=$1
  SCRIPT_END_TIME=$(date -u +%s)
  SCRIPT_END_TIMESTAMP=$(date -u +"%Y-%m-%d %H:%M:%S UTC")
  
  # Calculate elapsed time
  local elapsed_seconds=$((SCRIPT_END_TIME - SCRIPT_START_TIME))
  local hours=$((elapsed_seconds / 3600))
  local minutes=$(((elapsed_seconds % 3600) / 60))
  local seconds=$((elapsed_seconds % 60))
  
  # Format elapsed time
  local elapsed_formatted
  if [ $hours -gt 0 ]; then
    elapsed_formatted="${hours}h ${minutes}m ${seconds}s"
  elif [ $minutes -gt 0 ]; then
    elapsed_formatted="${minutes}m ${seconds}s"
  else
    elapsed_formatted="${seconds}s"
  fi
  
  echo ""
  echo "================================================================================"
  if [ $exit_code -eq 0 ]; then
    echo -e "${GREEN}✓ Completed successfully${NC}"
  else
    echo -e "${RED}✗ Completed with errors${NC}"
  fi
  echo "Started:  $SCRIPT_START_TIMESTAMP"
  echo "Finished: $SCRIPT_END_TIMESTAMP"
  echo "Elapsed:  $elapsed_formatted"
  echo "================================================================================"
  echo ""
}

# Set trap to display completion info on exit
trap 'display_completion_info $?' EXIT

# Default values
CONFIG_FILE=".essesseff"
ESSESSEFF_API_BASE_URL="${ESSESSEFF_API_BASE_URL:-https://essesseff.com/api/v1}"
LIST_TEMPLATES=false
LANGUAGE=""
CREATE_APP=false
SETUP_ARGOCD=""
VERBOSE=false
NON_ESSESSEFF_SUBSCRIBER_MODE=false

# Script directory (for bundled templates in non-subscriber mode)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLED_TEMPLATES_FILE="${SCRIPT_DIR}/bundled-global-templates.json"

# Print error message
error() {
  echo -e "${RED}Error:${NC} $1" >&2
}

# Print info message
info() {
  if [ "$VERBOSE" = true ]; then
    echo -e "${GREEN}Info:${NC} $1" >&2
  fi
}

# Print warning message
warning() {
  echo -e "${YELLOW}Warning:${NC} $1" >&2
}

# Retry a command up to max_attempts times, with delay_sec between attempts. For non-subscriber fault tolerance.
# Final attempt's output is not suppressed so the user sees the real error.
retry_cmd() {
  local max_attempts="$1"
  local delay_sec="$2"
  shift 2
  local attempt=1
  while [ "$attempt" -le "$max_attempts" ]; do
    if [ "$attempt" -lt "$max_attempts" ]; then
      if "$@" 2>/dev/null; then return 0; fi
      warning "Attempt $attempt/$max_attempts failed, retrying in ${delay_sec}s..."
    else
      if "$@"; then return 0; fi
    fi
    ((attempt++)) || true
    [ "$attempt" -le "$max_attempts" ] && sleep "$delay_sec"
  done
  return 1
}

# Print usage
usage() {
  cat << EOF
Usage: $0 [OPTIONS]

essesseff Onboarding Utility - Automates essesseff app creation and Argo CD setup

OPTIONS:
  --list-templates               List all available templates (global and account-specific, or bundled if --non-essesseff-subscriber-mode)
  --language LANGUAGE            Filter templates by language (go, python, node, java)
  --create-app                   Create a new essesseff app (via API or clone/replace/push if --non-essesseff-subscriber-mode)
  --setup-argocd ENVS            Comma-separated list of environments (dev,qa,staging,prod)
  --non-essesseff-subscriber-mode Run without essesseff API: clone templates, replace strings, create/push repos to your GitHub org
  --config-file FILE             Path to configuration file (default: .essesseff)
  --verbose                      Enable verbose output
  -h, --help                     Show this help message

EXAMPLES:
  # List all available templates
  $0 --list-templates --config-file .essesseff

  # List templates filtered by language
  $0 --list-templates --language go --config-file .essesseff

  # Create app and set up Argo CD for all environments
  $0 --create-app --setup-argocd dev,qa,staging,prod --config-file .essesseff

  # Create app only (no Argo CD setup)
  $0 --create-app --config-file .essesseff

  # Set up Argo CD only (app already exists)
  $0 --setup-argocd dev,qa --config-file .essesseff

CONFIGURATION:
  All configuration values must be specified in the .essesseff file:
  - ESSESSEFF_API_KEY (required)
  - ESSESSEFF_ACCOUNT_SLUG (required)
  - GITHUB_ORG (required)
  - APP_NAME (required)
  - TEMPLATE_NAME (required for --create-app)
  - TEMPLATE_IS_GLOBAL (required for --create-app)
  - ARGOCD_MACHINE_USER (required for --setup-argocd)
  - GITHUB_TOKEN (required for --setup-argocd)
  - ARGOCD_MACHINE_EMAIL (required for --setup-argocd)
  - APP_DESCRIPTION (optional for --create-app)
  - REPOSITORY_VISIBILITY (optional for --create-app, default: private)

PREREQUISITES:
  - kubectl must be installed and configured for each target environment (if using --setup-argocd)
  - Kubernetes cluster access must be available for each target environment (if using --setup-argocd)
  - GitHub organization must exist and have essesseff GitHub App installed
  - Organization must be linked to the essesseff account

EOF
}

# Parse command-line arguments
parse_args() {
  while [[ $# -gt 0 ]]; do
    # Skip empty arguments (can occur with line continuation e.g. "\      \n  --create-app")
    if [[ -z "${1:-}" ]]; then
      shift
      continue
    fi
    case $1 in
      --list-templates)
        LIST_TEMPLATES=true
        shift
        ;;
      --language)
        LANGUAGE="$2"
        shift 2
        ;;
      --create-app)
        CREATE_APP=true
        shift
        ;;
      --setup-argocd)
        SETUP_ARGOCD="$2"
        shift 2
        ;;
      --non-essesseff-subscriber-mode)
        NON_ESSESSEFF_SUBSCRIBER_MODE=true
        shift
        ;;
      --config-file)
        CONFIG_FILE="$2"
        shift 2
        ;;
      --verbose)
        VERBOSE=true
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        error "Unknown option: $1"
        usage
        exit 1
        ;;
    esac
  done

  # Validate that at least one action is specified
  if [ "$LIST_TEMPLATES" = false ] && [ "$CREATE_APP" = false ] && [ -z "$SETUP_ARGOCD" ]; then
    error "At least one action must be specified (--list-templates, --create-app, or --setup-argocd)"
    usage
    exit 1
  fi
}

# Read configuration file
read_config() {
  if [ ! -f "$CONFIG_FILE" ]; then
    error "Configuration file not found: $CONFIG_FILE"
    error "Copy from .essesseff.example (or the repository example), fill in required values, and save as $CONFIG_FILE (or specify a different file with --config-file)."
    exit 1
  fi

  info "Reading configuration from $CONFIG_FILE"

  # Source the config file
  # shellcheck source=/dev/null
  source "$CONFIG_FILE"
  
  # Trim whitespace and quotes from API key if present
  if [ -n "${ESSESSEFF_API_KEY:-}" ]; then
    ESSESSEFF_API_KEY=$(echo "$ESSESSEFF_API_KEY" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//")
  fi

  # Validate required variables
  local missing_vars=()

  if [ "$NON_ESSESSEFF_SUBSCRIBER_MODE" = false ]; then
    if [ -z "${ESSESSEFF_API_KEY:-}" ]; then
      missing_vars+=("ESSESSEFF_API_KEY")
    else
      if ! [[ "${ESSESSEFF_API_KEY}" =~ ^ess_[a-zA-Z0-9]{32}$ ]]; then
        error "Invalid API key format. API key must start with 'ess_' and be 36 characters total."
        exit 1
      fi
    fi
    if [ -z "${ESSESSEFF_ACCOUNT_SLUG:-}" ]; then
      missing_vars+=("ESSESSEFF_ACCOUNT_SLUG")
    fi
  fi

  if [ -z "${GITHUB_ORG:-}" ]; then
    missing_vars+=("GITHUB_ORG")
  fi

  if [ -z "${APP_NAME:-}" ]; then
    missing_vars+=("APP_NAME")
  fi

  if [ "$CREATE_APP" = true ]; then
    if [ -z "${TEMPLATE_NAME:-}" ]; then
      missing_vars+=("TEMPLATE_NAME")
    fi
    if [ "$NON_ESSESSEFF_SUBSCRIBER_MODE" = false ]; then
      if [ -z "${TEMPLATE_IS_GLOBAL:-}" ]; then
        missing_vars+=("TEMPLATE_IS_GLOBAL")
      fi
    fi
    if [ "$NON_ESSESSEFF_SUBSCRIBER_MODE" = true ]; then
      if [ -z "${GITHUB_ORG_ADMIN_PAT:-}" ]; then
        missing_vars+=("GITHUB_ORG_ADMIN_PAT")
      fi
    fi
  fi

  if [ -n "$SETUP_ARGOCD" ]; then
    if [ -z "${ARGOCD_MACHINE_USER:-}" ]; then
      missing_vars+=("ARGOCD_MACHINE_USER")
    fi
    if [ -z "${GITHUB_TOKEN:-}" ]; then
      missing_vars+=("GITHUB_TOKEN")
    fi
    if [ -z "${ARGOCD_MACHINE_EMAIL:-}" ]; then
      missing_vars+=("ARGOCD_MACHINE_EMAIL")
    fi
  fi

  if [ ${#missing_vars[@]} -gt 0 ]; then
    error "Missing required configuration variables: ${missing_vars[*]}"
    error "Please ensure all required variables are set in $CONFIG_FILE"
    exit 1
  fi

  # Set defaults
  REPOSITORY_VISIBILITY="${REPOSITORY_VISIBILITY:-private}"
  APP_DESCRIPTION="${APP_DESCRIPTION:-}"

  # Normalize GitHub org and app name: trim and force lowercase for string replacement and repo naming
  if [ -n "${GITHUB_ORG:-}" ]; then
    GITHUB_ORG=$(echo "$GITHUB_ORG" | xargs | tr '[:upper:]' '[:lower:]')
  fi
  if [ -n "${APP_NAME:-}" ]; then
    APP_NAME=$(echo "$APP_NAME" | xargs | tr '[:upper:]' '[:lower:]')
  fi

  info "Configuration loaded successfully"
}

# Check if git user.name and user.email are set (repo or global). Return 0 if both set, 1 otherwise.
check_git_profile() {
  local name
  local email
  name=$(git config user.name 2>/dev/null || true)
  email=$(git config user.email 2>/dev/null || true)
  if [ -z "$name" ] || [ -z "$email" ]; then
    return 1
  fi
  return 0
}

# Pre-flight checks based on command-line options. Emit warnings to stderr where requirements are not met.
run_preflight_checks() {
  local needs_git_profile=false

  if [ -n "$SETUP_ARGOCD" ]; then
    needs_git_profile=true
  fi
  if [ "$CREATE_APP" = true ] && [ "$NON_ESSESSEFF_SUBSCRIBER_MODE" = true ]; then
    needs_git_profile=true
  fi

  if [ "$needs_git_profile" = true ]; then
    if ! check_git_profile; then
      warning "A git profile (user.name and user.email) is required for the selected options."
      warning "setup-argocd.sh must run 'git commit' and 'git push'; the executor needs a git identity."
      warning "Set them with: git config [--global] user.name 'Your Name' and git config [--global] user.email 'you@example.com'"
    fi
  fi
}

# Make API request with rate limiting and error handling
api_request() {
  local method=$1
  local endpoint=$2
  local data="${3:-}"

  # Wait 4 seconds before each API call to respect rate limit (3 requests per 10 seconds)
  sleep 4

  local curl_args=(
    -s
    -L
    -w "\n%{http_code}"
    -X "$method"
    -H "X-API-Key: ${ESSESSEFF_API_KEY}"
    -H "User-Agent: essesseff-onboarding-utility/1.0"
  )

  if [ -n "$data" ]; then
    curl_args+=(-H "Content-Type: application/json")
    curl_args+=(-d "$data")
  fi

  curl_args+=("${ESSESSEFF_API_BASE_URL}${endpoint}")

  local response
  response=$(curl "${curl_args[@]}")

  local http_code
  http_code=$(echo "$response" | tail -n1)
  local body
  body=$(echo "$response" | sed '$d')

  # Handle rate limit errors (HTTP 429) with exponential backoff
  if [ "$http_code" -eq 429 ]; then
    warning "Rate limit exceeded, waiting 10 seconds before retry..."
    sleep 10
    # Retry the request (recursive call)
    local retry_response
    retry_response=$(api_request "$method" "$endpoint" "$data")
    echo "$retry_response"
    return
  fi

  if [ "$http_code" -ge 400 ]; then
    error "API request failed: HTTP $http_code"
    case "$http_code" in
      401) error "Check your API key (X-API-Key)." ;;
      403) error "Check your API key and account slug; you may not have access to this resource." ;;
      404) error "Resource not found. Check account slug, organization, and app name." ;;
      429) error "Rate limit exceeded. Wait and retry." ;;
      *)   [ -n "$body" ] && echo "$body" | head -20 >&2 ;;
    esac
    exit 1
  fi

  echo "$body"
}

# List templates from bundled JSON (non-subscriber mode only)
list_templates_bundled() {
  if [ ! -f "$BUNDLED_TEMPLATES_FILE" ]; then
    error "Bundled templates file not found: $BUNDLED_TEMPLATES_FILE"
    exit 1
  fi

  local templates
  templates=$(cat "$BUNDLED_TEMPLATES_FILE")
  if [ -n "$LANGUAGE" ]; then
    templates=$(echo "$templates" | jq -c --arg lang "$LANGUAGE" '[.[] | select(.language == $lang)]')
  else
    templates=$(echo "$templates" | jq -c '.')
  fi

  echo ""
  echo "Available Templates (bundled, non-essesseff-subscriber)${LANGUAGE:+ (${LANGUAGE})}:"
  echo ""
  printf "%-10s %-45s %-10s %s\n" "Type" "Name (template_org_login)" "Language" "Description"
  printf "%-10s %-45s %-10s %s\n" "----" "---------------------------" "--------" "-----------"
  echo "$templates" | jq -r '.[] | "Bundled    \(.name // "N/A")     \(.language // "N/A")       \(.description // "N/A")"' 2>/dev/null || true
  echo ""
  echo "Use TEMPLATE_NAME=<name> in .essesseff when running with --create-app --non-essesseff-subscriber-mode"
  echo ""
}

# List templates (global and account-specific) via API
list_templates() {
  info "Fetching templates..."

  local global_templates
  local account_templates
  local query_param=""

  if [ -n "$LANGUAGE" ]; then
    query_param="?language=${LANGUAGE}"
  fi

  # Fetch global templates
  info "Fetching global templates..."
  global_templates=$(api_request "GET" "/global/templates${query_param}")

  # Fetch account-specific templates
  info "Fetching account-specific templates..."
  account_templates=$(api_request "GET" "/accounts/${ESSESSEFF_ACCOUNT_SLUG}/templates${query_param}")

  # Parse and display templates
  echo ""
  echo "Available Templates${LANGUAGE:+ (${LANGUAGE})}:"
  echo ""
  printf "%-10s %-40s %-10s %s\n" "Type" "Name" "Language" "Description"
  printf "%-10s %-40s %-10s %s\n" "----" "----" "--------" "-----------"

  # Display global templates
  echo "$global_templates" | jq -r '.[] | "Global      \(.name // "N/A")                                    \(.language // "N/A")       \(.description // "N/A")"' 2>/dev/null || true

  # Display account-specific templates
  echo "$account_templates" | jq -r '.[] | "Account     \(.name // "N/A")                                    \(.language // "N/A")       \(.description // "N/A")"' 2>/dev/null || true

  echo ""
}

# Validate app name conforms to GitHub repository naming standards
validate_app_name() {
  local app_name=$1

  # Check if app name is empty
  if [ -z "$app_name" ]; then
    error "App name cannot be empty"
    return 1
  fi

  # Check if app name starts or ends with a dash
  if [[ "$app_name" =~ ^- ]] || [[ "$app_name" =~ -$ ]]; then
    error "App name cannot start or end with a dash: $app_name"
    return 1
  fi

  # Check if app name contains only lowercase letters, numbers, and dashes
  if ! [[ "$app_name" =~ ^[a-z0-9-]+$ ]]; then
    error "App name must contain only lowercase letters, numbers, and dashes: $app_name"
    return 1
  fi

  return 0
}

# Check if app already exists
check_app_exists() {
  local account_slug=$1
  local org_login=$2
  local app_name=$3

  info "Checking if app '$app_name' already exists..."

  # Use a separate function that doesn't exit on 404
  local endpoint="/accounts/${account_slug}/organizations/${org_login}/apps/${app_name}"
  
  sleep 4  # Rate limiting
  
  # Use curl with separate output files to reliably get HTTP code
  local temp_body
  temp_body=$(mktemp)
  
  if [ "$VERBOSE" = true ]; then
    info "API endpoint: ${ESSESSEFF_API_BASE_URL}${endpoint}"
    info "API key prefix: ${ESSESSEFF_API_KEY:0:10}..."
  fi

  # Debug: Show what we're sending
  if [ "$VERBOSE" = true ]; then
    info "Sending X-API-Key header: ${ESSESSEFF_API_KEY:0:10}..."
  fi

  local http_code
  http_code=$(curl -s -L -w "%{http_code}" -o "$temp_body" -X "GET" \
    -H "X-API-Key: ${ESSESSEFF_API_KEY}" \
    -H "User-Agent: essesseff-onboarding-utility/1.0" \
    "${ESSESSEFF_API_BASE_URL}${endpoint}")

  if [ "$VERBOSE" = true ]; then
    info "HTTP status code: $http_code"
    if [ "$http_code" -ge 400 ]; then
      info "Response body: $(cat "$temp_body" 2>/dev/null || echo 'N/A')"
    fi
  fi

  if [ "$http_code" = "404" ]; then
    info "App does not exist (404)"
    rm -f "$temp_body"
    return 1  # App does not exist
  elif [ "$http_code" -ge 400 ]; then
    error "Failed to check if app exists: HTTP $http_code"
    if [ -f "$temp_body" ]; then
      cat "$temp_body" >&2
    fi
    rm -f "$temp_body"
    exit 1
  fi

  info "App exists (HTTP $http_code)"
  rm -f "$temp_body"
  return 0  # App exists
}

# Fetch template details
fetch_template_details() {
  local template_name=$1
  local is_global=$2

  info "Fetching template details for '$template_name' (global: $is_global)..." >&2

  local endpoint
  if [ "$is_global" = "true" ]; then
    endpoint="/global/templates/${template_name}"
  else
    endpoint="/accounts/${ESSESSEFF_ACCOUNT_SLUG}/templates/${template_name}"
  fi

  local response
  response=$(api_request "GET" "$endpoint")

  echo "$response"
}

# Create essesseff app
create_app() {
  echo "==> Creating app '${APP_NAME}' in org '${GITHUB_ORG}' using template '${TEMPLATE_NAME}'..."

  # Validate app name
  if ! validate_app_name "$APP_NAME"; then
    exit 1
  fi

  # Check if app already exists
  if check_app_exists "$ESSESSEFF_ACCOUNT_SLUG" "$GITHUB_ORG" "$APP_NAME"; then
    error "App '$APP_NAME' already exists in organization '$GITHUB_ORG'"
    exit 1
  fi

  # Fetch template details
  local template_response
  template_response=$(fetch_template_details "$TEMPLATE_NAME" "$TEMPLATE_IS_GLOBAL")

  # Validate template response is valid JSON
  if ! echo "$template_response" | jq empty 2>/dev/null; then
    error "Invalid JSON response from template API"
    error "Response: $template_response"
    exit 1
  fi

  # Extract template information
  local template_org_login
  template_org_login=$(echo "$template_response" | jq -r '.template_org_login // empty')
  local source_template_repo
  source_template_repo=$(echo "$template_response" | jq -r '.source_template_repo // empty')
  local template_is_global
  template_is_global=$(echo "$template_response" | jq -r '.is_global_template // false')
  local template_language
  template_language=$(echo "$template_response" | jq -r '.language // empty')
  local replacement_string
  replacement_string=$(echo "$template_response" | jq -r '.replacement_string // empty')

  if [ -z "$template_org_login" ] || [ -z "$source_template_repo" ] || [ -z "$template_language" ]; then
    error "Failed to extract required template information"
    echo "Template response: $template_response" >&2
    exit 1
  fi

  # Build template JSON - conditionally include replacement_string
  local template_json
  if [ "$template_is_global" = "true" ]; then
    # Global templates: Do not include replacement_string (essesseff handles it automatically)
    template_json=$(jq -n \
      --arg org_login "$template_org_login" \
      --arg source_repo "$source_template_repo" \
      '{template_org_login: $org_login, source_template_repo: $source_repo, is_global_template: true}')
  else
    # Team-account-specific templates: Include replacement_string from template details
    if [ -z "$replacement_string" ]; then
      error "replacement_string is required for account-specific templates but was not found in template response"
      exit 1
    fi
    template_json=$(jq -n \
      --arg org_login "$template_org_login" \
      --arg source_repo "$source_template_repo" \
      --arg replacement "$replacement_string" \
      '{template_org_login: $org_login, source_template_repo: $source_repo, is_global_template: false, replacement_string: $replacement}')
  fi

  # Build request body
  local request_body
  request_body=$(jq -n \
    --argjson template "$template_json" \
    --arg language "$template_language" \
    --arg visibility "${REPOSITORY_VISIBILITY:-private}" \
    --arg description "${APP_DESCRIPTION:-}" \
    '{programming_language: $language, template: $template, repository_visibility: $visibility, description: $description}')

  # Create app via API
  info "Calling essesseff API to create app..."
  local response
  response=$(api_request "POST" "/accounts/${ESSESSEFF_ACCOUNT_SLUG}/organizations/${GITHUB_ORG}/apps?app_name=${APP_NAME}" "$request_body")

  # Check if creation was successful
  local success
  success=$(echo "$response" | jq -r '.success // false')
  if [ "$success" != "true" ]; then
    error "App creation failed: the API returned success=false or an error."
    local err_msg
    err_msg=$(echo "$response" | jq -r '.message // .error // "Check your API key and account slug."' 2>/dev/null || echo "Check your API key and account slug.")
    echo "$err_msg" >&2
    exit 1
  fi

  echo ""
  echo -e "${GREEN}✓ App '$APP_NAME' created successfully.${NC}"
  echo "Repositories:"
  local repos
  repos=$(echo "$response" | jq -r '.data.resultant_repos // {}')
  if echo "$repos" | jq -e 'length > 0' &>/dev/null; then
    echo "$repos" | jq -r 'to_entries[] | "  - \(.key): \(.value)"' 2>/dev/null || true
  else
    warning "Could not list repositories from response. Check the essesseff UI and GitHub org."
  fi
  echo ""
}

# Create app in non-essesseff-subscriber mode: clone templates, replace strings, create repos, push
create_app_non_subscriber() {
  echo "==> Creating app '${APP_NAME}' in org '${GITHUB_ORG}' using template '${TEMPLATE_NAME}' (non-subscriber mode)..."

  if ! validate_app_name "$APP_NAME"; then
    exit 1
  fi

  if [ ! -f "$BUNDLED_TEMPLATES_FILE" ]; then
    error "Bundled templates file not found: $BUNDLED_TEMPLATES_FILE"
    exit 1
  fi

  local template_json
  template_json=$(jq -c --arg name "$TEMPLATE_NAME" '.[] | select(.template_org_login == $name or .name == $name)' "$BUNDLED_TEMPLATES_FILE" | head -n1)
  if [ -z "$template_json" ]; then
    error "Template '$TEMPLATE_NAME' not found in bundled templates. Use --list-templates --non-essesseff-subscriber-mode to see available names."
    exit 1
  fi

  local template_org_login source_template_repo replacement_string
  template_org_login=$(echo "$template_json" | jq -r '.template_org_login')
  source_template_repo=$(echo "$template_json" | jq -r '.source_template_repo')
  replacement_string=$(echo "$template_json" | jq -r '.replacement_string')

  if [ -z "$template_org_login" ] || [ -z "$source_template_repo" ] || [ -z "$replacement_string" ]; then
    error "Bundled template missing required fields (template_org_login, source_template_repo, replacement_string)"
    exit 1
  fi

  # Clone to current working directory so you can inspect repos and debug replacement (no temp dir cleanup)
  local work_dir
  work_dir=$(pwd)

  local envs=(dev qa staging prod)
  local repo_names=("$source_template_repo")
  local target_repo_names=("$APP_NAME")
  for e in "${envs[@]}"; do
    repo_names+=("${replacement_string}-config-${e}")
    target_repo_names+=("${APP_NAME}-config-${e}")
  done
  for e in "${envs[@]}"; do
    repo_names+=("${replacement_string}-argocd-${e}")
    target_repo_names+=("${APP_NAME}-argocd-${e}")
  done

  local private_flag="true"
  [ "${REPOSITORY_VISIBILITY:-private}" = "public" ] && private_flag="false"

  # Phase 1: Create all repos (or ensure they exist) and capture GitHub repo IDs.
  # Argo CD app-of-apps need {{REPOSITORY_ID}} = the matching Helm config-env repo ID (see essesseff UX/API).
  local repo_ids=()
  local i=0
  for target_repo_name in "${target_repo_names[@]}"; do
    info "Creating repo ${GITHUB_ORG}/${target_repo_name}..."
    local create_http create_body create_attempt=1 create_max=3 create_delay=15
    while true; do
      local create_response
      create_response=$(curl -s -w "\n%{http_code}" -X POST \
        -H "Authorization: Bearer ${GITHUB_ORG_ADMIN_PAT}" \
        -H "Accept: application/vnd.github.v3+json" \
        -d "{\"name\":\"${target_repo_name}\",\"private\":${private_flag}}" \
        "https://api.github.com/orgs/${GITHUB_ORG}/repos")
      create_http=$(echo "$create_response" | tail -n1)
      create_body=$(echo "$create_response" | sed '$d')
      if [ "$create_http" -ge 200 ] && [ "$create_http" -lt 300 ]; then
        break
      fi
      if [ "$create_http" -ge 400 ]; then
        local already_exists
        already_exists=$(echo "$create_body" | jq -r 'if .message | test("name already exists"; "i") then "y" elif ((.errors // []) | map(.message | test("already exists"; "i")) | any) then "y" else "n" end' 2>/dev/null || echo "n")
        if [ "$already_exists" = "y" ]; then
          warning "Repository ${GITHUB_ORG}/${target_repo_name} already exists; will push to it"
          break
        fi
        if [ "$create_http" -ne 429 ] && [ "$create_http" -lt 500 ]; then
          error "Failed to create repo ${target_repo_name}: HTTP $create_http"
          echo "$create_body" | jq -r 'if .message then .message else . end' >&2
          exit 1
        fi
      fi
      if [ "$create_attempt" -ge "$create_max" ]; then
        error "Failed to create repo ${target_repo_name} after $create_max attempts: HTTP $create_http"
        exit 1
      fi
      warning "Create repo attempt $create_attempt/$create_max failed (HTTP $create_http), retrying in ${create_delay}s..."
      sleep "$create_delay"
      ((create_attempt++)) || true
    done

    local repo_id
    repo_id=$(echo "$create_body" | jq -r '.id // empty')
    if [ -z "$repo_id" ]; then
      local get_resp
      get_resp=$(curl -s -H "Authorization: Bearer ${GITHUB_ORG_ADMIN_PAT}" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/${GITHUB_ORG}/${target_repo_name}")
      repo_id=$(echo "$get_resp" | jq -r '.id // empty')
    fi
    if [ -z "$repo_id" ]; then
      error "Could not get GitHub repo ID for ${GITHUB_ORG}/${target_repo_name}"
      exit 1
    fi
    repo_ids+=("$repo_id")
    ((i++)) || true
  done

  # Phase 2: Clone, replace (with env-specific {{REPOSITORY_ID}} for argocd repos), commit, push.
  i=0
  for repo_name in "${repo_names[@]}"; do
    local target_repo_name="${target_repo_names[$i]}"
    info "Processing repo $repo_name -> $target_repo_name"

    local clone_url="https://github.com/${template_org_login}/${repo_name}.git"
    local clone_dir="${work_dir}/${repo_name}"

    if [ -d "$clone_dir" ]; then
      info "Removing existing $clone_dir for fresh clone..."
      rm -rf "$clone_dir"
    fi

    if ! retry_cmd 3 10 git clone "$clone_url" "$clone_dir"; then
      error "Failed to clone $clone_url after 3 attempts (check repo exists, is public, or try again later)"
      exit 1
    fi

    # Argo CD env repos (indices 5–8) get {{REPOSITORY_ID}} = matching Helm config-env repo ID (indices 1–4).
    local config_repo_id=""
    if [ "$i" -ge 5 ] && [ "$i" -le 8 ]; then
      config_repo_id="${repo_ids[$((i - 4))]}"
    fi

    cd "$clone_dir" || { error "Failed to cd to $clone_dir"; exit 1; }
    apply_replacements_and_rename "$template_org_login" "$GITHUB_ORG" "$replacement_string" "$APP_NAME" "$config_repo_id"
    git add -A
    git commit -m "Apply template string replacement: ${replacement_string} -> ${APP_NAME}, template org -> ${GITHUB_ORG}"
    cd "$work_dir" || { error "Failed to cd back to $work_dir"; exit 1; }

    local push_url="https://x-access-token:${GITHUB_ORG_ADMIN_PAT}@github.com/${GITHUB_ORG}/${target_repo_name}.git"
    cd "$clone_dir" || { error "Failed to cd to $clone_dir for push"; exit 1; }
    git remote add origin "$push_url" 2>/dev/null || git remote set-url origin "$push_url"
    local default_branch
    default_branch=$(git rev-parse --abbrev-ref HEAD)
    if ! retry_cmd 3 10 git push -u origin "$default_branch"; then
      error "Failed to push to ${GITHUB_ORG}/${target_repo_name} after 3 attempts"
      cd "$work_dir" || true
      exit 1
    fi
    cd "$work_dir" || { error "Failed to cd back to $work_dir"; exit 1; }

    echo -e "${GREEN}  ✓${NC} ${target_repo_name}"
    ((i++)) || true
  done

  echo ""
  echo -e "${GREEN}✓ App '$APP_NAME' created successfully in ${GITHUB_ORG} (non-essesseff-subscriber mode)!${NC}"
  echo ""
  echo "Repositories created and pushed:"
  for tr in "${target_repo_names[@]}"; do
    echo "  - ${GITHUB_ORG}/${tr}"
  done
  echo ""
  echo "Cloned directories left in current working directory (e.g. ${repo_names[0]}, ${replacement_string}-config-dev, ...) for inspection and debugging."
  echo ""
}

# String replacement and renames: same order and rules as essesseff UX/API (create-app flow).
# Optional 5th arg: GitHub repo ID for the matching Helm config-env repo; replaces {{REPOSITORY_ID}} in Argo CD app-of-apps (env-specific).
apply_replacements_and_rename() {
  local template_org=$1
  local target_org=$2
  local replacement_str=$3
  local app_name=$4
  local repository_id=${5:-}
  local placeholder='{{REPOSITORY_ID}}'
  local f path base newbase parent tmpfile

  # --- File contents: org, replacement_string, helloworld if hello-world, then {{REPOSITORY_ID}} if repository_id set ---
  while IFS= read -r -d '' f; do
    grep -Iq . "$f" 2>/dev/null || continue
    tmpfile=$(mktemp)
    exec 3>"$tmpfile"
    while IFS= read -r line || [ -n "$line" ]; do
      line="${line%$'\r'}"
      line="${line//${template_org}/${target_org}}"
      line="${line//${replacement_str}/${app_name}}"
      [ "$replacement_str" = "hello-world" ] && line="${line//helloworld/${app_name}}"
      [ -n "$repository_id" ] && line="${line//${placeholder}/${repository_id}}"
      printf '%s\n' "$line" >&3
    done < "$f"
    exec 3>&-
    mv "$tmpfile" "$f"
  done < <(find . -type f ! -path './.git/*' -print0)

  # --- File/dir renames: same order (org, then replacement_string, then helloworld if hello-world) ---
  while IFS= read -r -d '' path; do
    [ -e "$path" ] || continue
    base=$(basename "$path")
    newbase="${base//${template_org}/${target_org}}"
    newbase="${newbase//${replacement_str}/${app_name}}"
    [ "$replacement_str" = "hello-world" ] && newbase="${newbase//helloworld/${app_name}}"
    [ "$base" = "$newbase" ] && continue
    parent=$(dirname "$path")
    mv "$path" "${parent}/${newbase}"
  done < <(find . -depth ! -path './.git' ! -path '.' -print0)
}

# Main function
main() {
  parse_args "$@"
  read_config
  run_preflight_checks

  if [ "$LIST_TEMPLATES" = true ]; then
    if [ "$NON_ESSESSEFF_SUBSCRIBER_MODE" = true ]; then
      list_templates_bundled
    else
      list_templates
    fi
    exit 0
  fi

  if [ "$CREATE_APP" = true ]; then
    if [ "$NON_ESSESSEFF_SUBSCRIBER_MODE" = true ]; then
      create_app_non_subscriber
    else
      create_app
    fi
  fi

  if [ -n "$SETUP_ARGOCD" ]; then
    setup_argocd "$SETUP_ARGOCD"
  fi
}

# Setup Argo CD for specified environments
setup_argocd() {
  local environments=$1

  echo "==> Setting up Argo CD for environments: $environments"

  # Download notifications secret (subscriber only). In non-subscriber mode we do not provide one;
  # setup-argocd.sh detects missing notifications-secret.yaml and skips Argo CD Notifications setup.
  local notifications_secret_file=""
  if [ "$NON_ESSESSEFF_SUBSCRIBER_MODE" = false ]; then
    info "Downloading notifications-secret.yaml..."
    notifications_secret_file=$(mktemp)
    sleep 4  # Rate limiting
    local response
    response=$(curl -s -L -w "\n%{http_code}" -X "GET" \
      -H "X-API-Key: ${ESSESSEFF_API_KEY}" \
      -H "User-Agent: essesseff-onboarding-utility/1.0" \
      "${ESSESSEFF_API_BASE_URL}/accounts/${ESSESSEFF_ACCOUNT_SLUG}/organizations/${GITHUB_ORG}/apps/${APP_NAME}/notifications-secret")

    local http_code
    http_code=$(echo "$response" | tail -n1)
    local body
    body=$(echo "$response" | sed '$d')

    if [ "$http_code" -ge 400 ]; then
      error "Failed to download notifications-secret: HTTP $http_code"
      echo "$body" >&2
      exit 1
    fi

    echo "$body" > "$notifications_secret_file"
    info "Notifications secret downloaded to $notifications_secret_file"
  else
    info "Non-essesseff-subscriber mode: not providing notifications-secret.yaml; setup-argocd.sh will skip Argo CD Notifications setup."
  fi

  # Parse comma-separated environments
  IFS=',' read -ra ENV_ARRAY <<< "$environments"

  # Process each environment
  for env in "${ENV_ARRAY[@]}"; do
    env=$(echo "$env" | xargs)  # Trim whitespace
    if ! setup_argocd_environment "$env" "$notifications_secret_file"; then
      echo -e "${RED}==> Argo CD setup failed for '$env' (see above).${NC}" >&2
    fi
  done

  # If ARGOCD_INSTANCE_URL is set, register each environment's Argo CD application URL with essesseff via the API (subscriber only)
  if [ "$NON_ESSESSEFF_SUBSCRIBER_MODE" = false ] && [ -n "${ARGOCD_INSTANCE_URL:-}" ]; then
    ARGOCD_INSTANCE_URL=$(echo "$ARGOCD_INSTANCE_URL" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's:/$::')
    for env in "${ENV_ARRAY[@]}"; do
      env=$(echo "$env" | xargs)
      case "$env" in
        dev|qa|staging|prod)
          local env_upper
          env_upper=$(echo "$env" | tr '[:lower:]' '[:upper:]')
          local argocd_app_url="${ARGOCD_INSTANCE_URL}/applications/argocd/${APP_NAME}-${env}"
          info "Setting Argo CD application URL for $env_upper: $argocd_app_url"
          sleep 4
          local set_url_http
          local max_attempts=3
          local attempt=1
          while [ "$attempt" -le "$max_attempts" ]; do
            local set_url_response
            set_url_response=$(curl -s -L -w "\n%{http_code}" -X "POST" \
              -H "X-API-Key: ${ESSESSEFF_API_KEY}" \
              -H "User-Agent: essesseff-onboarding-utility/1.0" \
              -H "Content-Type: application/json" \
              -d "{\"url\":\"${argocd_app_url}\"}" \
              "${ESSESSEFF_API_BASE_URL}/accounts/${ESSESSEFF_ACCOUNT_SLUG}/organizations/${GITHUB_ORG}/apps/${APP_NAME}/environments/${env_upper}/set-argocd-application-url")
            set_url_http=$(echo "$set_url_response" | tail -n1)
            if [ "$set_url_http" -eq 429 ]; then
              if [ "$attempt" -lt "$max_attempts" ]; then
                warning "Rate limit exceeded, waiting 10 seconds before retry..."
                sleep 10
                attempt=$((attempt + 1))
              else
                warning "Failed to set Argo CD application URL for $env_upper: HTTP 429 (rate limit) after ${max_attempts} attempts"
                break
              fi
            elif [ "$set_url_http" -ge 400 ]; then
              warning "Failed to set Argo CD application URL for $env_upper: HTTP $set_url_http"
              break
            else
              info "Argo CD application URL set for $env_upper"
              break
            fi
          done
          ;;
        *)
          : ;; # skip invalid env (already validated earlier)
      esac
    done
  fi

  # Cleanup (only if we created a temp file)
  if [ -n "$notifications_secret_file" ] && [ -f "$notifications_secret_file" ]; then
    rm -f "$notifications_secret_file"
  fi

  echo ""
  echo -e "${GREEN}✓ Argo CD setup completed for all specified environments!${NC}"
  echo ""
  echo "Next steps:"
  echo "  - Verify setup via essesseff.com UI"
  echo "  - Check Argo CD UI for applications and sync status"
  echo "  - Confirm notifications are configured in Argo CD"
}

# Setup Argo CD for a single environment
setup_argocd_environment() {
  local env=$1
  local notifications_secret_file=$2
  local repo_name="${APP_NAME}-argocd-${env}"

  echo ""
  echo "==> Setting up Argo CD for environment '$env' (repo ${repo_name})..."

  # Validate environment name
  case "$env" in
    dev|qa|staging|prod)
      ;;
    *)
      warning "Invalid environment name: $env (must be one of: dev, qa, staging, prod)"
      return 1
      ;;
  esac

  # Use GITHUB_TOKEN (HTTPS) when set so clone works even if the account running the script lacks SSH access
  local repo_url
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    repo_url="https://x-access-token:${GITHUB_TOKEN}@github.com/${GITHUB_ORG}/${repo_name}.git"
  else
    repo_url="git@github.com:${GITHUB_ORG}/${repo_name}.git"
  fi

  # Clone repository if it doesn't exist locally
  if [ ! -d "$repo_name" ]; then
    info "Cloning repository: $repo_name"
    if ! git clone "$repo_url" "$repo_name" 2>/dev/null; then
      error "Could not clone ${repo_url}. Ensure your git credentials have access to this repository."
      return 1
    fi
  else
    info "Repository already exists locally: $repo_name"
  fi

  # Change to repository directory
  cd "$repo_name" || {
    error "Failed to change to repository directory: $repo_name"
    return 1
  }

  # Create .env file with only necessary variables
  info "Creating .env file..."
  cat > .env << EOF
# GitHub Machine User Credentials
ARGOCD_MACHINE_USER="${ARGOCD_MACHINE_USER}"
GITHUB_TOKEN="${GITHUB_TOKEN}"
ARGOCD_MACHINE_EMAIL="${ARGOCD_MACHINE_EMAIL}"

# Organization/App Config
GITHUB_ORG="${GITHUB_ORG}"
APP_NAME="${APP_NAME}"
ENVIRONMENT="${env}"
EOF

  # Copy notifications-secret.yaml (only when provided; in non-subscriber mode we do not provide it,
  # so setup-argocd.sh will see no file and skip Argo CD Notifications setup)
  if [ -n "$notifications_secret_file" ] && [ -f "$notifications_secret_file" ]; then
    info "Copying notifications-secret.yaml..."
    cp "$notifications_secret_file" ./notifications-secret.yaml
  else
    info "No notifications-secret.yaml provided; setup-argocd.sh will skip Argo CD Notifications setup."
  fi

  # Check if setup-argocd.sh exists
  if [ ! -f "setup-argocd.sh" ]; then
    error "setup-argocd.sh not found in repository: $repo_name"
    cd ..
    return 1
  fi

  # Make setup-argocd.sh executable
  chmod +x setup-argocd.sh

  # Verify kubectl is configured
  if ! command -v kubectl &> /dev/null; then
    error "kubectl is not installed or not in PATH"
    error "kubectl must be installed and configured before running the onboarding utility"
    cd ..
    return 1
  fi

  # Check kubectl connectivity
  if ! kubectl cluster-info &> /dev/null; then
    error "kubectl is not properly configured or cannot connect to cluster"
    error "Please configure kubectl for environment '$env' before running the onboarding utility"
    cd ..
    return 1
  fi

  # Execute setup-argocd.sh
  info "Executing setup-argocd.sh for environment: $env"
  local setup_exit=0
  ENVIRONMENT="$env" ./setup-argocd.sh || setup_exit=$?
  if [ "$setup_exit" -ne 0 ]; then
    error "setup-argocd.sh for environment '$env' failed (exit code ${setup_exit}). See the output above for details; common causes are missing git identity, no write access to the argocd-env repo, or missing cluster access."
    cd ..
    return 1
  fi

  echo -e "${GREEN}✓ Argo CD setup completed for '$env'.${NC}"

  # Return to previous directory
  cd ..
}

# Run main function
main "$@"

# Note: The trap will automatically display completion info on exit
