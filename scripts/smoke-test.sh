#!/usr/bin/env bash
# Exercise installed helpers with Strata's Nix runtime and bubblewrap isolation.
# Run outside the Nix build sandbox; nested user namespaces may be restricted.
set -euo pipefail
cd "$(dirname "$0")/.."
pkg=$(nix build .#strata --no-link --print-out-paths)
src=$(nix build .#strata.src --no-link --print-out-paths)
runtime_path=$(nix eval --raw .#strata.STRATA_SANDBOX_PATH)
prlimit=$(nix eval --raw .#strata.STRATA_SANDBOX_PRLIMIT)
loaders=$(nix eval --raw .#strata.STRATA_SANDBOX_GDK_PIXBUF_MODULE_FILE)
bwrap_pkg=$(nix build .#strata.bubblewrap --no-link --print-out-paths)
bwrap="$bwrap_pkg/bin/bwrap"
if [[ -x /run/wrappers/bin/bwrap ]]; then bwrap=/run/wrappers/bin/bwrap; fi
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir "$work/output"
# PPM exercises native image thumbnail generation (GdkPixbuf or a fallback).
printf 'P3\n2 2\n255\n255 0 0  0 255 0  0 0 255  255 255 255\n' > "$work/image.ppm"
# Use the package's FFmpeg, without requiring one in the user's profile.
PATH="$runtime_path" ffmpeg -hide_banner -loglevel error \
  -f lavfi -i 'sine=frequency=440:duration=0.2' "$work/audio.wav"

sandbox() {
  local input=$1; shift
  timeout 30s "$bwrap" --unshare-all --die-with-parent --new-session --clearenv \
    --setenv PATH "$runtime_path" --setenv HOME /nonexistent \
    --setenv XDG_CACHE_HOME /tmp/cache --setenv MALLOC_ARENA_MAX 1 \
    --setenv GDK_PIXBUF_MODULE_FILE "$loaders" \
    --proc /proc --dev /dev --size 536870912 --tmpfs /tmp \
    --dir /app --dir /etc \
    --ro-bind /nix/store /nix/store \
    --ro-bind-try /etc/fonts /etc/fonts \
    --ro-bind-try /var/cache/fontconfig /var/cache/fontconfig \
    --ro-bind "$pkg/bin/.strata-wrapped" /app/strata \
    --ro-bind "$input" "/input.${input##*.}" \
    --bind "$work/output" /output \
    -- "$prlimit" --as=2147483648 --cpu=10 --fsize=536870912 -- \
    /app/strata --preview-helper "$@"
}

"$pkg/bin/strata" --version
sandbox "$work/image.ppm" thumbnail-image /input.ppm /output/image.png 128 software
test -s "$work/output/image.png"
sandbox "$src/tests/fixtures/documents/text.pdf" thumbnail-pdf /input.pdf /output/pdf.png 128 software
test -s "$work/output/pdf.png"
sandbox "$work/audio.wav" audio-peaks /input.wav /output/peaks 0 software
test -s "$work/output/peaks"
sandbox "$src/tests/fixtures/rar/version.rar" extract-rar /input.rar > "$work/rar-stream"
test -s "$work/rar-stream"
grep -aF VERSION "$work/rar-stream" >/dev/null
grep -aF unrar-0.4.0 "$work/rar-stream" >/dev/null
printf 'Sandbox image, PDF, audio peaks and RAR streaming extraction checks passed.\n'
