#!/bin/sh
set -e

REPO="whcc/whcc-cli-releases"
BINARY_NAME="whcc"

use_color() {
  [ -t 1 ] && [ -z "${NO_COLOR:-}" ]
}

has_utf8() {
  case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
    *UTF-8*|*utf-8*|*UTF8*|*utf8*) return 0 ;;
  esac
  if command -v locale >/dev/null 2>&1; then
    charmap=$(locale charmap 2>/dev/null || true)
    case "${charmap}" in
      UTF-8|UTF8) return 0 ;;
    esac
  fi
  return 1
}

show_banner() {
  if has_utf8; then
    if use_color; then printf '\033[34m'; fi
    cat <<'BANNER'

             ▄▄██▄▄
        ▄▄████████████▄▄
    ▄▄██████▀▀▀  ▀▀▀██████▄▄
    ████▀▀            ▀▀████
    █████              █████
    █████              █████
    █████▄▄▄▄▄▄▄▄▄▄▄▄▄▄█████
    ████████████████████████

BANNER
    if use_color; then printf '\033[0m'; fi
  fi
  if use_color; then printf '\033[1m'; fi
  echo '        WHCC CLI Installer'
  if use_color; then printf '\033[0m'; fi
  echo ''
}

main() {
  show_banner

  case "${1:-}" in
    --banner) return ;;
  esac

  detect_platform
  resolve_version
  create_tmpdir
  download_and_verify
  install_binary
  check_path
  verify_install
  cleanup
}

detect_platform() {
  OS=$(uname -s)
  ARCH=$(uname -m)

  case "${OS}" in
    Darwin)
      case "${ARCH}" in
        arm64)  TARGET="aarch64-apple-darwin" ;;
        x86_64) TARGET="x86_64-apple-darwin" ;;
        *)      err "Unsupported macOS architecture: ${ARCH}" ;;
      esac
      ;;
    Linux)
      case "${ARCH}" in
        x86_64)  TARGET="x86_64-unknown-linux-gnu" ;;
        aarch64) TARGET="aarch64-unknown-linux-gnu" ;;
        *)       err "Unsupported Linux architecture: ${ARCH}" ;;
      esac
      ;;
    *)
      err "Unsupported OS: ${OS}. Download manually from https://github.com/${REPO}/releases"
      ;;
  esac

  echo "Detected platform: ${TARGET}"
}

resolve_version() {
  if [ -n "${WHCC_VERSION:-}" ]; then
    VERSION="${WHCC_VERSION}"
    echo "Using specified version: v${VERSION}"
    return
  fi

  echo "Fetching latest version..."
  VERSION=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
    | grep '"tag_name"' \
    | sed -E 's/.*"tag_name": *"v([^"]+)".*/\1/')

  if [ -z "${VERSION}" ]; then
    err "Could not determine latest version. Set WHCC_VERSION to install a specific version."
  fi

  echo "Latest version: v${VERSION}"
}

create_tmpdir() {
  if TMPDIR_INSTALL=$(mktemp -d 2>/dev/null); then
    :
  else
    TMPDIR_INSTALL=$(mktemp -d -t whcc)
  fi
}

download_and_verify() {
  ARCHIVE="whcc-${VERSION}-${TARGET}.tar.gz"
  URL="https://github.com/${REPO}/releases/download/v${VERSION}/${ARCHIVE}"
  CHECKSUMS_URL="https://github.com/${REPO}/releases/download/v${VERSION}/checksums.txt"

  echo "Downloading ${ARCHIVE}..."
  curl -fsSL -o "${TMPDIR_INSTALL}/${ARCHIVE}" "${URL}" || err "Download failed. Check that version v${VERSION} exists at https://github.com/${REPO}/releases"

  echo "Downloading checksums..."
  curl -fsSL -o "${TMPDIR_INSTALL}/checksums.txt" "${CHECKSUMS_URL}" || err "Checksums download failed"

  echo "Verifying checksum..."
  EXPECTED=$(grep "${ARCHIVE}" "${TMPDIR_INSTALL}/checksums.txt" | awk '{print $1}')
  if [ -z "${EXPECTED}" ]; then
    err "No checksum found for ${ARCHIVE} in checksums.txt"
  fi

  if command -v sha256sum >/dev/null 2>&1; then
    ACTUAL=$(sha256sum "${TMPDIR_INSTALL}/${ARCHIVE}" | awk '{print $1}')
  elif command -v shasum >/dev/null 2>&1; then
    ACTUAL=$(shasum -a 256 "${TMPDIR_INSTALL}/${ARCHIVE}" | awk '{print $1}')
  else
    echo "Warning: no sha256sum or shasum found, skipping checksum verification"
    ACTUAL="${EXPECTED}"
  fi

  if [ "${ACTUAL}" != "${EXPECTED}" ]; then
    err "Checksum mismatch!\n  Expected: ${EXPECTED}\n  Actual:   ${ACTUAL}"
  fi

  echo "Checksum verified."
}

install_binary() {
  INSTALL_DIR="${WHCC_INSTALL_DIR:-${HOME}/.local/bin}"
  mkdir -p "${INSTALL_DIR}"

  echo "Installing to ${INSTALL_DIR}..."
  tar -xzf "${TMPDIR_INSTALL}/whcc-${VERSION}-${TARGET}.tar.gz" -C "${TMPDIR_INSTALL}"
  mv "${TMPDIR_INSTALL}/${BINARY_NAME}" "${INSTALL_DIR}/${BINARY_NAME}"
  chmod +x "${INSTALL_DIR}/${BINARY_NAME}"

  case "$(uname -s)" in
    Darwin)
      xattr -d com.apple.quarantine "${INSTALL_DIR}/${BINARY_NAME}" 2>/dev/null || true
      ;;
  esac
}

check_path() {
  case ":${PATH}:" in
    *":${INSTALL_DIR}:"*)
      return
      ;;
  esac

  echo ""
  echo "Add ${INSTALL_DIR} to your PATH:"
  echo ""

  SHELL_NAME=$(basename "${SHELL:-/bin/sh}")
  case "${SHELL_NAME}" in
    zsh)
      echo "  echo 'export PATH=\"${INSTALL_DIR}:\$PATH\"' >> ~/.zshrc"
      echo "  source ~/.zshrc"
      ;;
    bash)
      if [ -f "${HOME}/.bash_profile" ]; then
        RC_FILE=".bash_profile"
      else
        RC_FILE=".bashrc"
      fi
      echo "  echo 'export PATH=\"${INSTALL_DIR}:\$PATH\"' >> ~/${RC_FILE}"
      echo "  source ~/${RC_FILE}"
      ;;
    *)
      echo "  export PATH=\"${INSTALL_DIR}:\$PATH\""
      ;;
  esac
  echo ""
}

verify_install() {
  INSTALLED_VERSION=$("${INSTALL_DIR}/${BINARY_NAME}" --version 2>/dev/null || true)
  if [ -n "${INSTALLED_VERSION}" ]; then
    echo "Successfully installed: ${INSTALLED_VERSION}"
  else
    echo "Installed ${BINARY_NAME} to ${INSTALL_DIR}/${BINARY_NAME}"
  fi
}

cleanup() {
  rm -rf "${TMPDIR_INSTALL}"
}

err() {
  printf "Error: %s\n" "$1" >&2
  cleanup 2>/dev/null || true
  exit 1
}

main "$@"
