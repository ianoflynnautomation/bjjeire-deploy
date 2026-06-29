#!/usr/bin/env bash

#
# deploy.sh - Deploy BJJ Application Helm charts to Kubernetes
#
# This script is part of the helm-charts repository and handles:
# - Kubernetes namespace creation
# - Secret management
# - Ingress controller setup
# - Helm chart deployment (MongoDB, API, Frontend)
#
# Usage:
#   ./deploy.sh [OPTIONS]
#
# Options:
#   --env <local|dev|prod>    Target environment (default: local)
#   --namespace <n>           Kubernetes namespace (default: bjjeire-app)
#   --skip-mongodb            Skip MongoDB deployment
#   --skip-api                Skip API deployment
#   --skip-frontend           Skip Frontend deployment
#   --skip-ingress            Skip Ingress controller setup
#   --skip-secrets            Skip secret creation
#   --image-tag <tag>         Override image tag for API/Frontend
#   --certs-dir <path>        Directory containing certificates
#   --dry-run                 Show what would be deployed without deploying
#

set -euo pipefail
IFS=$'\n\t'

# ==============================================================================
# Configuration Variables
# ==============================================================================

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
readonly CHARTS_ROOT_DIR="$(cd "${SCRIPT_DIR}/.." &>/dev/null && pwd)"

# Chart paths based on your directory structure
readonly MONGODB_CHART_PATH="${CHARTS_ROOT_DIR}/bjj-eire-mongodb"
readonly API_CHART_PATH="${CHARTS_ROOT_DIR}/bjj-eire-api/artifact"
readonly FRONTEND_CHART_PATH="${CHARTS_ROOT_DIR}/bjj-eire-web"

# Config paths for API
readonly API_CONFIG_DIR="${CHARTS_ROOT_DIR}/bjj-eire-api/config-artifact/config"

# Default values
ENVIRONMENT="local"
NAMESPACE="bjjeire-app"
SKIP_MONGODB=false
SKIP_API=false
SKIP_FRONTEND=false
SKIP_INGRESS=false
SKIP_SECRETS=false
IMAGE_TAG=""
DRY_RUN=false

# Attempt to find certs directory (assuming it's in parent directory or specified)
CERTS_DIR="${CHARTS_ROOT_DIR}/../certs/local-certs"

readonly INGRESS_NAMESPACE="ingress-nginx"

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# ==============================================================================
# Logging Functions
# ==============================================================================

log_info() {
  echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
  echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warning() {
  echo -e "${YELLOW}[WARNING]${NC} $*"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_section() {
  echo ""
  echo -e "${GREEN}===================================================================${NC}"
  echo -e "${GREEN}  $*${NC}"
  echo -e "${GREEN}===================================================================${NC}"
}

log_dry_run() {
  if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}[DRY-RUN]${NC} $*"
  fi
}

# ==============================================================================
# Utility Functions
# ==============================================================================

command_exists() {
  command -v "$1" &>/dev/null
}

show_usage() {
  cat << EOF
Usage: $(basename "$0") [OPTIONS]

Deploy BJJ Application Helm charts to Kubernetes

Options:
  --env <local|dev|prod>    Target environment (default: local)
  --namespace <n>           Kubernetes namespace (default: bjjeire-app)
  --skip-mongodb            Skip MongoDB deployment
  --skip-api                Skip API deployment
  --skip-frontend           Skip Frontend deployment
  --skip-ingress            Skip Ingress controller setup
  --skip-secrets            Skip secret creation
  --image-tag <tag>         Override image tag for API/Frontend
  --certs-dir <path>        Directory containing certificates
  --dry-run                 Show what would be deployed without deploying
  -h, --help                Show this help message

Examples:
  # Deploy everything to local environment
  $(basename "$0") --env local

  # Deploy only API and Frontend to dev environment
  $(basename "$0") --env dev --skip-mongodb --image-tag v1.2.3

  # Dry run for production with custom certs location
  $(basename "$0") --env prod --certs-dir /path/to/certs --dry-run

Directory Structure Expected:
  bjj-eire-deploy/
  ├── bjj-eire-mongodb/         (MongoDB chart)
  ├── bjj-eire-api/
  │   ├── artifact/             (API chart)
  │   └── config-artifact/config/ (Environment configs)
  ├── bjj-eire-web/             (Frontend chart)
  └── scripts/
      └── deploy.sh             (This script)

EOF
}

parse_arguments() {
  while [[ $# -gt 0 ]]; do
    case $1 in
      --env)
        ENVIRONMENT="$2"
        shift 2
        ;;
      --namespace)
        NAMESPACE="$2"
        shift 2
        ;;
      --skip-mongodb)
        SKIP_MONGODB=true
        shift
        ;;
      --skip-api)
        SKIP_API=true
        shift
        ;;
      --skip-frontend)
        SKIP_FRONTEND=true
        shift
        ;;
      --skip-ingress)
        SKIP_INGRESS=true
        shift
        ;;
      --skip-secrets)
        SKIP_SECRETS=true
        shift
        ;;
      --image-tag)
        IMAGE_TAG="$2"
        shift 2
        ;;
      --certs-dir)
        CERTS_DIR="$2"
        shift 2
        ;;
      --dry-run)
        DRY_RUN=true
        shift
        ;;
      -h|--help)
        show_usage
        exit 0
        ;;
      *)
        log_error "Unknown option: $1"
        show_usage
        exit 1
        ;;
    esac
  done
}

execute_or_dry_run() {
  if [ "$DRY_RUN" = true ]; then
    log_dry_run "$*"
    return 0
  else
    eval "$*"
  fi
}

# ==============================================================================
# Prerequisites
# ==============================================================================

check_prerequisites() {
  log_section "Checking Prerequisites"
  
  local missing_tools=()
  
  if ! command_exists kubectl; then
    missing_tools+=("kubectl")
  else
    local kubectl_version
    kubectl_version=$(kubectl version --client --short 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "unknown")
    log_success "kubectl found (version: $kubectl_version)"
  fi
  
  if ! command_exists helm; then
    missing_tools+=("Helm")
  else
    local helm_version
    helm_version=$(helm version --short 2>/dev/null || echo "unknown")
    log_success "Helm found (version: $helm_version)"
  fi
  
  if [ "$ENVIRONMENT" = "local" ] && ! command_exists minikube; then
    log_warning "Minikube not found. Assuming you're using a different local cluster."
  fi
  
  if [ ${#missing_tools[@]} -ne 0 ]; then
    log_error "Missing required tools: ${missing_tools[*]}"
    exit 1
  fi
  
  # Verify chart directories exist and check for Chart.yaml
  log_info "Verifying chart directories..."
  local charts_ok=true
  
  verify_chart_structure() {
    local chart_path=$1
    local chart_name=$2
    
    if [ ! -d "$chart_path" ]; then
      log_error "$chart_name chart directory not found: $chart_path"
      return 1
    fi
    
    # Check for Chart.yaml or Chart.yml
    if [ -f "$chart_path/Chart.yaml" ]; then
      log_success "$chart_name chart found: $chart_path (Chart.yaml ✓)"
      return 0
    elif [ -f "$chart_path/Chart.yml" ]; then
      log_error "$chart_name uses Chart.yml instead of Chart.yaml"
      log_error "  Helm requires 'Chart.yaml' (not .yml)"
      log_error "  Please rename: $chart_path/Chart.yml → Chart.yaml"
      return 1
    else
      log_error "$chart_name Chart.yaml not found in: $chart_path"
      log_error "  Expected: $chart_path/Chart.yaml"
      return 1
    fi
  }
  
  verify_chart_structure "$MONGODB_CHART_PATH" "MongoDB" || charts_ok=false
  verify_chart_structure "$API_CHART_PATH" "API" || charts_ok=false
  verify_chart_structure "$FRONTEND_CHART_PATH" "Frontend" || charts_ok=false
  
  if [ "$charts_ok" = false ]; then
    log_error ""
    log_error "Chart validation failed. Please fix the issues above."
    log_error ""
    log_error "Quick fix - run these commands:"
    echo "  cd $MONGODB_CHART_PATH && [ -f Chart.yml ] && mv Chart.yml Chart.yaml"
    echo "  cd $API_CHART_PATH && [ -f Chart.yml ] && mv Chart.yml Chart.yaml"
    echo "  cd $FRONTEND_CHART_PATH && [ -f Chart.yml ] && mv Chart.yml Chart.yaml"
    echo ""
    exit 1
  fi
  
  # Check if connected to a cluster
  if ! kubectl cluster-info &>/dev/null; then
    log_error "Not connected to a Kubernetes cluster"
    exit 1
  fi
  
  local current_context
  current_context=$(kubectl config current-context)
  log_info "Current context: $current_context"
  
  # Check for environment-specific configs
  local api_config_file="${API_CONFIG_DIR}/${ENVIRONMENT}ch"
  local mongodb_config_file="${MONGODB_CONFIG_DIR}/${ENVIRONMENT}ch"
  local frontend_config_file="${FRONTEND_CONFIG_DIR}/${ENVIRONMENT}ch"
  
  if [ "$ENVIRONMENT" != "local" ]; then
    if [ -f "$api_config_file" ]; then
      log_success "API config found: $api_config_file"
    else
      log_warning "API config file not found: $api_config_file"
    fi
    
    if [ -f "$mongodb_config_file" ]; then
      log_success "MongoDB config found: $mongodb_config_file"
    else
      log_warning "MongoDB config file not found: $mongodb_config_file"
    fi
    
    if [ -f "$frontend_config_file" ]; then
      log_success "Frontend config found: $frontend_config_file"
    else
      log_warning "Frontend config file not found: $frontend_config_file"
    fi
  fi
}

# ==============================================================================
# Minikube Setup (Local Only)
# ==============================================================================

setup_minikube() {
  if [ "$ENVIRONMENT" != "local" ]; then
    return 0
  fi
  
  if ! command_exists minikube; then
    log_info "Minikube not found, skipping Minikube-specific setup"
    return 0
  fi
  
  log_section "Minikube Setup"
  
  if ! minikube status &>/dev/null; then
    log_info "Starting Minikube..."
    if [ "$DRY_RUN" = true ]; then
      log_dry_run "minikube start --driver=docker --cpus=4 --memory=8192 --disk-size=20g"
    else
      minikube start --driver=docker --cpus=4 --memory=8192 --disk-size=20g
      log_success "Minikube started"
    fi
  else
    log_info "Minikube is already running"
  fi
  
  # Set context
  if [ "$DRY_RUN" = false ]; then
    kubectl config use-context minikube
  fi
  
  # Enable addons
  if [ "$DRY_RUN" = false ]; then
    log_info "Enabling Minikube addons..."
    minikube addons enable metrics-server 2>/dev/null || log_warning "Metrics-server addon already enabled"
  fi
}

# ==============================================================================
# Namespace Management
# ==============================================================================

ensure_namespace() {
  log_section "Namespace Setup"
  
  if kubectl get namespace "$NAMESPACE" &>/dev/null 2>&1; then
    log_info "Namespace '$NAMESPACE' already exists"
  else
    log_info "Creating namespace '$NAMESPACE'..."
    execute_or_dry_run "kubectl create namespace '$NAMESPACE'"
    
    if [ "$DRY_RUN" = false ]; then
      log_success "Namespace '$NAMESPACE' created"
    fi
  fi
  
  # Label the namespace
  execute_or_dry_run "kubectl label namespace '$NAMESPACE' name='$NAMESPACE' environment='$ENVIRONMENT' --overwrite"
}

# ==============================================================================
# Certificate Generation
# ==============================================================================

generate_self_signed_certificates() {
  log_section "Generating Self-Signed Certificates"
  
  if ! command_exists openssl; then
    log_error "OpenSSL not found. Cannot generate certificates."
    log_error "Please install OpenSSL or provide existing certificates."
    return 1
  fi
  
  log_info "Creating certificates directory: $CERTS_DIR"
  mkdir -p "$CERTS_DIR"
  
  cd "$CERTS_DIR"
  
  # Generate Frontend TLS certificate
  log_info "Generating Frontend TLS certificate..."
  openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout bjj-frontend.key \
    -out bjj-frontend.crt \
    -subj "/CN=app.bjj.local/O=BJJ App/C=IE" \
    2>/dev/null
  
  if [ $? -eq 0 ]; then
    log_success "Frontend certificate generated"
  else
    log_error "Failed to generate Frontend certificate"
    return 1
  fi
  
  # Generate API Kestrel certificate
  log_info "Generating API Kestrel certificate..."
  openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout bjj-api-kestrel.key \
    -out bjj-api-kestrel.crt \
    -subj "/CN=api.bjj.local/O=BJJ App/C=IE" \
    2>/dev/null
  
  if [ $? -ne 0 ]; then
    log_error "Failed to generate API certificate"
    return 1
  fi
  
  # Convert to PFX format
  log_info "Converting API certificate to PFX format..."
  openssl pkcs12 -export \
    -out bjj-api-kestrel.pfx \
    -inkey bjj-api-kestrel.key \
    -in bjj-api-kestrel.crt \
    -passout pass:securepassword123 \
    2>/dev/null
  
  if [ $? -eq 0 ]; then
    log_success "API certificate converted to PFX"
  else
    log_error "Failed to convert API certificate to PFX"
    return 1
  fi
  
  # Create password file
  echo -n "securepassword123" > bjj-api-kestrel-password.txt
  
  log_success "All certificates generated successfully in: $CERTS_DIR"
  
  # List generated files
  log_info "Generated certificate files:"
  ls -lh bjj-frontend.crt bjj-frontend.key bjj-api-kestrel.pfx bjj-api-kestrel-password.txt 2>/dev/null | awk '{print "  " $9 " (" $5 ")"}'
  
  return 0
}

# ==============================================================================
# Secret Management
# ==============================================================================

create_secrets() {
  if [ "$SKIP_SECRETS" = true ]; then
    log_info "Skipping secret creation (--skip-secrets specified)"
    return 0
  fi
  
  log_section "Creating Kubernetes Secrets"
  
  # MongoDB root password
  log_info "Creating MongoDB root password secret..."
  local mongodb_password
  if [ "$ENVIRONMENT" = "local" ]; then
    mongodb_password="securepassword123"
  else
    # In production, you should retrieve this from a secure vault
    log_warning "Using default password for MongoDB. In production, use a secure password from a vault!"
    mongodb_password="CHANGE_ME_IN_PRODUCTION"
  fi
  
  if [ "$DRY_RUN" = false ]; then
    kubectl create secret generic bjj-mongodb-root-password \
      --from-literal=mongodb-password="$mongodb_password" \
      --namespace "$NAMESPACE" \
      --dry-run=client -o yaml | kubectl apply -f -
    log_success "MongoDB password secret created"
  else
    log_dry_run "kubectl create secret generic bjj-mongodb-root-password --from-literal=mongodb-password='***' --namespace '$NAMESPACE'"
  fi
  
  # Certificate secrets (only for local environment)
  if [ "$ENVIRONMENT" = "local" ]; then
    # Check if certificates directory exists
    if [ ! -d "$CERTS_DIR" ]; then
      log_warning "Certificates directory not found: $CERTS_DIR"
      
      if [ "$DRY_RUN" = true ]; then
        log_info "Would generate self-signed certificates (dry-run mode)"
      else
        # Ask user if they want to generate certificates
        echo ""
        log_warning "TLS certificates are required for the application to start."
        echo ""
        read -p "Do you want to generate self-signed certificates now? (Y/n) " -n 1 -r
        echo ""
        
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
          if generate_self_signed_certificates; then
            log_success "Certificates generated successfully"
          else
            log_error "Failed to generate certificates"
            log_error "Please generate certificates manually or run with --skip-secrets"
            return 1
          fi
        else
          log_warning "Certificate generation skipped by user"
          log_warning "Secrets will not be created. Pods will fail to start."
          return 0
        fi
      fi
    fi
    
    # Verify all required certificate files exist
    local missing_certs=false
    local required_files=(
      "${CERTS_DIR}/bjj-frontend.crt"
      "${CERTS_DIR}/bjj-frontend.key"
      "${CERTS_DIR}/bjj-api-kestrel.pfx"
      "${CERTS_DIR}/bjj-api-kestrel-password.txt"
    )
    
    for cert_file in "${required_files[@]}"; do
      if [ ! -f "$cert_file" ]; then
        log_error "Required certificate file not found: $cert_file"
        missing_certs=true
      fi
    done
    
    if [ "$missing_certs" = true ]; then
      log_error "Missing certificate files. Cannot create secrets."
      return 1
    fi
    
    # Create Frontend TLS secret
    log_info "Creating Frontend TLS secret..."
    if [ "$DRY_RUN" = false ]; then
      kubectl create secret tls bjj-frontend-tls-secret \
        --cert="${CERTS_DIR}/bjj-frontend.crt" \
        --key="${CERTS_DIR}/bjj-frontend.key" \
        --namespace "$NAMESPACE" \
        --dry-run=client -o yaml | kubectl apply -f -
      log_success "Frontend TLS secret created"
    else
      log_dry_run "kubectl create secret tls bjj-frontend-tls-secret --cert='${CERTS_DIR}/bjj-frontend.crt' --key='${CERTS_DIR}/bjj-frontend.key'"
    fi
    
    # Create Ingress TLS secret (same as frontend)
    log_info "Creating Ingress TLS secret..."
    if [ "$DRY_RUN" = false ]; then
      kubectl create secret tls bjj-tls-secret \
        --cert="${CERTS_DIR}/bjj-frontend.crt" \
        --key="${CERTS_DIR}/bjj-frontend.key" \
        --namespace "$NAMESPACE" \
        --dry-run=client -o yaml | kubectl apply -f -
      log_success "Ingress TLS secret created"
    else
      log_dry_run "kubectl create secret tls bjj-tls-secret --cert='${CERTS_DIR}/bjj-frontend.crt' --key='${CERTS_DIR}/bjj-frontend.key'"
    fi
    
    # Create API Kestrel certificate secret
    log_info "Creating API Kestrel certificate secret..."
    if [ "$DRY_RUN" = false ]; then
      kubectl create secret generic bjj-api-kestrel-cert-secret \
        --from-file=aspnetapp.pfx="${CERTS_DIR}/bjj-api-kestrel.pfx" \
        --namespace "$NAMESPACE" \
        --dry-run=client -o yaml | kubectl apply -f -
      log_success "API Kestrel certificate secret created"
    else
      log_dry_run "kubectl create secret generic bjj-api-kestrel-cert-secret --from-file=aspnetapp.pfx='${CERTS_DIR}/bjj-api-kestrel.pfx'"
    fi
    
    # Create API Kestrel certificate password secret
    log_info "Creating API Kestrel certificate password secret..."
    if [ "$DRY_RUN" = false ]; then
      kubectl create secret generic bjj-api-kestrel-cert-password \
        --from-file=cert-password="${CERTS_DIR}/bjj-api-kestrel-password.txt" \
        --namespace "$NAMESPACE" \
        --dry-run=client -o yaml | kubectl apply -f -
      log_success "API Kestrel password secret created"
    else
      log_dry_run "kubectl create secret generic bjj-api-kestrel-cert-password --from-file=cert-password='${CERTS_DIR}/bjj-api-kestrel-password.txt'"
    fi
  fi
  
  if [ "$DRY_RUN" = false ]; then
    log_success "All secrets created successfully"
    
    # Show created secrets
    log_info "Verifying secrets in namespace '$NAMESPACE':"
    kubectl get secrets -n "$NAMESPACE" | grep -E "bjj-|NAME" || true
  fi
}

# ==============================================================================
# Ingress Controller
# ==============================================================================

deploy_ingress_controller() {
  if [ "$SKIP_INGRESS" = true ]; then
    log_info "Skipping Ingress controller setup (--skip-ingress specified)"
    return 0
  fi
  
  log_section "NGINX Ingress Controller Setup"
  
  # Create ingress namespace
  if ! kubectl get namespace "$INGRESS_NAMESPACE" &>/dev/null 2>&1; then
    execute_or_dry_run "kubectl create namespace '$INGRESS_NAMESPACE'"
  fi
  
  # Check if already installed
  local ingress_exists=false
  if helm list -n "$INGRESS_NAMESPACE" 2>/dev/null | grep -q "ingress-nginx"; then
    log_info "NGINX Ingress Controller already installed, upgrading..."
    ingress_exists=true
  else
    log_info "Installing NGINX Ingress Controller..."
  fi
  
  local helm_cmd="helm upgrade --install ingress-nginx ingress-nginx"
  helm_cmd+=" --repo https://kubernetes.github.io/ingress-nginx"
  helm_cmd+=" --namespace '$INGRESS_NAMESPACE'"
  
  if [ "$ENVIRONMENT" = "local" ]; then
    helm_cmd+=" --set controller.service.type=NodePort"
    helm_cmd+=" --set controller.service.nodePorts.http=30080"
    helm_cmd+=" --set controller.service.nodePorts.https=30443"
  fi
  
  helm_cmd+=" --set controller.admissionWebhooks.enabled=false"
  helm_cmd+=" --wait"
  helm_cmd+=" --timeout 5m"
  
  execute_or_dry_run "$helm_cmd"
  
  if [ "$DRY_RUN" = false ]; then
    # Wait for ingress controller to be ready
    log_info "Waiting for Ingress Controller to be ready..."
    kubectl wait --namespace "$INGRESS_NAMESPACE" \
      --for=condition=ready pod \
      --selector=app.kubernetes.io/component=controller \
      --timeout=300s || log_warning "Ingress controller pods may still be starting"
    
    log_success "NGINX Ingress Controller is ready"
  fi
}

# ==============================================================================
# Helm Chart Deployment
# ==============================================================================

get_values_file() {
  local service=$1
  local config_dir=""
  
  case "$service" in
    mongodb)
      config_dir="$MONGODB_CONFIG_DIR"
      ;;
    api)
      config_dir="$API_CONFIG_DIR"
      ;;
    frontend)
      config_dir="$FRONTEND_CONFIG_DIR"
      ;;
    *)
      echo ""
      return
      ;;
  esac
  
  local env_suffix
  case "$ENVIRONMENT" in
    prod)
      env_suffix="prodch"
      ;;
    test)
      env_suffix="testch"
      ;;
    uat)
      env_suffix="uatch"
      ;;
    local)
      # For local, use the default values.yaml in the chart
      echo ""
      return
      ;;
    *)
      log_warning "Unknown environment: $ENVIRONMENT, using default values"
      echo ""
      return
      ;;
  esac
  
  local values_file="${config_dir}/${env_suffix}"
  if [ -f "$values_file" ]; then
    echo "$values_file"
  else
    log_warning "Values file not found for $service: $values_file, using chart defaults"
    echo ""
  fi
}

get_api_values_file() {
  get_values_file "api"
}

get_mongodb_values_file() {
  get_values_file "mongodb"
}

get_frontend_values_file() {
  get_values_file "frontend"
}

deploy_helm_chart() {
  local chart_name=$1
  local chart_path=$2
  local release_name=$3
  local values_file=$4
  
  log_info "Deploying Helm chart: $chart_name"
  log_info "Chart path: $chart_path"
  log_info "Release name: $release_name"
  
  if [ ! -d "$chart_path" ]; then
    log_error "Chart directory not found: $chart_path"
    return 1
  fi
  
  local helm_cmd="helm upgrade --install '$release_name' '$chart_path'"
  helm_cmd+=" --namespace '$NAMESPACE'"
  helm_cmd+=" --create-namespace"
  
  # Add values file if specified
  if [ -n "$values_file" ] && [ -f "$values_file" ]; then
    log_info "Using values file: $values_file"
    helm_cmd+=" --values '$values_file'"
  else
    log_info "Using chart default values"
  fi
  
  # Override image tag if specified
  if [ -n "$IMAGE_TAG" ] && { [ "$chart_name" = "bjj-eire-api" ] || [ "$chart_name" = "bjj-eire-web" ]; }; then
    if [ "$chart_name" = "bjj-eire-api" ]; then
      helm_cmd+=" --set api.image.tag='$IMAGE_TAG'"
    elif [ "$chart_name" = "bjj-eire-web" ]; then
      helm_cmd+=" --set frontend.image.tag='$IMAGE_TAG'"
    fi
    log_info "Overriding image tag: $IMAGE_TAG"
  fi
  
  helm_cmd+=" --wait"
  helm_cmd+=" --timeout 5m"
  
  execute_or_dry_run "$helm_cmd"
  
  if [ $? -eq 0 ] || [ "$DRY_RUN" = true ]; then
    log_success "Successfully deployed: $chart_name"
    return 0
  else
    log_error "Failed to deploy: $chart_name"
    return 1
  fi
}

deploy_application_charts() {
  log_section "Deploying Application Helm Charts"
  
  local deployment_failed=0
  
  # Deploy MongoDB first
  if [ "$SKIP_MONGODB" = false ]; then
    log_info "Deploying MongoDB..."
    if ! deploy_helm_chart "bjj-eire-mongodb" "$MONGODB_CHART_PATH" "bjj-eire-mongodb" ""; then
      deployment_failed=1
    else
      if [ "$DRY_RUN" = false ]; then
        # Wait for MongoDB to be ready
        log_info "Waiting for MongoDB to be ready..."
        kubectl wait --namespace "$NAMESPACE" \
          --for=condition=ready pod \
          --selector=app.kubernetes.io/component=mongodb \
          --timeout=300s || log_warning "MongoDB pods not ready yet, but continuing..."
      fi
    fi
  else
    log_info "Skipping MongoDB deployment"
  fi
  
  # Deploy API
  if [ "$SKIP_API" = false ]; then
    log_info "Deploying API..."
    local api_values_file
    api_values_file=$(get_api_values_file)
    
    if ! deploy_helm_chart "bjj-eire-api" "$API_CHART_PATH" "bjj-eire-api" "$api_values_file"; then
      deployment_failed=1
    else
      if [ "$DRY_RUN" = false ]; then
        # Wait for API to be ready
        log_info "Waiting for API to be ready..."
        kubectl wait --namespace "$NAMESPACE" \
          --for=condition=ready pod \
          --selector=app.kubernetes.io/component=api \
          --timeout=300s || log_warning "API pods not ready yet, but continuing..."
      fi
    fi
  else
    log_info "Skipping API deployment"
  fi
  
  # Deploy Frontend
  if [ "$SKIP_FRONTEND" = false ]; then
    log_info "Deploying Frontend..."
    if ! deploy_helm_chart "bjj-eire-web" "$FRONTEND_CHART_PATH" "bjj-eire-web" ""; then
      deployment_failed=1
    else
      if [ "$DRY_RUN" = false ]; then
        # Wait for Frontend to be ready
        log_info "Waiting for Frontend to be ready..."
        kubectl wait --namespace "$NAMESPACE" \
          --for=condition=ready pod \
          --selector=app.kubernetes.io/component=frontend \
          --timeout=300s || log_warning "Frontend pods not ready yet, but continuing..."
      fi
    fi
  else
    log_info "Skipping Frontend deployment"
  fi
  
  if [ $deployment_failed -eq 1 ]; then
    log_error "One or more charts failed to deploy"
    exit 1
  fi
  
  log_success "All application charts deployed successfully"
}

# ==============================================================================
# DNS Configuration (Local Only)
# ==============================================================================

update_hosts_file() {
  if [ "$ENVIRONMENT" != "local" ] || [ "$DRY_RUN" = true ]; then
    return 0
  fi
  
  if ! command_exists minikube; then
    log_info "Minikube not available, skipping hosts file update"
    return 0
  fi
  
  log_section "Configuring Local DNS"
  
  local minikube_ip
  minikube_ip=$(minikube ip 2>/dev/null)
  
  if [ -z "$minikube_ip" ]; then
    log_error "Could not determine Minikube IP"
    return 1
  fi
  
  log_info "Minikube IP: $minikube_ip"
  
  local hosts_file="/etc/hosts"
  local api_host="api.bjj.local"
  local app_host="app.bjj.local"
  
  # Function to add or update host entry
  add_or_update_host() {
    local ip=$1
    local host=$2
    
    if grep -q "[[:space:]]${host}$" "$hosts_file" 2>/dev/null; then
      log_info "Updating existing entry for $host..."
      if [[ "$OSTYPE" == "darwin"* ]]; then
        sudo sed -i '' "/[[:space:]]${host}$/d" "$hosts_file"
      else
        sudo sed -i "/[[:space:]]${host}$/d" "$hosts_file"
      fi
    else
      log_info "Adding new entry for $host..."
    fi
    
    echo "$ip $host" | sudo tee -a "$hosts_file" > /dev/null
    log_success "Host entry configured: $ip $host"
  }
  
  add_or_update_host "$minikube_ip" "$api_host"
  add_or_update_host "$minikube_ip" "$app_host"
  
  log_success "DNS configuration complete"
}

# ==============================================================================
# Deployment Summary
# ==============================================================================

print_deployment_summary() {
  log_section "Deployment Summary"
  
  echo ""
  if [ "$DRY_RUN" = true ]; then
    log_warning "DRY RUN COMPLETED - No actual changes were made"
    echo ""
  else
    log_success "BJJ Application deployed successfully!"
    echo ""
  fi
  
  echo "Configuration:"
  echo "  Environment:  $ENVIRONMENT"
  echo "  Namespace:    $NAMESPACE"
  if [ -n "$IMAGE_TAG" ]; then
    echo "  Image Tag:    $IMAGE_TAG"
  fi
  echo ""
  
  if [ "$ENVIRONMENT" = "local" ]; then
    echo "Access your application:"
    echo "  Frontend: https://app.bjj.local:30443"
    echo "  API:      https://api.bjj.local:30443"
    echo ""
  fi
  
  echo "Deployed components:"
  [ "$SKIP_MONGODB" = false ] && echo "  ✓ MongoDB"
  [ "$SKIP_API" = false ] && echo "  ✓ API"
  [ "$SKIP_FRONTEND" = false ] && echo "  ✓ Frontend"
  [ "$SKIP_INGRESS" = false ] && echo "  ✓ Ingress Controller"
  echo ""
  
  echo "Useful commands:"
  echo "  View pods:        kubectl get pods -n $NAMESPACE"
  echo "  View services:    kubectl get svc -n $NAMESPACE"
  echo "  View ingresses:   kubectl get ingress -n $NAMESPACE"
  echo "  View logs (API):  kubectl logs -n $NAMESPACE -l app.kubernetes.io/component=api -f"
  echo "  View logs (FE):   kubectl logs -n $NAMESPACE -l app.kubernetes.io/component=frontend -f"
  echo "  View logs (DB):   kubectl logs -n $NAMESPACE -l app.kubernetes.io/component=mongodb -f"
  echo ""
  
  if [ "$ENVIRONMENT" = "local" ] && command_exists minikube; then
    echo "Minikube commands:"
    echo "  Dashboard:        minikube dashboard"
    echo "  Stop cluster:     minikube stop"
    echo "  Delete cluster:   minikube delete"
    echo ""
  fi
}

# ==============================================================================
# Main Execution
# ==============================================================================

main() {
  parse_arguments "$@"
  
  log_section "BJJ Application - Kubernetes Deployment"
  
  echo "Deploy script location: $SCRIPT_DIR"
  echo "Charts root directory: $CHARTS_ROOT_DIR"
  echo ""
  
  check_prerequisites
  setup_minikube
  ensure_namespace
  create_secrets
  deploy_ingress_controller
  deploy_application_charts
  update_hosts_file
  print_deployment_summary
  
  if [ "$DRY_RUN" = false ]; then
    log_success "Deployment completed successfully!"
  else
    log_info "Dry run completed. Run without --dry-run to actually deploy."
  fi
}

main "$@"