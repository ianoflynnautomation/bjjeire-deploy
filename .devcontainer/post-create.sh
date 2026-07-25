
#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# post-create.sh
#
# Runs once after the container is created (postCreateCommand). Wires up Helm
# repos used by this project, builds the umbrella chart's dependencies, and
# prints a version summary + quick-start cheatsheet.
# ---------------------------------------------------------------------------
set -euo pipefail

echo "==> Configuring Helm repositories"
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx >/dev/null 2>&1 || true
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
helm repo add bitnami https://charts.bitnami.com/bitnami >/dev/null 2>&1 || true
helm repo update >/dev/null 2>&1 || true

# Build the umbrella chart's local subchart dependencies so `helm template`
# and `helm lint` work immediately in a fresh clone.
if [ -f "bjj-eire/artifact/Chart.yaml" ]; then
  echo "==> Building umbrella chart dependencies"
  helm dependency build bjj-eire/artifact >/dev/null 2>&1 \
    || echo "    (helm dependency build skipped — run it manually if needed)"
fi

# Enable shell completions for the interactive terminal.
{
  echo 'source <(kubectl completion zsh) 2>/dev/null || true'
  echo 'source <(helm completion zsh) 2>/dev/null || true'
  echo 'alias k=kubectl'
  echo 'complete -F __start_kubectl k 2>/dev/null || true'
} >> "${HOME}/.zshrc" 2>/dev/null || true

echo ""
echo "==> Installed tool versions"
printf '  %-12s %s\n' "kubectl"     "$(kubectl version --client -o yaml 2>/dev/null | grep gitVersion | head -1 | awk '{print $2}')"
printf '  %-12s %s\n' "helm"        "$(helm version --short 2>/dev/null)"
printf '  %-12s %s\n' "minikube"    "$(minikube version --short 2>/dev/null)"
printf '  %-12s %s\n' "kind"        "$(kind version 2>/dev/null | awk '{print $2}')"
printf '  %-12s %s\n' "az"          "$(az version --query '\"azure-cli\"' -o tsv 2>/dev/null)"
printf '  %-12s %s\n' "kubeconform" "$(kubeconform -v 2>/dev/null)"
printf '  %-12s %s\n' "helm-docs"   "$(helm-docs --version 2>/dev/null | awk '{print $3}')"
printf '  %-12s %s\n' "ct"          "$(ct version 2>/dev/null | grep Version | head -1 | awk '{print $2}')"
printf '  %-12s %s\n' "kustomize"   "$(kustomize version 2>/dev/null)"
printf '  %-12s %s\n' "yq"          "$(yq --version 2>/dev/null | awk '{print $NF}')"
printf '  %-12s %s\n' "kubelogin"   "$(kubelogin --version 2>/dev/null | grep -o 'v[0-9.]*' | head -1)"
printf '  %-12s %s\n' "terraform"   "$(terraform version 2>/dev/null | head -1 | awk '{print $2}')"
printf '  %-12s %s\n' "tflint"      "$(tflint --version 2>/dev/null | head -1 | awk '{print $3}')"
printf '  %-12s %s\n' "flux"        "$(flux version --client 2>/dev/null | awk '{print $2}')"

cat <<'EOF'

============================================================================
 BJJ Eire Helm dev container is ready.

 Local cluster (minikube):
   minikube start --driver=docker --cpus=4 --memory=8192
   ./scripts/deploy.sh --env local

 Local cluster (kind):
   kind create cluster --name bjj-eire

 Remote AKS:
   az login
   az aks get-credentials -g <resource-group> -n <cluster-name>
   kubelogin convert-kubeconfig -l azurecli   # Entra ID auth for kubectl
   kubectl config use-context <aks-context>

 Chart workflow:
   helm dependency build bjj-eire/artifact
   helm lint bjj-eire/artifact
   helm template bjj-eire bjj-eire/artifact -f bjj-eire/artifact/values-dev.yaml | kubeconform -strict -summary
   ct lint --charts bjj-eire/artifact
   helm unittest bjj-eire/artifact
   helm-docs                     # regenerate chart README docs

 Switch contexts fast:  kubectl config get-contexts / use-context <name>
 Explore the cluster:   k9s
============================================================================
EOF
