#!/bin/bash
set -e

GITHUB_USER="rosstoss"
GITHUB_REPO="courier-dist"
BINARY_NAME="courier"
INSTALL_DIR="$HOME/.courier"
BIN_DIR="$INSTALL_DIR/bin"

CYAN='\033[1;36m'
BLUE='\033[1;34m'
RED='\033[0;31m'
NC='\033[0m'

clear

echo -e "${CYAN}"
echo "      ______                 _          "
echo "     / ____/___   __  _______(_)__  _____"
echo "    / /   / __ \/ / / / ___/ / _ \/ ___/"
echo "   / /___/ /_/ / /_/ / /  / /  __/ /     "
echo "   \____/\____/\__,_/_/  /_/\___/_/      "
echo -e "${BLUE}       INFRASTRUCTURE INSTALLER${NC}"
echo ""

echo -e "${BLUE}[+]${NC} Checking System Compatibility..."

ARCH=$(uname -m)
if [[ "$ARCH" != "arm64" ]]; then
  echo -e "${RED}Error: Courier requires an Apple Silicon (M1/M2/M3) Mac.${NC}"
  echo "Current architecture: $ARCH"
  exit 1
fi

if ! command -v python3 &> /dev/null; then
    echo -e "${RED}Error: Python 3 is required but not found.${NC}"
    exit 1
fi

mkdir -p "$BIN_DIR"

SHELL_CONFIG="$HOME/.zshrc"
if ! grep -q "$BIN_DIR" "$SHELL_CONFIG"; then
    echo -e "${BLUE}[+]${NC} Adding Courier to PATH..."
    echo "" >> "$SHELL_CONFIG"
    echo "# Courier AI Infrastructure" >> "$SHELL_CONFIG"
    echo "export PATH=\"$BIN_DIR:\$PATH\"" >> "$SHELL_CONFIG"
fi

echo -e "${BLUE}[+]${NC} Fetching Courier Engine..."

if [ -z "$VERSION_TAG" ]; then
    DOWNLOAD_URL="https://github.com/$GITHUB_USER/$GITHUB_REPO/releases/latest/download/$BINARY_NAME"
else
    DOWNLOAD_URL="https://github.com/$GITHUB_USER/$GITHUB_REPO/releases/download/$VERSION_TAG/$BINARY_NAME"
fi

echo "Downloading from: $DOWNLOAD_URL"

if ! curl -# -L "$DOWNLOAD_URL" -o "$BIN_DIR/$BINARY_NAME"; then
    echo -e "${RED}Error: Download failed.${NC}"
    echo "Please check your internet connection or the repository status."
    exit 1
fi

echo -e "${BLUE}[+]${NC} Finalizing Installation..."

chmod +x "$BIN_DIR/$BINARY_NAME"

xattr -d com.apple.quarantine "$BIN_DIR/$BINARY_NAME" 2>/dev/null || true

export PATH="$BIN_DIR:$PATH"

echo -e "${BLUE}[+]${NC} Launching Setup Wizard..."
sleep 1

cd "$INSTALL_DIR"

clear

exec "$BIN_DIR/$BINARY_NAME" --setup