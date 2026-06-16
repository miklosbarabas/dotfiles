#!/usr/bin/env bash

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
APT_UPDATED=0

if [[ ${EUID} -eq 0 ]]; then
  TARGET_USER="${SUDO_USER:-root}"
else
  TARGET_USER="${USER}"
fi

TARGET_HOME="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"
TARGET_GROUP="$(id -gn "${TARGET_USER}")"

TOOLS_ROOT="${TARGET_HOME}/Tools"
LOCAL_BIN="${TARGET_HOME}/.local/bin"
WORKSPACES_ROOT="${TARGET_HOME}/Workspaces"
TFSWITCH_BIN_DIR="${TOOLS_ROOT}/tfswitch/bin"
LLMFIT_BIN_DIR="${TOOLS_ROOT}/llmfit/bin"

BASE_PACKAGES=(
  apt-transport-https
  build-essential
  ca-certificates
  cpu-checker
  curl
  gnupg
  jq
  python3
  qemu-system-x86-hwe
  bridge-utils
  libvirt-clients-qemu-hwe
  libvirt-clients-hwe
#  libvirt-daemon-system
  snapd
  tar
  tmux
  unzip
)

JAVA_PACKAGES=(
  openjdk-21-jdk
)

GCLOUD_PACKAGES=(
  google-cloud-cli
  google-cloud-cli-gke-gcloud-auth-plugin
)

NODE_PACKAGES=(
  nodejs
)

VSCODE_PACKAGES=(
  code
)

CHROME_PACKAGES=(
  google-chrome-stable
)

ARCH="$(uname -m)"
case "${ARCH}" in
  x86_64)
    CLI_ARCH="amd64"
    AWS_ARCH="x86_64"
    GO_ARCH="amd64"
    K9S_ARCH="amd64"
    LLMFIT_ARCH="x86_64-unknown-linux-gnu"
    CHROME_SUPPORTED=1
    ;;
  aarch64|arm64)
    CLI_ARCH="arm64"
    AWS_ARCH="aarch64"
    GO_ARCH="arm64"
    K9S_ARCH="arm64"
    LLMFIT_ARCH="aarch64-unknown-linux-gnu"
    CHROME_SUPPORTED=0
    ;;
  *)
    echo "Unsupported architecture: ${ARCH}" >&2
    exit 1
    ;;
esac

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

log_section() {
  printf '\n==> %s\n' "$1"
}

log_info() {
  printf '  - %s\n' "$1"
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

run_sudo() {
  if [[ ${EUID} -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

run_as_target_user() {
  if [[ "${TARGET_USER}" == "$(id -un)" ]]; then
    "$@"
  else
    sudo -u "${TARGET_USER}" "$@"
  fi
}

ensure_sudo() {
  if [[ ${EUID} -ne 0 ]]; then
    sudo -v
  fi
}

ensure_ubuntu() {
  if [[ ! -r /etc/os-release ]]; then
    fail "/etc/os-release is missing; this script targets Ubuntu."
  fi

  # shellcheck disable=SC1091
  source /etc/os-release
  if [[ "${ID:-}" != "ubuntu" ]]; then
    fail "This script targets Ubuntu; detected ${ID:-unknown}."
  fi

  if [[ "${VERSION_ID:-}" != "26.04" ]]; then
    log_info "Detected Ubuntu ${VERSION_ID:-unknown}; this script is intended for Ubuntu 26.04 LTS."
  fi
}

apt_update() {
  if [[ ${APT_UPDATED} -eq 0 ]]; then
    run_sudo apt-get update
    APT_UPDATED=1
  fi
}

install_apt_packages() {
  apt_update
  run_sudo apt-get install -y "$@"
}

write_root_file() {
  local destination="$1"
  local content="$2"
  printf '%s\n' "${content}" | run_sudo tee "${destination}" >/dev/null
}

install_gpg_key() {
  local url="$1"
  local destination="$2"
  curl -fsSL "${url}" | run_sudo gpg --dearmor -o "${destination}"
  run_sudo chmod 0644 "${destination}"
}

ensure_dir_owned_by_target() {
  run_sudo install -d -m 0755 -o "${TARGET_USER}" -g "${TARGET_GROUP}" "$1"
}

ensure_directories() {
  ensure_dir_owned_by_target "${TOOLS_ROOT}"
  ensure_dir_owned_by_target "${LOCAL_BIN}"
  ensure_dir_owned_by_target "${WORKSPACES_ROOT}"
  ensure_dir_owned_by_target "${WORKSPACES_ROOT}/oss"
  ensure_dir_owned_by_target "${WORKSPACES_ROOT}/models"
  ensure_dir_owned_by_target "${TFSWITCH_BIN_DIR}"
  ensure_dir_owned_by_target "${LLMFIT_BIN_DIR}"
}

symlink_into_local_bin() {
  local source_path="$1"
  local link_name="$2"
  run_as_target_user ln -sfn "${source_path}" "${LOCAL_BIN}/${link_name}"
}

install_binary_url() {
  local url="$1"
  local destination="$2"
  local tmp_file="${TMP_DIR}/$(basename "${destination}")"
  curl -fsSL "${url}" -o "${tmp_file}"
  run_sudo install -m 0755 "${tmp_file}" "${destination}"
}

install_tarball_binary_from_url() {
  local url="$1"
  local binary_name="$2"
  local destination="$3"
  local tarball="${TMP_DIR}/${binary_name}.tar.gz"
  local extract_dir="${TMP_DIR}/${binary_name}-extract"

  rm -rf "${extract_dir}"
  mkdir -p "${extract_dir}"
  curl -fsSL "${url}" -o "${tarball}"
  tar -xzf "${tarball}" -C "${extract_dir}"

  local extracted
  extracted="$(find "${extract_dir}" -type f -name "${binary_name}" | head -n 1)"
  [[ -n "${extracted}" ]] || fail "Unable to find ${binary_name} inside ${url}"

  run_sudo install -m 0755 "${extracted}" "${destination}"
}

setup_google_cloud_repo() {
  log_section "repository setup: google cloud cli"
  run_sudo install -d -m 0755 /etc/apt/keyrings
  install_gpg_key \
    "https://packages.cloud.google.com/apt/doc/apt-key.gpg" \
    "/etc/apt/keyrings/google-cloud.gpg"
  write_root_file \
    "/etc/apt/sources.list.d/google-cloud-sdk.list" \
    "deb [signed-by=/etc/apt/keyrings/google-cloud.gpg] https://packages.cloud.google.com/apt cloud-sdk main"
  APT_UPDATED=0
  install_apt_packages "${GCLOUD_PACKAGES[@]}"
}

setup_vscode_repo() {
  log_section "repository setup: visual studio code"
  run_sudo install -d -m 0755 /etc/apt/keyrings
  install_gpg_key \
    "https://packages.microsoft.com/keys/microsoft.asc" \
    "/etc/apt/keyrings/packages.microsoft.gpg"
  write_root_file \
    "/etc/apt/sources.list.d/vscode.list" \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main"
  APT_UPDATED=0
  install_apt_packages "${VSCODE_PACKAGES[@]}"
}

setup_chrome_repo() {
  if [[ ${CHROME_SUPPORTED} -ne 1 ]]; then
    log_section "repository setup: google chrome"
    log_info "Skipping Google Chrome because Google only publishes Linux Chrome packages for amd64."
    return
  fi

  log_section "repository setup: google chrome"
  run_sudo install -d -m 0755 /etc/apt/keyrings
  install_gpg_key \
    "https://dl.google.com/linux/linux_signing_key.pub" \
    "/etc/apt/keyrings/google-linux-signing-key.gpg"
  write_root_file \
    "/etc/apt/sources.list.d/google-chrome.list" \
    "deb [arch=amd64 signed-by=/etc/apt/keyrings/google-linux-signing-key.gpg] https://dl.google.com/linux/chrome/deb/ stable main"
  APT_UPDATED=0
  install_apt_packages "${CHROME_PACKAGES[@]}"
}

setup_nodesource_repo() {
  log_section "repository setup: node.js 24"
  curl -fsSL https://deb.nodesource.com/setup_24.x -o "${TMP_DIR}/nodesource-setup.sh"
  run_sudo bash "${TMP_DIR}/nodesource-setup.sh"
  APT_UPDATED=0
  install_apt_packages "${NODE_PACKAGES[@]}"
}

install_base_packages() {
  log_section "system packages"
  install_apt_packages "${BASE_PACKAGES[@]}" "${JAVA_PACKAGES[@]}"
}

install_go() {
  log_section "language toolchains: go"
  local go_json_url="https://go.dev/dl/?mode=json"
  local go_filename
  go_filename="$(curl -fsSL "${go_json_url}" | jq -r --arg suffix "linux-${GO_ARCH}.tar.gz" '
    map(select(.stable == true))[0].files[]
    | select(.filename | endswith($suffix))
    | .filename
  ' | head -n 1)"
  [[ -n "${go_filename}" && "${go_filename}" != "null" ]] || fail "Could not determine latest Go tarball."

  local tarball="${TMP_DIR}/${go_filename}"
  curl -fsSL "https://go.dev/dl/${go_filename}" -o "${tarball}"
  run_sudo rm -rf /usr/local/go
  run_sudo tar -C /usr/local -xzf "${tarball}"
}

install_pnpm() {
  log_section "language toolchains: pnpm"
  run_sudo npm install -g pnpm
}

install_awscli() {
  log_section "cloud tools: aws cli"
  local archive="${TMP_DIR}/awscliv2.zip"
  local extract_dir="${TMP_DIR}/awscli"
  rm -rf "${extract_dir}"

  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${AWS_ARCH}.zip" -o "${archive}"
  unzip -q "${archive}" -d "${extract_dir}"
  run_sudo "${extract_dir}/aws/install" --update
}

install_kubectl() {
  log_section "cloud tools: kubectl"
  local version
  version="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"
  install_binary_url \
    "https://dl.k8s.io/release/${version}/bin/linux/${CLI_ARCH}/kubectl" \
    "/usr/local/bin/kubectl"
}

install_helm() {
  log_section "kubernetes tools: helm"
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 -o "${TMP_DIR}/get-helm-3"
  chmod +x "${TMP_DIR}/get-helm-3"
  run_sudo env DESIRED_VERSION="" USE_SUDO=false BINARY_NAME=helm HELM_INSTALL_DIR=/usr/local/bin "${TMP_DIR}/get-helm-3"
}

install_kind() {
  log_section "kubernetes tools: kind"
  local kind_version
  kind_version="$(curl -fsSL https://api.github.com/repos/kubernetes-sigs/kind/releases/latest | jq -r '.tag_name')"
  [[ -n "${kind_version}" && "${kind_version}" != "null" ]] || fail "Could not determine latest kind release."
  install_binary_url \
    "https://kind.sigs.k8s.io/dl/${kind_version}/kind-linux-${CLI_ARCH}" \
    "/usr/local/bin/kind"
}

install_k9s() {
  log_section "kubernetes tools: k9s"
  install_tarball_binary_from_url \
    "https://github.com/derailed/k9s/releases/latest/download/k9s_Linux_${K9S_ARCH}.tar.gz" \
    "k9s" \
    "/usr/local/bin/k9s"
}

install_minikube() {
  log_section "kubernetes tools: minikube"
  install_binary_url \
    "https://github.com/kubernetes/minikube/releases/latest/download/minikube-linux-${CLI_ARCH}" \
    "/usr/local/bin/minikube"
}

install_multipass() {
  log_section "virtualization: multipass"
  if run_sudo snap list multipass >/dev/null 2>&1; then
    run_sudo snap refresh multipass
  else
    run_sudo snap install multipass
  fi
}

install_tfswitch() {
  log_section "downloaded tools: tfswitch"
  curl -fsSL \
    "https://raw.githubusercontent.com/warrensbox/terraform-switcher/master/install.sh" \
    -o "${TMP_DIR}/install-tfswitch.sh"
  chmod +x "${TMP_DIR}/install-tfswitch.sh"
  run_as_target_user bash "${TMP_DIR}/install-tfswitch.sh" -b "${TFSWITCH_BIN_DIR}"
  symlink_into_local_bin "${TFSWITCH_BIN_DIR}/tfswitch" "tfswitch"
}

install_llmfit() {
  log_section "downloaded tools: llmfit"
  local llmfit_url
  llmfit_url="$(curl -fsSL https://api.github.com/repos/AlexsJones/llmfit/releases/latest \
    | jq -r --arg asset_suffix "${LLMFIT_ARCH}.tar.gz" '
      .assets[]
      | select(.name | endswith($asset_suffix))
      | .browser_download_url
    ' | head -n 1)"
  [[ -n "${llmfit_url}" && "${llmfit_url}" != "null" ]] || fail "Could not determine latest llmfit release asset."

  install_tarball_binary_from_url "${llmfit_url}" "llmfit" "${LLMFIT_BIN_DIR}/llmfit"
  run_sudo chown "${TARGET_USER}:${TARGET_GROUP}" "${LLMFIT_BIN_DIR}/llmfit"
  symlink_into_local_bin "${LLMFIT_BIN_DIR}/llmfit" "llmfit"
}

print_next_steps() {
  log_section "installed tools and versions"

  print_version_line() {
    local label="$1"
    shift

    if "$@" >/dev/null 2>&1; then
      local version_output
      version_output="$("$@" 2>&1 | head -n 1)"
      printf '  - %-18s %s\n' "${label}" "${version_output}"
    else
      printf '  - %-18s %s\n' "${label}" "not found"
    fi
  }

  print_version_line "curl" curl --version
  print_version_line "jq" jq --version
  print_version_line "tmux" tmux -V
  print_version_line "python3" python3 --version
  print_version_line "java" java -version
  print_version_line "javac" javac -version
  print_version_line "go" /usr/local/go/bin/go version
  print_version_line "node" node --version
  print_version_line "npm" npm --version
  print_version_line "pnpm" pnpm --version
  print_version_line "gcloud" gcloud --version
  print_version_line "aws" aws --version
  print_version_line "kubectl" kubectl version --client=true
  print_version_line "helm" helm version --short
  print_version_line "kind" kind version
  print_version_line "k9s" k9s version
  print_version_line "minikube" minikube version
  print_version_line "multipass" multipass version
  print_version_line "tfswitch" tfswitch --version
  print_version_line "llmfit" llmfit --version

  if [[ ":${PATH}:" != *":${LOCAL_BIN}:"* ]]; then
    log_info "~/.local/bin is not currently on PATH in this shell."
  fi

  if [[ ":${PATH}:" != *":/usr/local/go/bin:"* ]]; then
    log_info "/usr/local/go/bin is not currently on PATH in this shell."
  fi
}

main() {
  ensure_ubuntu
  ensure_sudo
  ensure_directories

  install_base_packages
  setup_google_cloud_repo
  setup_vscode_repo
  setup_chrome_repo
  setup_nodesource_repo

  install_go
  install_pnpm

  install_awscli
  install_kubectl
  install_helm
  install_kind
  install_k9s
  install_minikube
  install_multipass

  install_tfswitch
  install_llmfit

  log_section "workspace directories"
  log_info "Ensured ${WORKSPACES_ROOT}"
  log_info "Ensured ${WORKSPACES_ROOT}/oss"
  log_info "Ensured ${WORKSPACES_ROOT}/models"

  print_next_steps
}

main "$@"
