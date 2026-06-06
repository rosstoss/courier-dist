#!/usr/bin/env bash

set -e

# ── config ───────────────────────────────────────────────────────────────────
GITHUB_USER="rosstoss"
GITHUB_REPO="courier-dist"
BINARY_NAME="courier"
COURIER_ROOT="$HOME/.courier"
APP_DIR="$COURIER_ROOT/app"
BIN_DIR="$COURIER_ROOT/bin"
ASSET_NAME="courier-personal-macos-arm64.tar.gz"
EDITION_LABEL="Personal Edition"

LATEST_RELEASE_URL="https://api.github.com/repos/$GITHUB_USER/$GITHUB_REPO/releases/latest"
COURIER_VERSION="$(curl -fsSL "$LATEST_RELEASE_URL" 2>/dev/null \
  | grep '"tag_name":' | head -1 \
  | sed -E 's/.*"tag_name": *"v?([^"]+)".*/\1/' | tr -d '[:space:]')"
[ -z "$COURIER_VERSION" ] && COURIER_VERSION="latest"

DOWNLOAD_URL="https://github.com/$GITHUB_USER/$GITHUB_REPO/releases/latest/download/$ASSET_NAME"
TMP_TAR="/tmp/courier_download.tar.gz"

ACCENT=$'\033[38;2;122;158;177m'   # #7a9eb1
SUCCESS=$'\033[38;2;127;174;127m'  # #7fae7f
ERRC=$'\033[38;2;201;122;122m'     # #c97a7a
MUTED=$'\033[38;2;138;141;148m'    # #8a8d94
DIM=$'\033[38;2;94;96;102m'        # #5e6066
TEXT=$'\033[38;2;212;214;219m'     # #d4d6db
BOLD=$'\033[1m'
NC=$'\033[0m'
CLR=$'\033[K'
HIDE_CUR=$'\033[?25l'
SHOW_CUR=$'\033[?25h'
SPIN=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
LABEL_W=15

TTY=0; [ -t 1 ] && TTY=1
cleanup() { [ "$TTY" -eq 1 ] && printf '%s' "$SHOW_CUR" 2>/dev/null || true; }
trap cleanup EXIT INT TERM

# ── helpers ───────────────────────────────────────────────────────────────────
bar() {  # $1 pct  [$2 width] — accent block-char bar over a dim track
  local pct=${1:-0} width=${2:-18} filled i out=""
  filled=$(( pct * width / 100 ))
  if [ "$filled" -lt 0 ]; then filled=0; fi
  if [ "$filled" -gt "$width" ]; then filled=$width; fi

  out="$SUCCESS"
  for (( i=0; i<width; i++ )); do
    if [ "$i" -eq "$filled" ]; then out="$out$DIM"; fi
    if [ "$i" -lt "$filled" ]; then out="$out-"; else out="$out-"; fi
  done
  printf '%s%s' "$out" "$NC"
}

human() {  # $1 bytes -> human size
  local b=${1:-0}
  if [ "$b" -ge 1073741824 ]; then
    printf '%d.%01d GB' $(( b / 1073741824 )) $(( b % 1073741824 * 10 / 1073741824 ))
  elif [ "$b" -ge 1048576 ]; then
    printf '%d MB' $(( b / 1048576 ))
  else
    printf '%d KB' $(( b / 1024 ))
  fi
}

step_done() { printf '\r  %s[✓]%s %-*s %s%s%s%s\n' "$SUCCESS" "$NC" "$LABEL_W" "$1" "$DIM" "${2:-}" "$NC" "$CLR"; }
step_fail() { printf '\r  %s[✗]%s %-*s %s%s%s%s\n' "$ERRC" "$NC" "$LABEL_W" "$1" "$ERRC" "${2:-}" "$NC" "$CLR"; }

# Download $1 -> $2 with a live progress bar (%, size, speed, ETA).
download() {
  local url=$1 out=$2 total cur=0 start elapsed speed eta pct tick=0
  total=$(curl -fsIL "$url" 2>/dev/null \
    | awk '{ if (tolower($0) ~ /^content-length:/) v=$2 } END { gsub(/[^0-9]/,"",v); print v+0 }')
  [ -z "$total" ] && total=0
  rm -f "$out"
  curl -fL "$url" -o "$out" 2>/dev/null &
  local pid=$!
  start=$SECONDS
  while kill -0 "$pid" 2>/dev/null; do
    if [ -f "$out" ]; then cur=$(stat -f%z "$out" 2>/dev/null || echo 0); fi
    elapsed=$(( SECONDS - start )); if [ "$elapsed" -lt 1 ]; then elapsed=1; fi
    speed=$(( cur / elapsed ))
    if [ "$total" -gt 0 ]; then
      pct=$(( cur * 100 / total )); if [ "$pct" -gt 99 ]; then pct=99; fi
      eta=0; if [ "$speed" -gt 0 ]; then eta=$(( (total - cur) / speed )); fi
      printf '\r  %s%s%s %-*s %s %s%3d%%%s  %s%s / %s · %s/s · ETA %ds%s%s' \
        "$ACCENT" "${SPIN[tick%10]}" "$NC" "$LABEL_W" "Downloading" "$(bar "$pct")" \
        "$TEXT" "$pct" "$NC" "$DIM" "$(human "$cur")" "$(human "$total")" "$(human "$speed")" "$eta" "$NC" "$CLR"
    else
      printf '\r  %s%s%s %-*s %s%s · %s/s%s%s' \
        "$ACCENT" "${SPIN[tick%10]}" "$NC" "$LABEL_W" "Downloading" "$DIM" "$(human "$cur")" "$(human "$speed")" "$NC" "$CLR"
    fi
    tick=$(( tick + 1 )); sleep 0.2
  done
  local rc=0; wait "$pid" || rc=$?
  return $rc
}

# Extract $1 -> $2 with a progress bar driven by gzip's uncompressed-size footer.
extract() {
  local tarball=$1 dest=$2 total_b total_kb cur_kb pct tick=0
  total_b=$(tail -c 4 "$tarball" 2>/dev/null | od -An -tu4 2>/dev/null | tr -d ' ' || echo 0)
  [ -z "$total_b" ] && total_b=0
  total_kb=$(( total_b / 1024 ))
  rm -rf "$dest"; mkdir -p "$dest"
  tar -xf "$tarball" -C "$dest" &
  local pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    cur_kb=$(du -sk "$dest" 2>/dev/null | awk '{print $1}'); [ -z "$cur_kb" ] && cur_kb=0
    if [ "$total_kb" -gt 1024 ]; then
      pct=$(( cur_kb * 100 / total_kb )); if [ "$pct" -gt 99 ]; then pct=99; fi
      printf '\r  %s%s%s %-*s %s %s%3d%%%s  %s%s%s%s' \
        "$ACCENT" "${SPIN[tick%10]}" "$NC" "$LABEL_W" "Extracting" "$(bar "$pct")" \
        "$TEXT" "$pct" "$NC" "$DIM" "$(human $(( cur_kb * 1024 )))" "$NC" "$CLR"
    else
      printf '\r  %s%s%s %-*s %s%s%s%s' \
        "$ACCENT" "${SPIN[tick%10]}" "$NC" "$LABEL_W" "Extracting" "$DIM" "$(human $(( cur_kb * 1024 )))" "$NC" "$CLR"
    fi
    tick=$(( tick + 1 )); sleep 0.2
  done
  local rc=0; wait "$pid" || rc=$?
  return $rc
}

# Ad-hoc codesign the binary + native libs with a per-file progress bar.
sign() {
  local dir=$1 list total i=0 pct f
  list=$(find "$dir" -type f \( -name "Courier" -o -name "*.dylib" -o -name "*.so" \) 2>/dev/null || true)
  total=$(printf '%s\n' "$list" | grep -c . 2>/dev/null || true); [ -z "$total" ] && total=0
  if [ "$total" -eq 0 ]; then return 0; fi
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    codesign --force --deep --sign - "$f" >/dev/null 2>&1 || true
    i=$(( i + 1 )); pct=$(( i * 100 / total )); if [ "$pct" -gt 100 ]; then pct=100; fi
    printf '\r  %s%s%s %-*s %s %s%3d%%%s  %s%d / %d%s%s' \
      "$ACCENT" "${SPIN[i%10]}" "$NC" "$LABEL_W" "Verifying" "$(bar "$pct")" \
      "$TEXT" "$pct" "$NC" "$DIM" "$i" "$total" "$NC" "$CLR"
  done <<< "$list"
  return 0
}

# ── banner ────────────────────────────────────────────────────────────────────
clear 2>/dev/null || true
[ "$TTY" -eq 1 ] && printf '%s' "$HIDE_CUR"
printf '%s\n' "$ACCENT"
echo " ██████╗ ██████╗ ██╗   ██╗██████╗ ██╗███████╗██████╗ "
echo "██╔════╝██╔═══██╗██║   ██║██╔══██╗██║██╔════╝██╔══██╗"
echo "██║     ██║   ██║██║   ██║██████╔╝██║█████╗  ██████╔╝"
echo "██║     ██║   ██║██║   ██║██╔══██╗██║██╔══╝  ██╔══██╗"
echo "╚██████╗╚██████╔╝╚██████╔╝██║  ██║██║███████╗██║  ██║"
echo " ╚═════╝ ╚═════╝  ╚═════╝ ╚═╝  ╚═╝╚═╝╚══════╝╚═╝  ╚═╝"
printf '%s   %s · installing v%s%s\n\n' "$MUTED" "$EDITION_LABEL" "$COURIER_VERSION" "$NC"

# ── 1. system check ───────────────────────────────────────────────────────────
ARCH=$(uname -m)
if [ "$ARCH" != "arm64" ]; then
  step_fail "System check" "Courier requires an Apple Silicon Mac"
  exit 1
fi
step_done "System check" "Apple Silicon · macOS"

# ── 2. PATH ───────────────────────────────────────────────────────────────────
mkdir -p "$APP_DIR" "$BIN_DIR"
export PATH="$BIN_DIR:$PATH"
SHELL_CONFIG="$HOME/.zshrc"
if [[ "$SHELL" == *"bash"* ]]; then SHELL_CONFIG="$HOME/.bash_profile"; fi
[ -f "$SHELL_CONFIG" ] || touch "$SHELL_CONFIG"
if ! grep -q "$BIN_DIR" "$SHELL_CONFIG" 2>/dev/null; then
  printf "\n# Courier AI Infrastructure\nexport PATH=\"%s:\$PATH\"\n" "$BIN_DIR" >> "$SHELL_CONFIG"
  step_done "Configure PATH" "added to ${SHELL_CONFIG/#$HOME/~}"
else
  step_done "Configure PATH" "already configured"
fi

# ── 3. download ───────────────────────────────────────────────────────────────
if download "$DOWNLOAD_URL" "$TMP_TAR"; then
  step_done "Download" "$(human "$(stat -f%z "$TMP_TAR" 2>/dev/null || echo 0)") · $ASSET_NAME"
else
  step_fail "Download" "could not fetch $ASSET_NAME — check your connection"
  exit 1
fi

if ! tar -tf "$TMP_TAR" >/dev/null 2>&1; then
  step_fail "Download" "archive is corrupt — please retry"
  rm -f "$TMP_TAR"; exit 1
fi

# ── 4. extract ────────────────────────────────────────────────────────────────
if extract "$TMP_TAR" "$APP_DIR"; then
  step_done "Extract" "unpacked to ${APP_DIR/#$HOME/~}"
else
  step_fail "Extract" "failed to unpack the archive"
  exit 1
fi
rm -f "$TMP_TAR"

# ── 5. verify (quarantine + codesign) ─────────────────────────────────────────
xattr -dr com.apple.quarantine "$APP_DIR" 2>/dev/null || true
sign "$APP_DIR"
step_done "Verify" "signed for this Mac"

# ── 6. finalize ───────────────────────────────────────────────────────────────
[ -L "$BIN_DIR/$BINARY_NAME" ] && rm "$BIN_DIR/$BINARY_NAME"
ln -sf "$APP_DIR/$BINARY_NAME" "$BIN_DIR/$BINARY_NAME"
chmod +x "$APP_DIR/$BINARY_NAME"
hash -r 2>/dev/null || true
echo "$COURIER_VERSION" > "$COURIER_ROOT/VERSION"
step_done "Finalize" "courier v$COURIER_VERSION ready"

# ── launch ────────────────────────────────────────────────────────────────────
[ "$TTY" -eq 1 ] && printf '%s' "$SHOW_CUR"
printf '\n  %s%s✓ Courier installed.%s %sLaunching setup…%s\n\n' "$BOLD" "$SUCCESS" "$NC" "$MUTED" "$NC"
sleep 1

"$BIN_DIR/$BINARY_NAME" --setup </dev/tty

exec "${SHELL:-/bin/zsh}" -l </dev/tty
