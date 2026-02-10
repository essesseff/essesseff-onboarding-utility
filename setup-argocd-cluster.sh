#!/bin/bash

# setup-argocd-cluster.sh

# One-time setup script for Argo CD and Argo CD Notifications on a Kubernetes cluster
# This should be run ONCE per cluster, before setting up any apps
# It installs Argo CD (if not already installed) and the Argo CD Notifications catalog

set -e

echo "=========================================="
echo "Argo CD Cluster Setup"
echo "=========================================="
echo ""
echo "This script will:"
echo "  1. Install Argo CD (if not already installed)"
echo "  2. Install the Argo CD Notifications catalog (triggers and templates)"
echo ""
echo "⚠️  WARNING: If a ConfigMap already exists, installing the catalog will OVERWRITE it!"
echo "   Make sure you don't have custom configurations you want to keep."
echo ""
read -p "Continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Aborted"
  exit 1
fi

# Step 1: Install Argo CD (idempotent)
echo ""
echo "=========================================="
echo "Step 1: Installing Argo CD"
echo "=========================================="
echo ""

# Check if Argo CD namespace exists
if kubectl get namespace argocd &> /dev/null; then
  echo "  ✓ Argo CD namespace already exists"
  
  # Check if Argo CD server is running
  if kubectl get deployment argocd-server -n argocd &> /dev/null; then
    echo "  ✓ Argo CD server deployment found"
    
    # Check if server is ready
    if kubectl get deployment argocd-server -n argocd -o jsonpath='{.status.readyReplicas}' | grep -q "1"; then
      echo "  ✓ Argo CD is already installed and running"
    else
      echo "  ⚠️  Argo CD server deployment exists but may not be ready"
      echo "     Waiting for Argo CD server to be ready..."
      kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd || {
        echo "  ✗ Argo CD server did not become ready in time"
        echo "     You may need to check the deployment status manually"
      }
    fi
  else
    echo "  ⚠️  Argo CD namespace exists but server deployment not found"
    echo "     Installing Argo CD..."
    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
    echo "  ✓ Argo CD installation manifest applied"
    echo "     Waiting for Argo CD server to be ready (this may take a few minutes)..."
    kubectl wait --for=condition=available --timeout=600s deployment/argocd-server -n argocd || {
      echo "  ⚠️  Argo CD server is installing but not ready yet"
      echo "     You can check status with: kubectl get pods -n argocd"
    }
  fi
else
  echo "  📥 Installing Argo CD..."
  
  # Create namespace
  kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
  echo "  ✓ Created argocd namespace"
  
  # Install Argo CD
  kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
  echo "  ✓ Argo CD installation manifest applied"
  
  echo ""
  echo "  ⏳ Waiting for Argo CD server to be ready (this may take 2-3 minutes)..."
  kubectl wait --for=condition=available --timeout=600s deployment/argocd-server -n argocd || {
    echo "  ⚠️  Argo CD server is installing but not ready yet"
    echo "     You can check status with: kubectl get pods -n argocd"
    echo "     The server may take a few more minutes to become available"
  }
  
  echo "  ✓ Argo CD installation complete"
fi

# Step 2: Install Argo CD Notifications catalog
echo ""
echo "=========================================="
echo "Step 2: Installing Argo CD Notifications Catalog"
echo "=========================================="
echo ""

# Check if ConfigMap already exists
if kubectl get configmap argocd-notifications-cm -n argocd &> /dev/null; then
  # Check if catalog is already installed
  if kubectl get configmap argocd-notifications-cm -n argocd -o yaml | grep -q "trigger.on-sync-succeeded:"; then
    echo ""
    echo "✓ Notifications catalog already installed"
    echo "  ConfigMap exists and contains catalog triggers"
    echo ""
    echo "If you need to reinstall, delete the ConfigMap first:"
    echo "  kubectl delete configmap argocd-notifications-cm -n argocd"
    exit 0
  else
    echo ""
    echo "⚠️  WARNING: ConfigMap exists but catalog triggers not detected"
    echo "   Installing catalog will OVERWRITE existing ConfigMap"
    echo ""
    read -p "   Continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      echo "Aborted"
      exit 1
    fi
  fi
fi

# Install the catalog
echo ""
echo "📥 Installing Argo CD Notifications catalog..."
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/notifications_catalog/install.yaml

# Add on-sync-started trigger (not included in catalog by default)
echo ""
if kubectl get configmap argocd-notifications-cm -n argocd -o yaml | grep -q "trigger.on-sync-started:"; then
  echo "  ✓ on-sync-started trigger already configured"
else
  echo "📝 Adding on-sync-started trigger (not in catalog by default)..."
  kubectl patch configmap argocd-notifications-cm -n argocd \
    --type merge \
    -p '{
      "data": {
        "trigger.on-sync-started": "|\n- description: Application sync has started\n  send:\n  - app-sync-status\n  when: app.status.operationState.phase in [\"Running\"] and app.status.operationState.operation.sync != nil"
      }
    }'
  echo "  ✓ on-sync-started trigger added"
fi

# Note: Argo CD Notifications controller uses default ConfigMap and Secret names
# by default: "argocd-notifications-cm" and "argocd-notifications-secret"
# These match what we're creating, so no deployment configuration needed

# Verify installation
echo ""
echo "✅ Verifying installation..."
if kubectl get configmap argocd-notifications-cm -n argocd -o yaml | grep -q "trigger.on-sync-succeeded:"; then
  echo "  ✓ Catalog installed successfully"
  echo ""
  echo "Available triggers:"
  kubectl get configmap argocd-notifications-cm -n argocd -o yaml | grep -E "^  trigger\." | sed 's/^  /    /'
else
  echo "  ✗ Installation may have failed - catalog triggers not found"
  exit 1
fi

echo ""
echo "=============================================="
echo "✅ Argo CD Cluster Setup Complete!"
echo "=============================================="
echo ""
echo "Argo CD Status:"
if kubectl get deployment argocd-server -n argocd &> /dev/null; then
  READY=$(kubectl get deployment argocd-server -n argocd -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
  DESIRED=$(kubectl get deployment argocd-server -n argocd -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "1")
  if [ "$READY" = "$DESIRED" ] && [ "$READY" != "0" ]; then
    echo "  ✓ Argo CD server is running ($READY/$DESIRED replicas ready)"
  else
    echo "  ⚠️  Argo CD server is installing ($READY/$DESIRED replicas ready)"
    echo "     Check status: kubectl get pods -n argocd"
  fi
else
  echo "  ⚠️  Argo CD server deployment not found"
fi

echo ""
echo "Notifications Status:"
if kubectl get configmap argocd-notifications-cm -n argocd &> /dev/null; then
  if kubectl get configmap argocd-notifications-cm -n argocd -o yaml | grep -q "trigger.on-sync-succeeded:"; then
    echo "  ✓ Notifications catalog installed"
    echo "  ✓ on-sync-started trigger configured"
  else
    echo "  ⚠️  ConfigMap exists but catalog may not be fully installed"
  fi
else
  echo "  ✗ Notifications catalog not found"
fi

echo ""
echo "Next steps:"
echo "  1. Get Argo CD admin password (if needed):"
echo "     kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath=\"{.data.password}\" | base64 -d"
echo ""
echo "  2. Port-forward to access Argo CD UI:"
echo "     kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "     Then access: https://localhost:8080 (username: admin)"
echo ""
echo "  3. Configure custom webhook services using kubectl patch --type merge"
echo "  4. Run app-specific setup scripts (setup-argocd.sh) for each app/environment"
