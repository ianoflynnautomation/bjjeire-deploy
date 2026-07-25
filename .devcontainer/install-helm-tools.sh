set -euo pipefail

KUBECONFORM_VERSION="${KUBECONFORM_VERSION:-v0.7.0}"
HELM_DOCS_VERSION="${HELM_DOCS_VERSION:-v1.14.2}"
CHART_TESTING_VERSION="${CHART_TESTING_VERSION:-v3.13.0}"
KUSTOMIZE_VERSION="${KUSTOMIZE_VERSION:-v5.5.0}"
YQ_VERSION="${YQ_VERSION:-v4.44.5}"
K9S_VERSION="${K9S_VERSION:-v0.32.7}"
FLUX_VERSION="${FLUX_VERSION:-2.4.0}"

HELM_DIFF_VERSION="${HELM_DIFF_VERSION:-v3.9.14}"
HELM_UNITTEST_VERSION="${HELM_UNITTEST_VERSION:-v0.7.2}"

BIN_DIR="/usr/local/bin"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

for d in "${HOME}/.kube" "${HOME}/.azure" "${HOME}/.minikube"; do
  [ -d "$d" ] && sudo chown -R "$(id -u):$(id -g)" "$d" || true
done

case "$(uname -m)" in
  x86_64 | amd64) ARCH="amd64" ;;
  aarch64 | arm64) ARCH="arm64" ;;
  *) echo "Unsupported arch: $(uname -m)" >&2; exit 1 ;;
esac
OS="linux"

echo "==> Installing Helm chart-dev toolchain (${OS}/${ARCH})"

dl() { curl -fsSL --retry 3 "$1" -o "$2"; }

# --- kubeconform ------------------------------------------------------------
if ! command -v kubeconform >/dev/null; then
  echo "--> kubeconform ${KUBECONFORM_VERSION}"
  dl "https://github.com/yannh/kubeconform/releases/download/${KUBECONFORM_VERSION}/kubeconform-${OS}-${ARCH}.tar.gz" "${TMP_DIR}/kubeconform.tgz"
  tar -xzf "${TMP_DIR}/kubeconform.tgz" -C "${TMP_DIR}" kubeconform
  sudo install -m 0755 "${TMP_DIR}/kubeconform" "${BIN_DIR}/kubeconform"
fi

# --- helm-docs --------------------------------------------------------------
if ! command -v helm-docs >/dev/null; then
  echo "--> helm-docs ${HELM_DOCS_VERSION}"
  # release assets use capitalized OS/arch names
  case "${ARCH}" in amd64) HD_ARCH="x86_64" ;; arm64) HD_ARCH="arm64" ;; esac
  dl "https://github.com/norwoodj/helm-docs/releases/download/${HELM_DOCS_VERSION}/helm-docs_${HELM_DOCS_VERSION#v}_Linux_${HD_ARCH}.tar.gz" "${TMP_DIR}/helm-docs.tgz"
  tar -xzf "${TMP_DIR}/helm-docs.tgz" -C "${TMP_DIR}" helm-docs
  sudo install -m 0755 "${TMP_DIR}/helm-docs" "${BIN_DIR}/helm-docs"
fi

# --- chart-testing (ct) + its Python deps -----------------------------------
if ! command -v ct >/dev/null; then
  echo "--> chart-testing ${CHART_TESTING_VERSION}"
  dl "https://github.com/helm/chart-testing/releases/download/${CHART_TESTING_VERSION}/chart-testing_${CHART_TESTING_VERSION#v}_linux_${ARCH}.tar.gz" "${TMP_DIR}/ct.tgz"
  mkdir -p "${TMP_DIR}/ct"
  tar -xzf "${TMP_DIR}/ct.tgz" -C "${TMP_DIR}/ct"
  sudo install -m 0755 "${TMP_DIR}/ct/ct" "${BIN_DIR}/ct"
  sudo mkdir -p /etc/ct
  sudo cp -r "${TMP_DIR}/ct/etc/." /etc/ct/ 2>/dev/null || true
  # ct's `lint` uses yamllint + yamale
  pipx install yamllint 2>/dev/null || pip3 install --user --quiet yamllint || true
  pipx install yamale 2>/dev/null || pip3 install --user --quiet yamale || true
fi

# --- kustomize --------------------------------------------------------------
if ! command -v kustomize >/dev/null; then
  echo "--> kustomize ${KUSTOMIZE_VERSION}"
  dl "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2F${KUSTOMIZE_VERSION}/kustomize_${KUSTOMIZE_VERSION}_${OS}_${ARCH}.tar.gz" "${TMP_DIR}/kustomize.tgz"
  tar -xzf "${TMP_DIR}/kustomize.tgz" -C "${TMP_DIR}" kustomize
  sudo install -m 0755 "${TMP_DIR}/kustomize" "${BIN_DIR}/kustomize"
fi

# --- yq ---------------------------------------------------------------------
if ! command -v yq >/dev/null; then
  echo "--> yq ${YQ_VERSION}"
  dl "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_${OS}_${ARCH}" "${TMP_DIR}/yq"
  sudo install -m 0755 "${TMP_DIR}/yq" "${BIN_DIR}/yq"
fi

# --- k9s --------------------------------------------------------------------
if ! command -v k9s >/dev/null; then
  echo "--> k9s ${K9S_VERSION}"
  dl "https://github.com/derailed/k9s/releases/download/${K9S_VERSION}/k9s_Linux_${ARCH}.tar.gz" "${TMP_DIR}/k9s.tgz"
  tar -xzf "${TMP_DIR}/k9s.tgz" -C "${TMP_DIR}" k9s
  sudo install -m 0755 "${TMP_DIR}/k9s" "${BIN_DIR}/k9s"
fi

# --- kubelogin (AKS + Entra ID) ---------------------------------------------
# The Azure CLI ships an installer that fetches a matching kubelogin build.
if ! command -v kubelogin >/dev/null; then
  echo "--> kubelogin (via az aks install-cli)"
  # Send the bundled kubectl to a throwaway path so we keep the feature's kubectl;
  # we only want kubelogin on PATH.
  az aks install-cli --install-location "${TMP_DIR}/kubectl-unused" \
    --kubelogin-install-location "${BIN_DIR}/kubelogin" >/dev/null 2>&1 \
    || echo "    (kubelogin install skipped — run 'az aks install-cli' after 'az login')"
fi

# --- Flux CLI (GitOps) ------------------------------------------------------
if ! command -v flux >/dev/null; then
  echo "--> flux ${FLUX_VERSION}"
  curl -fsSL https://fluxcd.io/install.sh | sudo FLUX_VERSION="${FLUX_VERSION}" bash >/dev/null 2>&1 \
    || echo "    (flux install skipped)"
fi

# --- Helm plugins (installed into the vscode user's HOME) --------------------
echo "==> Installing Helm plugins"
install_plugin() {
  local name="$1" url="$2" ver="$3"
  if ! helm plugin list 2>/dev/null | grep -q "^${name}\b"; then
    helm plugin install "${url}" --version "${ver}" 2>/dev/null \
      || echo "    (helm-${name} install skipped)"
  fi
}
install_plugin "diff"     "https://github.com/databus23/helm-diff"       "${HELM_DIFF_VERSION}"
install_plugin "unittest" "https://github.com/helm-unittest/helm-unittest" "${HELM_UNITTEST_VERSION}"

echo "==> Helm chart-dev toolchain ready."
