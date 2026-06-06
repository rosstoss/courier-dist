set -e

GITHUB_USER="rosstoss"
GITHUB_REPO="courier-dist"
BINARY_NAME="courier"
COURIER_ROOT="$HOME/.courier"
APP_DIR="$COURIER_ROOT/app"
BIN_DIR="$COURIER_ROOT/bin"

LATEST_RELEASE_URL="https://api.github.com/repos/$GITHUB_USER/$GITHUB_REPO/releases/latest"
COURIER_VERSION="$(curl -fsSL "$LATEST_RELEASE_URL" 2>/dev/null \
  | grep '"tag_name":' \
  | head -1 \
  | sed -E 's/.*"tag_name": *"v?([^"]+)".*/\1/' \
  | tr -d '[:space:]')"
if [ -z "$COURIER_VERSION" ]; then
  COURIER_VERSION="1.2.12"
fi

CYAN=$'\033[1;36m'
BLUE=$'\033[1;34m'
RED=$'\033[0;31m'
NC=$'\033[0m'

spinner() {
  local pid="$1"
  local delay=0.1
  local spinstr='|/-\\'
  while [ "$(ps -p "$pid" -o state= 2>/dev/null)" ]; do
    local temp="${spinstr#?}"
    printf " [%c]  " "$spinstr"
    local spinstr="$temp${spinstr%"$temp"}"
    sleep "$delay"
    printf "\b\b\b\b\b\b"
  done
  printf "    \b\b\b\b"
}

clear
echo "${CYAN}"
echo " ██████╗ ██████╗ ██╗   ██╗██████╗ ██╗███████╗██████╗ "
echo "██╔════╝██╔═══██╗██║   ██║██╔══██╗██║██╔════╝██╔══██╗"
echo "██║     ██║   ██║██║   ██║██████╔╝██║█████╗  ██████╔╝"
echo "██║     ██║   ██║██║   ██║██╔══██╗██║██╔══╝  ██╔══██╗"
echo "╚██████╗╚██████╔╝╚██████╔╝██║  ██║██║███████╗██║  ██║"
echo " ╚═════╝ ╚═════╝  ╚═════╝ ╚═╝  ╚═╝╚═╝╚══════╝╚═╝  ╚═╝"
echo "${BLUE}       COMMERCIAL EDITION INSTALLER · v${COURIER_VERSION}${NC}"
echo ""

echo "${BLUE}[+]${NC} Checking System Compatibility..."

ARCH=$(uname -m)
if [[ "$ARCH" != "arm64" ]]; then
  echo "${RED}Error: Courier requires an Apple Silicon Mac.${NC}"
  exit 1
fi

if [ -d "$APP_DIR" ]; then
  if [ -f "$APP_DIR/$BINARY_NAME" ]; then
    echo "${BLUE}[+]${NC} Removing existing Courier app bundle..."
    rm -rf "$APP_DIR"
  fi
fi

mkdir -p "$APP_DIR"
mkdir -p "$BIN_DIR"

export PATH="$BIN_DIR:$PATH"

SHELL_CONFIG="$HOME/.zshrc"
if [[ "$SHELL" == *"bash"* ]]; then
  SHELL_CONFIG="$HOME/.bash_profile"
fi

echo "${BLUE}[+]${NC} Checking PATH configuration..."

if [ ! -f "$SHELL_CONFIG" ]; then
  echo "${BLUE}[+]${NC} Creating $SHELL_CONFIG..."
  touch "$SHELL_CONFIG"
fi

if ! grep -q "$BIN_DIR" "$SHELL_CONFIG" 2>/dev/null; then
    echo "${BLUE}[+]${NC} Adding Courier to PATH in $SHELL_CONFIG..."
    printf "\n# Courier AI Infrastructure\nexport PATH=\"%s:\$PATH\"\n" "$BIN_DIR" >> "$SHELL_CONFIG"
    echo "${BLUE}[+]${NC} Added Courier to your PATH — the 'courier' command is ready in this terminal after setup, and in any new terminal automatically."
else
    echo "${BLUE}[+]${NC} Courier is already in your PATH."
fi

echo "${BLUE}[+]${NC} Fetching Courier Engine..."

ASSET_NAME="courier-macos-arm64.tar.gz"
DOWNLOAD_URL="https://github.com/$GITHUB_USER/$GITHUB_REPO/releases/latest/download/$ASSET_NAME"

TMP_TAR="/tmp/courier_download.tar.gz"
echo "${BLUE}[+]${NC} Downloading bundle..."
curl -f# -L "$DOWNLOAD_URL" -o "$TMP_TAR"

echo "${BLUE}[+]${NC} Validating archive..."
tar -tf "$TMP_TAR" >/dev/null

echo "${BLUE}[+]${NC} Extracting bundle..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR"
tar -xf "$TMP_TAR" -C "$APP_DIR" &
EXTRACT_PID=$!
spinner "$EXTRACT_PID"
wait "$EXTRACT_PID"
rm -rf "$TMP_TAR"
echo " Done."

echo "${BLUE}[+]${NC} Finalizing Installation..."

[ -L "$BIN_DIR/$BINARY_NAME" ] && rm "$BIN_DIR/$BINARY_NAME"

ln -sf "$APP_DIR/$BINARY_NAME" "$BIN_DIR/$BINARY_NAME"
chmod +x "$APP_DIR/$BINARY_NAME"

echo "${BLUE}[+]${NC} Clearing macOS security flags..."
( xattr -dr com.apple.quarantine "$APP_DIR" 2>/dev/null || true ) &
XATTR_PID=$!
spinner "$XATTR_PID"
echo " Done."

echo "${BLUE}[+]${NC} Verifying binary integrity..."
(
  # Find and sign the main binary and all dylibs/so files
  find "$APP_DIR" -type f \( -name "Courier" -o -name "*.dylib" -o -name "*.so" \) -exec codesign --force --deep --sign - {} \; 2>/dev/null
) &
SIGN_PID=$!
spinner "$SIGN_PID"
echo " Done."

mv "$APP_DIR" "${APP_DIR}_tmp"
mv "${APP_DIR}_tmp" "$APP_DIR"
export PATH="$BIN_DIR:$PATH"
hash -r 2>/dev/null || true

echo "$COURIER_VERSION" > "$COURIER_ROOT/VERSION"

echo -n "${BLUE}[+]${NC} Finalizing Courier Engine installation. This may take a minute or two."
(
  delay=0.1
  spinstr='|/-\\'
  for ((i=0; i<750; i++)); do
    temp="${spinstr#?}"
    printf " [%c]  " "$spinstr"
    spinstr="$temp${spinstr%"$temp"}"
    sleep "$delay"
    printf "\b\b\b\b\b\b"
  done
  printf " Done. \n"
) &

"$BIN_DIR/$BINARY_NAME" --setup </dev/tty

exec "${SHELL:-/bin/zsh}" -l </dev/tty