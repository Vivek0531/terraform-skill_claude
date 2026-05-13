#!/usr/bin/env bash
# prereqs.sh — install all tools needed to work with this repo locally
# Usage: bash scripts/prereqs.sh
set -euo pipefail

TERRAFORM_VERSION="1.9.0"
TERRAGRUNT_VERSION="0.67.0"
KUBECTL_VERSION="1.31.0"
HELM_VERSION="3.16.2"
AWSCLI_VERSION="2"

OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)
[[ "$ARCH" == "x86_64" ]] && ARCH="amd64"
[[ "$ARCH" == "aarch64" ]] && ARCH="arm64"

echo "==> Detected: ${OS}/${ARCH}"

# ── Helpers ────────────────────────────────────────────────────────────────
need() { command -v "$1" &>/dev/null; }
info() { echo -e "\033[0;32m[INFO]\033[0m $*"; }
warn() { echo -e "\033[0;33m[WARN]\033[0m $*"; }

# ── Homebrew (macOS) ───────────────────────────────────────────────────────
if [[ "$OS" == "darwin" ]] && ! need brew; then
  info "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# ── Terraform ─────────────────────────────────────────────────────────────
if need terraform && terraform version | grep -q "${TERRAFORM_VERSION}"; then
  info "Terraform ${TERRAFORM_VERSION} already installed"
else
  info "Installing Terraform ${TERRAFORM_VERSION}..."
  if [[ "$OS" == "darwin" ]]; then
    brew tap hashicorp/tap && brew install hashicorp/tap/terraform
  else
    curl -sLo /tmp/tf.zip \
      "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_${OS}_${ARCH}.zip"
    sudo unzip -o /tmp/tf.zip -d /usr/local/bin/
    rm /tmp/tf.zip
  fi
fi
terraform version

# ── Terragrunt ────────────────────────────────────────────────────────────
if need terragrunt && terragrunt --version | grep -q "${TERRAGRUNT_VERSION}"; then
  info "Terragrunt ${TERRAGRUNT_VERSION} already installed"
else
  info "Installing Terragrunt ${TERRAGRUNT_VERSION}..."
  if [[ "$OS" == "darwin" ]]; then
    brew install terragrunt
  else
    sudo curl -sLo /usr/local/bin/terragrunt \
      "https://github.com/gruntwork-io/terragrunt/releases/download/v${TERRAGRUNT_VERSION}/terragrunt_${OS}_${ARCH}"
    sudo chmod +x /usr/local/bin/terragrunt
  fi
fi
terragrunt --version

# ── AWS CLI v2 ────────────────────────────────────────────────────────────
if need aws; then
  info "AWS CLI already installed: $(aws --version)"
else
  info "Installing AWS CLI v${AWSCLI_VERSION}..."
  if [[ "$OS" == "darwin" ]]; then
    brew install awscli
  else
    curl -sLo /tmp/awscli.zip \
      "https://awscli.amazonaws.com/awscli-exe-linux-${ARCH/amd64/x86_64}.zip"
    unzip -o /tmp/awscli.zip -d /tmp/aws-install
    sudo /tmp/aws-install/aws/install --update
    rm -rf /tmp/awscli.zip /tmp/aws-install
  fi
fi
aws --version

# ── kubectl ───────────────────────────────────────────────────────────────
if need kubectl && kubectl version --client | grep -q "${KUBECTL_VERSION}"; then
  info "kubectl ${KUBECTL_VERSION} already installed"
else
  info "Installing kubectl ${KUBECTL_VERSION}..."
  if [[ "$OS" == "darwin" ]]; then
    brew install kubectl
  else
    sudo curl -sLo /usr/local/bin/kubectl \
      "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/${OS}/${ARCH}/kubectl"
    sudo chmod +x /usr/local/bin/kubectl
  fi
fi
kubectl version --client

# ── Helm ──────────────────────────────────────────────────────────────────
if need helm && helm version | grep -q "${HELM_VERSION}"; then
  info "Helm ${HELM_VERSION} already installed"
else
  info "Installing Helm ${HELM_VERSION}..."
  if [[ "$OS" == "darwin" ]]; then
    brew install helm
  else
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  fi
fi
helm version

# ── Helm repos ────────────────────────────────────────────────────────────
info "Adding Helm repositories..."
helm repo add bitnami              https://charts.bitnami.com/bitnami
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana              https://grafana.github.io/helm-charts
helm repo add fluent               https://fluent.github.io/helm-charts
helm repo update

# ── tflint ────────────────────────────────────────────────────────────────
if ! need tflint; then
  info "Installing tflint..."
  if [[ "$OS" == "darwin" ]]; then
    brew install tflint
  else
    curl -sLo /tmp/tflint.zip \
      "https://github.com/terraform-linters/tflint/releases/latest/download/tflint_${OS}_${ARCH}.zip"
    sudo unzip -o /tmp/tflint.zip -d /usr/local/bin/
    rm /tmp/tflint.zip
  fi
fi
tflint --version

# ── checkov (security scanning) ───────────────────────────────────────────
if ! need checkov; then
  info "Installing checkov..."
  pip3 install checkov 2>/dev/null || pip install checkov
fi
checkov --version

echo ""
info "All prerequisites installed successfully!"
echo ""
echo "Next steps:"
echo "  1. Configure AWS credentials: aws configure --profile payments-api"
echo "  2. Export profile:            export AWS_PROFILE=payments-api"
echo "  3. Run setup:                 bash scripts/bootstrap.sh"
