#!/usr/bin/env bash
# build_appimage.sh
# Builds a PhotoFlare AppImage locally, equivalent to the GitHub Actions workflow.
#
# Usage:
#   bash installers/build_appimage.sh [--version VERSION] [--prefix /path/to/qt6]
#
# Options:
#   --version VERSION   Version string used to name the output AppImage (default: local)
#   --prefix  PATH      Path to a Qt6 installation (sets QMAKE and CMAKE_PREFIX_PATH)
#
# Output: PhotoFlare-<VERSION>-x86_64.AppImage in the repo root.
#
# Requirements (Ubuntu/Debian):
#   sudo apt-get install -y libgraphicsmagick++-dev libomp-dev \
#     libfftw3-dev libcurl4-openssl-dev qt6-base-dev qt6-tools-dev qt6-tools-dev-tools

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

VERSION="local"
QT_PREFIX=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version) VERSION="$2"; shift 2 ;;
        --prefix)  QT_PREFIX="$2"; shift 2 ;;
        *) echo "Unknown argument: $1"; exit 1 ;;
    esac
done

# Required on systems without FUSE (VMs, containers, CI)
export APPIMAGE_EXTRACT_AND_RUN=1

# Resolve qmake
if [[ -n "$QT_PREFIX" ]]; then
    QMAKE="$QT_PREFIX/bin/qmake"
else
    QMAKE=$(command -v qmake6 || command -v qmake || true)
fi
if [[ -z "$QMAKE" || ! -x "$QMAKE" ]]; then
    echo "ERROR: qmake not found. Install qt6-base-dev or pass --prefix /path/to/qt6"
    exit 1
fi
echo "Using qmake: $QMAKE"

# Install build dependencies
echo "=== Installing build dependencies ==="
if command -v apt-get &>/dev/null; then
    SUDO=""
    [[ $EUID -ne 0 ]] && command -v sudo &>/dev/null && SUDO="sudo"
    $SUDO apt-get install -y \
        libgraphicsmagick++-dev libomp-dev \
        libfftw3-dev libcurl4-openssl-dev \
        qt6-base-dev qt6-tools-dev qt6-tools-dev-tools
fi
echo ""

# Build photoflare and stage into appdir/
echo "=== Building photoflare ==="
"$QMAKE" CONFIG+=release PREFIX=/usr
make -j$(nproc)
make install INSTALL_ROOT="$REPO_ROOT/appdir"
echo ""

# Build gmic-qt and stage
echo "=== Building gmic-qt ==="
GMIC_QT_CLONE="$REPO_ROOT/build-gmic-qt-src"
GMIC_QT_BUILD="$REPO_ROOT/build-gmic-qt"

CMAKE_PREFIX=""
[[ -n "$QT_PREFIX" ]] && CMAKE_PREFIX="-DCMAKE_PREFIX_PATH=$QT_PREFIX"

if [[ ! -d "$GMIC_QT_CLONE" ]]; then
    git clone --depth 1 --branch v.3.4.2 https://github.com/c-koi/gmic-qt.git "$GMIC_QT_CLONE"
    git clone --depth 1 --branch v.3.7.5 https://github.com/GreycLab/gmic.git "$GMIC_QT_CLONE/gmic"
fi

cmake "$GMIC_QT_CLONE" -B "$GMIC_QT_BUILD" \
    $CMAKE_PREFIX \
    -DBUILD_WITH_QT6=ON \
    -DGMIC_QT_HOST=none \
    -DENABLE_SYSTEM_GMIC=OFF \
    -DGMIC_PATH="$GMIC_QT_CLONE/gmic/src" \
    -DENABLE_FFTW3=ON \
    -DENABLE_CURL=ON \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_EXE_LINKER_FLAGS="-no-pie"

cmake --build "$GMIC_QT_BUILD" --parallel 1
cp "$GMIC_QT_BUILD/gmic_qt" "$REPO_ROOT/appdir/usr/bin/gmic_photoflare_qt"
echo ""

# Download linuxdeploy tools
echo "=== Downloading linuxdeploy ==="
mkdir -p "$REPO_ROOT/tools"
for url in \
    "https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage" \
    "https://github.com/linuxdeploy/linuxdeploy-plugin-qt/releases/download/continuous/linuxdeploy-plugin-qt-x86_64.AppImage"
do
    fname=$(basename "$url")
    if [[ ! -f "$REPO_ROOT/tools/$fname" ]]; then
        wget -nv -P "$REPO_ROOT/tools" "$url"
        chmod +x "$REPO_ROOT/tools/$fname"
    fi
done
echo ""

# Build AppImage
echo "=== Building AppImage ==="
export QMAKE
export VERSION
export PATH="$REPO_ROOT/tools:$PATH"

"$REPO_ROOT/tools/linuxdeploy-x86_64.AppImage" \
    --appdir "$REPO_ROOT/appdir" \
    --plugin qt \
    --output appimage

echo ""
echo "=== Done. Output: PhotoFlare-${VERSION}-x86_64.AppImage ==="
