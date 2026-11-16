#!/usr/bin/env bash
# Build an LGPL libmpv runtime bundle for Linux.
#
# The resulting tarball contains libmpv.so.2 plus its private runtime
# dependencies, but not glibc or host graphics/audio driver libraries.
set -euo pipefail

MPV_TAG="${MPV_TAG:-v0.42.0}"
FFMPEG_TAG="${FFMPEG_TAG:-n9.0.2}"
LIBPLACEBO_TAG="${LIBPLACEBO_TAG:-v7.387.0}"
RID="${RID:-linux-x64}"
JOBS="${JOBS:-$(nproc)}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="${WORK:-$ROOT/.work/$RID}"
DIST="${DIST:-$ROOT/dist}"
PREFIX="$WORK/prefix"
SRC="$WORK/src"
BUILD="$WORK/build"
BUNDLE="$WORK/bundle"

MPV_SRC="${MPV_SRC:-$SRC/mpv}"
FFMPEG_SRC="${FFMPEG_SRC:-$SRC/ffmpeg}"
LIBPLACEBO_SRC="${LIBPLACEBO_SRC:-$SRC/libplacebo}"

log() { printf '\n==> %s\n' "$*"; }

fetch() {
    local repo=$1 tag=$2 dir=$3
    if [ ! -d "$dir" ]; then
        mkdir -p "$(dirname "$dir")"
        git clone --depth 1 --branch "$tag" "$repo" "$dir"
    fi
    if [ -d "$dir/.git" ] && [ -f "$dir/.gitmodules" ]; then
        # libplacebo needs its Python/glad helpers to generate the GL loader.
        git -C "$dir" submodule update --init 3rdparty/glad 3rdparty/jinja 3rdparty/markupsafe
    fi
}

fetch https://github.com/mpv-player/mpv.git "$MPV_TAG" "$MPV_SRC"
fetch https://github.com/FFmpeg/FFmpeg.git "$FFMPEG_TAG" "$FFMPEG_SRC"
fetch https://github.com/haasn/libplacebo.git "$LIBPLACEBO_TAG" "$LIBPLACEBO_SRC"

if [ "${REUSE:-0}" != "1" ]; then
    rm -rf "$PREFIX" "$BUILD"
fi
rm -rf "$BUNDLE"
mkdir -p "$PREFIX" "$BUILD" "$BUNDLE" "$DIST"

log "Building FFmpeg $FFMPEG_TAG (LGPL, shared)"
mkdir -p "$BUILD/ffmpeg"
(
    cd "$BUILD/ffmpeg"
    "$FFMPEG_SRC/configure" \
        --prefix="$PREFIX" \
        --libdir="$PREFIX/lib" \
        --disable-gpl \
        --disable-nonfree \
        --disable-programs \
        --disable-doc \
        --disable-debug \
        --enable-shared \
        --disable-static \
        --enable-pic \
        --disable-autodetect \
        --enable-zlib \
        --enable-libdav1d \
        --disable-gnutls \
        --disable-openssl
    make -j"$JOBS"
    make install
)

log "Building libplacebo $LIBPLACEBO_TAG (LGPL, OpenGL only)"
(
    cd "$LIBPLACEBO_SRC"
    rm -rf build
    PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}" \
    meson setup build \
        --prefix="$PREFIX" \
        --libdir=lib \
        --buildtype=release \
        -Ddefault_library=shared \
        -Ddemos=false \
        -Dtests=false \
        -Dvulkan=disabled \
        -Dd3d11=disabled \
        -Dopengl=enabled \
        -Dgl-proc-addr=enabled \
        -Dshaderc=disabled \
        -Dglslang=disabled \
        -Dlcms=enabled \
        -Dlibdovi=disabled \
        -Ddovi=disabled \
        -Dunwind=disabled \
        -Dxxhash=disabled
    meson compile -C build -j "$JOBS"
    meson install -C build
)

log "Building mpv $MPV_TAG (LGPL, libmpv only)"
(
    cd "$MPV_SRC"
    rm -rf build
    PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}" \
    meson setup build \
        --prefix="$PREFIX" \
        --libdir=lib \
        --buildtype=release \
        -Ddefault_library=shared \
        -Dlibmpv=true \
        -Dcplayer=false \
        -Dgpl=false \
        -Dlibbluray=enabled \
        -Dzimg=enabled \
        -Dlcms2=enabled \
        -Dalsa=enabled \
        -Dpulse=enabled \
        -Dpipewire=enabled \
        -Dlibarchive=disabled \
        -Djavascript=disabled \
        -Dlua=luajit \
        -Dopenal=disabled \
        -Duchardet=disabled \
        -Dlibcurl=disabled \
        -Dvapoursynth=disabled \
        -Ddvdnav=disabled \
        -Dcdda=disabled \
        -Drubberband=disabled \
        -Dvulkan=disabled \
        -Dvaapi=disabled \
        -Dvdpau=disabled \
        -Dcuda-hwaccel=disabled \
        -Dcuda-interop=disabled \
        -Degl=disabled \
        -Ddrm=disabled \
        -Dwayland=disabled \
        -Dx11=disabled \
        -Dgl-x11=disabled \
        -Dlibavdevice=disabled
    meson compile -C build -j "$JOBS"
)

LIBMPV="$MPV_SRC/build/libmpv.so.2"
if [ ! -e "$LIBMPV" ]; then
    echo "libmpv.so.2 was not produced" >&2
    find "$MPV_SRC/build" -maxdepth 2 -name 'libmpv*' -ls
    exit 1
fi

log "Collecting libmpv and its private runtime dependencies"
cp -L "$LIBMPV" "$BUNDLE/libmpv.so.2"

# ldd needs the build prefix to resolve FFmpeg/libplacebo while collecting.
LD_LIBRARY_PATH="$PREFIX/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
    ldd "$BUNDLE/libmpv.so.2" |
    awk '/=> \// { print $3 } /^[[:space:]]+\/.*\.so/ { print $1 }' |
    sort -u |
    while read -r lib; do
        name=$(basename "$lib")
        case "$name" in
            # glibc and the dynamic loader are provided by the host.
            libc.so.*|libm.so.*|libdl.so.*|libpthread.so.*|librt.so.*|libresolv.so.*|libutil.so.*|libanl.so.*|libnss_*.so.*|ld-linux*) continue ;;
            # Host graphics/audio driver interfaces.
            libGL.so.*|libEGL.so.*|libGLES*.so.*|libGLX*.so.*|libGLdispatch.so.*|libOpenGL.so.*|libgbm.so.*|libdrm.so.*|libvulkan.so.*|libX11*.so.*|libxcb*.so.*|libXau.so.*|libXdmcp.so.*|libwayland*.so.*|libxkbcommon.so.*|libasound.so.*|libpulse*.so.*|libpipewire*.so.*|libjack.so.*|libsndio.so.*|libva*.so.*|libvdpau.so.*|libvpl.so.*|libOpenCL.so.*|libcuda.so.*|libnvidia*.so.*) continue ;;
            # Transitive clients of the host audio stack; not used once the
            # audio driver libraries above are left to the host.
            libpulsecommon*|libsndfile*|libFLAC*|libmpg123*|libmp3lame*|libogg*|libvorbis*|libopus*|libasyncns*|libapparmor*|libsystemd*|libdbus-1*|libcap.so.*|libgcrypt*|libgpg-error*|libbsd*|libmd*|liblz4*|libzstd*) continue ;;
        esac
        cp -L "$lib" "$BUNDLE/$name"
    done

# Make every library load its sibling dependencies first, including when the
# consumer does not set LD_LIBRARY_PATH (the AvaStudio AppRun still sets it).
for f in "$BUNDLE"/*.so*; do
    patchelf --set-rpath '$ORIGIN' "$f"
done

cp "$MPV_SRC/LICENSE.LGPL" "$BUNDLE/LICENSE.LGPL"
cp "$FFMPEG_SRC/COPYING.LGPLv2.1" "$BUNDLE/LICENSE.FFmpeg.LGPL"
cp "$LIBPLACEBO_SRC/LICENSE" "$BUNDLE/LICENSE.libplacebo"
cat > "$BUNDLE/SOURCE.txt" <<EOF
LGPL libmpv runtime bundle

mpv:        $MPV_TAG (LGPL-2.1-or-later, built with -Dgpl=false)
FFmpeg:     $FFMPEG_TAG (LGPL-2.1-or-later, built without --enable-gpl)
libplacebo: $LIBPLACEBO_TAG (LGPL-2.1-or-later)

Build scripts and source pinning:
https://github.com/WangWindow/libmpv-bundles
EOF

log "Checking the collected bundle"
if LD_LIBRARY_PATH="$BUNDLE" ldd "$BUNDLE/libmpv.so.2" | grep -q 'not found'; then
    LD_LIBRARY_PATH="$BUNDLE" ldd "$BUNDLE/libmpv.so.2" | grep 'not found'
    exit 1
fi

output="$DIST/libmpv-$RID.tar.gz"
rm -f "$output"
tar -C "$BUNDLE" -czf "$output" .
log "Created $output"
tar -tzf "$output" | sed -n '1,80p'
