#!/bin/bash

# essesseff-onboard-wizard.sh
# Interactive wizard front-end for essesseff-onboard.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ONBOARD_SCRIPT="${SCRIPT_DIR}/essesseff-onboard.sh"
CONFIG_FILE=".essesseff"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

warn() {
  echo -e "${YELLOW}Warning:${NC} $1" >&2
}

error() {
  echo -e "${RED}Error:${NC} $1" >&2
}

info() {
  echo -e "${GREEN}Info:${NC} $1"
}

pause() {
  read -r -p "Press Enter to continue..." _
}

load_existing_config() {
  EXISTING_CONFIG=false
  if [ -f "$CONFIG_FILE" ]; then
    EXISTING_CONFIG=true
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
  fi
}

prompt_with_default() {
  local var_name=$1
  local prompt_label=$2
  local current_value=${!var_name:-}
  local secret=${3:-false}

  if [ -n "$current_value" ]; then
    if [ "$secret" = true ]; then
      echo "${prompt_label}: (current value is set; leave blank to keep)"
      read -r -s -p "> " input
      echo
    else
      echo "${prompt_label}: [${current_value}] (press Enter to keep, or type a new value)"
      read -r -p "> " input
    fi
    if [ -z "$input" ]; then
      printf -v "$var_name" '%s' "$current_value"
    else
      printf -v "$var_name" '%s' "$input"
    fi
  else
    if [ "$secret" = true ]; then
      echo "${prompt_label}:"
      read -r -s -p "> " input
      echo
    else
      echo "${prompt_label}:"
      read -r -p "> " input
    fi
    printf -v "$var_name" '%s' "$input"
  fi
}

validate_app_name() {
  local name=$1
  if [ -z "$name" ]; then
    error "App name cannot be empty."
    return 1
  fi
  if [[ "$name" =~ ^- ]] || [[ "$name" =~ -$ ]]; then
    error "App name cannot start or end with a dash."
    return 1
  fi
  if ! [[ "$name" =~ ^[a-z0-9-]+$ ]]; then
    error "App name must contain only lowercase letters, numbers, and dashes."
    return 1
  fi
  return 0
}

# Kubernetes namespace (DNS label) validation. Returns 0 if valid, 1 otherwise.
validate_k8s_namespace() {
  local ns="$1"
  if [ -z "$ns" ]; then
    error "Kubernetes namespace cannot be empty."
    return 1
  fi
  if [ "${#ns}" -gt 63 ]; then
    error "Kubernetes namespace must be at most 63 characters."
    return 1
  fi
  if ! [[ "$ns" =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ ]]; then
    error "Kubernetes namespace must contain only lowercase letters, numbers, and hyphens, and must start and end with a letter or number."
    return 1
  fi
  return 0
}

choose_mode() {
  echo "Are you an essesseff subscriber?"
  echo "  1) Yes, subscriber mode (use essesseff API)"
  echo "  2) No, non-subscriber mode (clone templates into my org)"
  local choice
  while true; do
    read -r -p "Select 1 or 2: " choice
    case "$choice" in
      1) NON_ESSESSEFF_SUBSCRIBER_MODE=false; break ;;
      2) NON_ESSESSEFF_SUBSCRIBER_MODE=true; break ;;
      *) echo "Please enter 1 or 2." ;;
    esac
  done
}

collect_core_config() {
  echo ""
  echo "=== Core Configuration ==="

  prompt_with_default "GITHUB_ORG" "GitHub organization login (GITHUB_ORG)"
  GITHUB_ORG=$(echo "$GITHUB_ORG" | xargs | tr '[:upper:]' '[:lower:]')

  while true; do
    prompt_with_default "APP_NAME" "essesseff app name (APP_NAME, lowercase letters/numbers/dashes only)"
    APP_NAME=$(echo "$APP_NAME" | xargs | tr '[:upper:]' '[:lower:]')
    if validate_app_name "$APP_NAME"; then
      break
    fi
  done

  echo "Kubernetes namespace (K8S_NAMESPACE, optional). If left blank, the target GitHub org will be used."
  prompt_with_default "K8S_NAMESPACE" "K8S_NAMESPACE (optional)"
  if [ -n "${K8S_NAMESPACE:-}" ]; then
    K8S_NAMESPACE=$(echo "$K8S_NAMESPACE" | xargs | tr '[:upper:]' '[:lower:]')
    while ! validate_k8s_namespace "$K8S_NAMESPACE"; do
      read -r -p "Enter a valid Kubernetes namespace (or leave blank to use GitHub org): " K8S_NAMESPACE
      K8S_NAMESPACE=$(echo "$K8S_NAMESPACE" | xargs | tr '[:upper:]' '[:lower:]')
      [ -z "$K8S_NAMESPACE" ] && break
    done
  fi

  if [ "${NON_ESSESSEFF_SUBSCRIBER_MODE:-false}" = false ]; then
    prompt_with_default "ESSESSEFF_API_KEY" "essesseff API key (ESSESSEFF_API_KEY)" true
    prompt_with_default "ESSESSEFF_ACCOUNT_SLUG" "essesseff account slug (ESSESSEFF_ACCOUNT_SLUG)"
  else
    prompt_with_default "GITHUB_ORG_ADMIN_PAT" "GitHub org admin PAT for create-app (GITHUB_ORG_ADMIN_PAT)" true
  fi
}

collect_template_config() {
  echo ""
  echo "=== Template Configuration ==="

  prompt_with_default "TEMPLATE_NAME" "Template name (TEMPLATE_NAME)"

  if [ "${NON_ESSESSEFF_SUBSCRIBER_MODE:-false}" = false ]; then
    # Subscriber: ask whether template is global
    local current="${TEMPLATE_IS_GLOBAL:-}"
    echo "Is this a global template? (TEMPLATE_IS_GLOBAL) [current: ${current:-unset}]"
    while true; do
      read -r -p "Enter 'true' or 'false' (press Enter to keep current): " input
      if [ -z "$input" ]; then
        if [ -n "$current" ]; then
          TEMPLATE_IS_GLOBAL="$current"
          break
        fi
      fi
      case "$input" in
        true|false) TEMPLATE_IS_GLOBAL="$input"; break ;;
        *) echo "Please enter 'true' or 'false', or press Enter to keep the current value." ;;
      esac
    done
  else
    echo "Non-subscriber mode: TEMPLATE_NAME must match the template org login (e.g. essesseff-hello-world-go-template)."
  fi
}

collect_argocd_config() {
  echo ""
  echo "=== Argo CD Setup ==="
  echo "Do you want to set up Argo CD now?"
  echo "  1) Yes, set up Argo CD for one or more environments"
  echo "  2) No, skip Argo CD setup"
  local choice
  while true; do
    read -r -p "Select 1 or 2: " choice
    case "$choice" in
      1) break ;;
      2) SETUP_ARGOCD_ENVS=""; return ;;
      *) echo "Please enter 1 or 2." ;;
    esac
  done

  while true; do
    local current="${SETUP_ARGOCD_ENVS:-}"
    if [ -n "$current" ]; then
      echo "Environments for --setup-argocd (dev,qa,staging,prod). Current: ${current}"
      read -r -p "Enter comma-separated envs, or press Enter to keep: " input
      if [ -z "$input" ]; then
        SETUP_ARGOCD_ENVS="$current"
      else
        SETUP_ARGOCD_ENVS="$input"
      fi
    else
      read -r -p "Enter comma-separated environments (e.g. dev,qa,staging,prod): " input
      SETUP_ARGOCD_ENVS="$input"
    fi

    # Basic validation
    local ok=true
    IFS=',' read -r -a envs <<< "$SETUP_ARGOCD_ENVS"
    for e in "${envs[@]}"; do
      e=$(echo "$e" | xargs)
      case "$e" in
        dev|qa|staging|prod) ;;
        *) error "Invalid environment: $e (must be one of dev, qa, staging, prod)"; ok=false ;;
      esac
    done
    if [ "$ok" = true ]; then
      break
    fi
  done

  echo ""
  echo "Argo CD machine user configuration (for --setup-argocd):"
  prompt_with_default "ARGOCD_MACHINE_USER" "ARGOCD_MACHINE_USER"
  prompt_with_default "GITHUB_TOKEN" "GITHUB_TOKEN (PAT for Argo CD machine user)" true
  prompt_with_default "ARGOCD_MACHINE_EMAIL" "ARGOCD_MACHINE_EMAIL"
}

write_config_file() {
  echo ""
  echo "Writing configuration to ${CONFIG_FILE}..."

  shell_quote() {
    # Produce a double-quoted, shell-safe string literal for bash assignments.
    # We escape backslashes and double quotes; values should not contain newlines.
    local s="${1:-}"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    printf '"%s"' "$s"
  }

  cat > "$CONFIG_FILE" <<EOF
ESSESSEFF_API_KEY=$(shell_quote "${ESSESSEFF_API_KEY:-}")
ESSESSEFF_ACCOUNT_SLUG=$(shell_quote "${ESSESSEFF_ACCOUNT_SLUG:-}")
NON_ESSESSEFF_SUBSCRIBER_MODE=$(shell_quote "${NON_ESSESSEFF_SUBSCRIBER_MODE:-false}")
GITHUB_ORG=$(shell_quote "${GITHUB_ORG:-}")
APP_NAME=$(shell_quote "${APP_NAME:-}")
K8S_NAMESPACE=$(shell_quote "${K8S_NAMESPACE:-}")
TEMPLATE_NAME=$(shell_quote "${TEMPLATE_NAME:-}")
TEMPLATE_IS_GLOBAL=$(shell_quote "${TEMPLATE_IS_GLOBAL:-}")
GITHUB_ORG_ADMIN_PAT=$(shell_quote "${GITHUB_ORG_ADMIN_PAT:-}")
ARGOCD_MACHINE_USER=$(shell_quote "${ARGOCD_MACHINE_USER:-}")
GITHUB_TOKEN=$(shell_quote "${GITHUB_TOKEN:-}")
ARGOCD_MACHINE_EMAIL=$(shell_quote "${ARGOCD_MACHINE_EMAIL:-}")
ESSESSEFF_API_BASE_URL=$(shell_quote "${ESSESSEFF_API_BASE_URL:-}")
APP_DESCRIPTION=$(shell_quote "${APP_DESCRIPTION:-}")
REPOSITORY_VISIBILITY=$(shell_quote "${REPOSITORY_VISIBILITY:-private}")
ARGOCD_INSTANCE_URL=$(shell_quote "${ARGOCD_INSTANCE_URL:-}")
EOF

  info "Configuration saved to ${CONFIG_FILE}"
}

show_summary() {
  echo ""
  echo "=== Summary ==="
  echo "Mode: $([ "${NON_ESSESSEFF_SUBSCRIBER_MODE:-false}" = true ] && echo "Non-subscriber" || echo "Subscriber")"
  echo "GitHub org: ${GITHUB_ORG:-<unset>}"
  echo "App name:   ${APP_NAME:-<unset>}"
  echo "Template:   ${TEMPLATE_NAME:-<unset>}"
  if [ "${NON_ESSESSEFF_SUBSCRIBER_MODE:-false}" = false ]; then
    echo "Template is global: ${TEMPLATE_IS_GLOBAL:-<unset>}"
  fi
  if [ -n "${SETUP_ARGOCD_ENVS:-}" ]; then
    echo "Argo CD envs: ${SETUP_ARGOCD_ENVS}"
  else
    echo "Argo CD:      not requested"
  fi
  echo "Config file:  ${CONFIG_FILE}"
}

run_or_print_command() {
  echo ""
  echo "How do you want to continue?"
  echo "  1) Run essesseff-onboard.sh now with this configuration"
  echo "  2) Do not run now; just print the command to run later"
  local choice
  while true; do
    read -r -p "Select 1 or 2: " choice
    case "$choice" in
      1) break ;;
      2) break ;;
      *) echo "Please enter 1 or 2." ;;
    esac
  done

  local cmd="./essesseff-onboard.sh"
  if [ -n "${SETUP_ARGOCD_ENVS:-}" ]; then
    cmd="$cmd --setup-argocd ${SETUP_ARGOCD_ENVS}"
  fi
  # Always create the app as part of the wizard flow.
  # In non-subscriber mode, creation is done via clone/replace/push.
  if [ "${NON_ESSESSEFF_SUBSCRIBER_MODE:-false}" = true ]; then
    cmd="$cmd --create-app --non-essesseff-subscriber-mode"
  else
    cmd="$cmd --create-app"
  fi
  cmd="$cmd --config-file ${CONFIG_FILE}"

  if [ "$choice" = "2" ]; then
    echo ""
    echo "You can run the onboarding utility later with:"
    echo "  $cmd"
    return
  fi

  echo ""
  echo "Running: $cmd"
  echo ""
  (cd "$SCRIPT_DIR" && eval "$cmd")
}

main() {
  if [ ! -x "$ONBOARD_SCRIPT" ]; then
    error "essesseff-onboard.sh not found or not executable at ${ONBOARD_SCRIPT}"
    exit 1
  fi

  echo ""
  echo "==============================================="
  echo " essesseff Onboarding Utility - Interactive Wizard"
  echo "==============================================="
  echo ""

  load_existing_config

  if [ "$EXISTING_CONFIG" = true ]; then
    echo "Found existing ${CONFIG_FILE}."
    echo "  1) Reuse and optionally update existing values"
    echo "  2) Ignore and start from a blank config"
    local choice
    while true; do
      read -r -p "Select 1 or 2: " choice
      case "$choice" in
        1) break ;;
        2) ESSESSEFF_API_KEY=""; ESSESSEFF_ACCOUNT_SLUG=""; NON_ESSESSEFF_SUBSCRIBER_MODE=false; GITHUB_ORG=""; APP_NAME=""; TEMPLATE_NAME=""; TEMPLATE_IS_GLOBAL=""; GITHUB_ORG_ADMIN_PAT=""; ARGOCD_MACHINE_USER=""; GITHUB_TOKEN=""; ARGOCD_MACHINE_EMAIL=""; SETUP_ARGOCD_ENVS=""; break ;;
        *) echo "Please enter 1 or 2." ;;
      esac
    done
  fi

  choose_mode
  collect_core_config
  collect_template_config
  collect_argocd_config
  write_config_file
  show_summary
  run_or_print_command
}

main "$@"

