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

# Print usage
usage() {
  cat << EOF
Usage: $0 [OPTIONS]

essesseff Onboarding Utility - Automates essesseff app creation and Argo CD setup

OPTIONS:
  --list-templates          List all available templates (global and account-specific)
  --language LANGUAGE       Filter templates by language (go, python, node, java)
  --create-app              Create a new essesseff app
  --setup-argocd ENVS       Comma-separated list of environments (dev,qa,staging,prod)
  --config-file FILE        Path to configuration file (default: .essesseff)
  --verbose                 Enable verbose output
  -h, --help                Show this help message

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
    error "Please create a .essesseff file or specify a different file with --config-file"
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

  if [ -z "${ESSESSEFF_API_KEY:-}" ]; then
    missing_vars+=("ESSESSEFF_API_KEY")
  else
    # Validate API key format (should start with "ess_" and be 36 characters)
    if ! [[ "${ESSESSEFF_API_KEY}" =~ ^ess_[a-zA-Z0-9]{32}$ ]]; then
      error "Invalid API key format. API key must start with 'ess_' and be 36 characters total."
      error "Current API key length: ${#ESSESSEFF_API_KEY} characters"
      error "API key starts with: ${ESSESSEFF_API_KEY:0:4}"
      exit 1
    fi
  fi

  if [ -z "${ESSESSEFF_ACCOUNT_SLUG:-}" ]; then
    missing_vars+=("ESSESSEFF_ACCOUNT_SLUG")
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
    if [ -z "${TEMPLATE_IS_GLOBAL:-}" ]; then
      missing_vars+=("TEMPLATE_IS_GLOBAL")
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

  info "Configuration loaded successfully"
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
    echo "$body" >&2
    exit 1
  fi

  echo "$body"
}

# List templates (global and account-specific)
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
  info "Creating essesseff app '$APP_NAME'..."

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
    error "Failed to create app"
    echo "$response" >&2
    exit 1
  fi

  echo ""
  echo -e "${GREEN}✓ App '$APP_NAME' created successfully!${NC}"
  echo ""
  echo "Repository names:"
  local repos
  repos=$(echo "$response" | jq -r '.data.resultant_repos // {}')
  echo "$repos" | jq -r 'to_entries[] | "  - \(.key): \(.value)"' 2>/dev/null || true
  echo ""
  echo "App creation completed. All repositories have been created and configured."
}

# Main function
main() {
  parse_args "$@"
  read_config

  if [ "$LIST_TEMPLATES" = true ]; then
    list_templates
    exit 0
  fi

  if [ "$CREATE_APP" = true ]; then
    create_app
  fi

  if [ -n "$SETUP_ARGOCD" ]; then
    setup_argocd "$SETUP_ARGOCD"
  fi
}

# Setup Argo CD for specified environments
setup_argocd() {
  local environments=$1

  info "Setting up Argo CD for environments: $environments"

  # Download notifications secret once (before processing environments)
  info "Downloading notifications-secret.yaml..."
  local notifications_secret_file
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

  # Parse comma-separated environments
  IFS=',' read -ra ENV_ARRAY <<< "$environments"

  # Process each environment
  for env in "${ENV_ARRAY[@]}"; do
    env=$(echo "$env" | xargs)  # Trim whitespace
    setup_argocd_environment "$env" "$notifications_secret_file"
  done

  # Cleanup
  rm -f "$notifications_secret_file"

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

  echo ""
  echo "Setting up Argo CD for environment: $env"

  # Validate environment name
  case "$env" in
    dev|qa|staging|prod)
      ;;
    *)
      warning "Invalid environment name: $env (must be one of: dev, qa, staging, prod)"
      return 1
      ;;
  esac

  local repo_name="${APP_NAME}-argocd-${env}"
  local repo_url="git@github.com:${GITHUB_ORG}/${repo_name}.git"

  # Clone repository if it doesn't exist locally
  if [ ! -d "$repo_name" ]; then
    info "Cloning repository: $repo_name"
    if ! git clone "$repo_url" "$repo_name" 2>/dev/null; then
      error "Failed to clone repository: $repo_name"
      error "Please ensure the repository exists and you have access to it"
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

  # Copy notifications-secret.yaml
  info "Copying notifications-secret.yaml..."
  cp "$notifications_secret_file" ./notifications-secret.yaml

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
  if ! ENVIRONMENT="$env" ./setup-argocd.sh; then
    error "setup-argocd.sh failed for environment: $env"
    cd ..
    return 1
  fi

  echo -e "${GREEN}✓ Argo CD setup completed for environment: $env${NC}"

  # Return to previous directory
  cd ..
}

# Run main function
main "$@"

# Note: The trap will automatically display completion info on exit
