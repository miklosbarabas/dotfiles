#!/usr/bin/env bash
set -euo pipefail

# create-secureboot-mok-keys.sh
#
# Purpose:
#   Create a local Secure Boot / MOK signing key pair for signing a custom
#   Linux kernel image and kernel modules while keeping Secure Boot enabled.
#
# What it creates by default:
#   /root/secureboot-keys/MOK.priv
#   /root/secureboot-keys/MOK.der
#   /root/secureboot-keys/MOK.pem
#   /root/secureboot-keys/sb-kernel.cnf
#
# How to use:
#
#   1. Save this file:
#
#        create-secureboot-mok-keys.sh
#
#   2. Make it executable:
#
#        sudo chmod +x create-secureboot-mok-keys.sh
#
#   3. Run it:
#
#        sudo ./create-secureboot-mok-keys.sh
#
#   4. Enrol the generated certificate into MOK:
#
#        sudo mokutil --import /root/secureboot-keys/MOK.der
#
#      You will be asked to create a temporary enrolment password.
#
#   5. Reboot:
#
#        sudo reboot
#
#   6. In the blue MokManager screen:
#
#        Enroll MOK -> Continue -> Yes -> enter password -> Reboot
#
#   7. After booting back into Ubuntu, verify the key is enrolled:
#
#        sudo mokutil --test-key /root/secureboot-keys/MOK.der
#
#   8. Then run your kernel/module signing script, for example:
#
#        sudo ./sign-kernel-and-all-modules.sh 7.1.0-070100rc7-generic
#
# Optional overrides:
#
#   Use a different key directory:
#
#        sudo KEY_DIR=/root/my-secureboot-keys ./create-secureboot-mok-keys.sh
#
#   Use a different certificate Common Name:
#
#        sudo CN="My Kernel Signing Key" ./create-secureboot-mok-keys.sh
#
#      If you change CN, also run the signing script with matching EXPECTED_SIGNER:
#
#        sudo EXPECTED_SIGNER="My Kernel Signing Key" \
#          ./sign-kernel-and-all-modules.sh 7.1.0-070100rc7-generic
#
#   Use a longer certificate validity:
#
#        sudo DAYS=7300 ./create-secureboot-mok-keys.sh
#
#   Use a larger RSA key:
#
#        sudo RSA_BITS=4096 ./create-secureboot-mok-keys.sh
#
# Safety notes:
#
#   - The private key is sensitive:
#
#        /root/secureboot-keys/MOK.priv
#
#   - Keep it root-readable only.
#   - Do not copy it into your home directory.
#   - Do not commit it to git.
#   - Anyone with this private key can sign kernel modules trusted by your
#     enrolled MOK key.

KEY_DIR="${KEY_DIR:-/root/secureboot-keys}"
KEY_PRIV="$KEY_DIR/MOK.priv"
KEY_DER="$KEY_DIR/MOK.der"
KEY_PEM="$KEY_DIR/MOK.pem"
CONFIG_FILE="$KEY_DIR/sb-kernel.cnf"

CN="${CN:-Local Secure Boot Kernel Signing}"
DAYS="${DAYS:-3650}"
RSA_BITS="${RSA_BITS:-2048}"

die() {
  echo "ERROR: $*" >&2
  exit 1
}

require_root() {
  [[ "${EUID}" -eq 0 ]] || die "Run as root, e.g. sudo $0"
}

require_tool() {
  local tool="$1"
  command -v "$tool" >/dev/null 2>&1 || die "Missing tool: $tool"
}

file_exists() {
  [[ -f "$1" ]]
}

print_key_summary() {
  echo
  echo "Key files:"
  echo "  private key: $KEY_PRIV"
  echo "  DER cert:    $KEY_DER"
  echo "  PEM cert:    $KEY_PEM"

  echo
  echo "Certificate subject:"
  openssl x509 -in "$KEY_DER" -inform DER -noout -subject

  echo
  echo "Certificate fingerprint:"
  openssl x509 -in "$KEY_DER" -inform DER -noout -fingerprint -sha256

  if command -v mokutil >/dev/null 2>&1; then
    echo
    echo "MOK enrolment status:"
    if mokutil --test-key "$KEY_DER" >/dev/null 2>&1; then
      echo "  enrolled: yes"
    else
      echo "  enrolled: no"
      echo
      echo "To enrol it:"
      echo "  sudo mokutil --import $KEY_DER"
      echo "  sudo reboot"
      echo
      echo "Then use MokManager:"
      echo "  Enroll MOK -> Continue -> Yes -> enter password -> Reboot"
    fi
  fi
}

main() {
  require_root
  require_tool openssl

  mkdir -p "$KEY_DIR"
  chmod 700 "$KEY_DIR"

  local has_priv=0
  local has_der=0
  local has_pem=0

  file_exists "$KEY_PRIV" && has_priv=1
  file_exists "$KEY_DER" && has_der=1
  file_exists "$KEY_PEM" && has_pem=1

  if [[ "$has_priv" == "1" && "$has_der" == "1" && "$has_pem" == "1" ]]; then
    echo "MOK signing keys already exist. Not modifying them."
    chmod 600 "$KEY_PRIV"
    chmod 644 "$KEY_DER" "$KEY_PEM"
    print_key_summary
    exit 0
  fi

  if [[ "$has_priv" == "1" && "$has_der" == "1" && "$has_pem" == "0" ]]; then
    echo "Private key and DER certificate exist, but PEM certificate is missing."
    echo "Recreating PEM certificate from DER..."

    openssl x509 \
      -in "$KEY_DER" \
      -inform DER \
      -outform PEM \
      -out "$KEY_PEM"

    chmod 600 "$KEY_PRIV"
    chmod 644 "$KEY_DER" "$KEY_PEM"
    print_key_summary
    exit 0
  fi

  if [[ "$has_priv" == "1" || "$has_der" == "1" || "$has_pem" == "1" ]]; then
    die "Partial key state detected in $KEY_DIR.

Found:
  $KEY_PRIV: $has_priv
  $KEY_DER:  $has_der
  $KEY_PEM:  $has_pem

Refusing to guess or overwrite. Either restore the missing files, or move this directory aside and rerun:

  sudo mv $KEY_DIR ${KEY_DIR}.backup.\$(date +%Y%m%d-%H%M%S)
  sudo $0"
  fi

  echo "Creating new Secure Boot / MOK signing key pair..."
  echo "Directory: $KEY_DIR"
  echo "Common Name: $CN"
  echo "Validity: $DAYS days"
  echo "RSA bits: $RSA_BITS"

  cat > "$CONFIG_FILE" <<EOF
[ req ]
distinguished_name = req_distinguished_name
x509_extensions = v3
string_mask = utf8only
prompt = no

[ req_distinguished_name ]
commonName = $CN

[ v3 ]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical,CA:FALSE
extendedKeyUsage = codeSigning,1.3.6.1.4.1.311.10.3.6
EOF

  chmod 600 "$CONFIG_FILE"

  openssl req \
    -config "$CONFIG_FILE" \
    -new \
    -x509 \
    -newkey "rsa:$RSA_BITS" \
    -nodes \
    -days "$DAYS" \
    -outform DER \
    -keyout "$KEY_PRIV" \
    -out "$KEY_DER"

  openssl x509 \
    -in "$KEY_DER" \
    -inform DER \
    -outform PEM \
    -out "$KEY_PEM"

  chmod 600 "$KEY_PRIV" "$CONFIG_FILE"
  chmod 644 "$KEY_DER" "$KEY_PEM"

  echo
  echo "Created MOK signing keys."
  print_key_summary
}

main "$@"