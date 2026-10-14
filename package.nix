{ lib
, rustPlatform
, fetchFromGitHub
, pkg-config
, wrapGAppsHook4
, glib
, gtk4
, gtksourceview5
, poppler
, fontconfig
, gst_all_1
, gdk-pixbuf
, bubblewrap
, util-linux
, ffmpeg
, ffmpegthumbnailer
, imagemagick
, libraw
, squashfsTools
, bash
, coreutils
, xdg-utils
, runCommand
}:
let
  # These directories are compiled into Strata, not taken from a user's PATH.
  previewTools = [
    ffmpeg ffmpegthumbnailer imagemagick libraw squashfsTools
    util-linux coreutils fontconfig
  ];
  trustedTools = [ bubblewrap bash coreutils xdg-utils ] ++ previewTools;
  gstPlugins = with gst_all_1; [
    gst-plugins-base
    gst-plugins-good
    gst-plugins-bad
    gst-libav
  ];
in
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "strata";
  version = "1.0.0";

  src = fetchFromGitHub {
    owner = "lgse";
    repo = "strata";
    # Commit underlying the annotated v1.0.0 tag.
    rev = "0a086aa3bdb251842a1e8413e2a6b35970d0b409";
    hash = "sha256-dFNsFCnkeZs0VwmYRyu+6Jh8XxJzv+agUlP70Fdxa5Q=";
  };

  cargoHash = "sha256-vuhHierqb4WsMdg890NpkaztYnfsnck2FxMz5cPMwCQ=";

  patches = [ ./patches/wrapper-aware-activation.patch ];

  nativeBuildInputs = [ pkg-config wrapGAppsHook4 glib ];
  buildInputs = [
    gtk4
    gtksourceview5
    poppler
    fontconfig
    gdk-pixbuf
    gst_all_1.gstreamer
    gst_all_1.gst-plugins-base
  ] ++ gstPlugins;

  # Preserve upstream's default features, including statically linked UnRAR.
  STRATA_BUILD_COMMIT = finalAttrs.src.rev;
  STRATA_RELEASE_TAG = "v${finalAttrs.version}";
  STRATA_BUILD_KIND = "stable";
  STRATA_SANDBOX_ROOT = "/nix/store";
  STRATA_SANDBOX_PATH = lib.makeBinPath previewTools;
  STRATA_SANDBOX_PRLIMIT = "${lib.getBin util-linux}/bin/prlimit";
  STRATA_SANDBOX_GDK_PIXBUF_MODULE_FILE = "${gdk-pixbuf}/lib/gdk-pixbuf-2.0/2.10.0/loaders.cache";

  postPatch = ''
    # Upstream deliberately ignores PATH when looking up trusted host tools.
    # Keep its NixOS setuid-wrapper precedence; append immutable store paths.
    substituteInPlace src/trusted_command.rs \
      --replace-fail '    "/run/current-system/profile/bin",' \
        '    "/run/current-system/profile/bin",
${lib.concatMapStringsSep "\n" (pkg: "    \"${lib.getBin pkg}/bin\",") trustedTools}'
  '';

  preFixup = ''
    gappsWrapperArgs+=(--prefix GST_PLUGIN_SYSTEM_PATH_1_0 : "${lib.makeSearchPath "lib/gstreamer-1.0" gstPlugins}")
  '';

  postInstall = ''
    install -Dm644 data/io.github.lgse.Strata.desktop \
      "$out/share/applications/io.github.lgse.Strata.desktop"
    substituteInPlace "$out/share/applications/io.github.lgse.Strata.desktop" \
      --replace-fail 'Exec=strata %U' "Exec=$out/bin/strata %U"
    install -Dm644 data/icons/scalable/apps/io.github.lgse.Strata.svg \
      "$out/share/icons/hicolor/scalable/apps/io.github.lgse.Strata.svg"
    # A shared FileManager1 provider must be enabled explicitly, not compete
    # with an existing file manager merely because Strata was installed.
    install -Dm644 data/io.github.lgse.Strata.FileManager1.service \
      "$out/share/strata/io.github.lgse.Strata.FileManager1.service"
    substituteInPlace "$out/share/strata/io.github.lgse.Strata.FileManager1.service" \
      --replace-fail '/usr/bin/strata' "$out/bin/strata"

    install -Dm644 LICENSE "$out/share/licenses/strata/LICENSE"
    install -Dm644 THIRD_PARTY_LICENSES.md "$out/share/licenses/strata/THIRD_PARTY_LICENSES.md"
    cp -r data/licenses "$out/share/licenses/strata/third-party"
    mkdir -p "$out/share/strata"
    cat > "$out/share/strata/install-source.toml" <<'MARKER'
    manager = "Nix"
    package = "strata"
    channel = "stable"
    MARKER
  '';

  # Upstream's full test suite requires a desktop/session and sandbox access.
  # Use a display-independent installed-binary check below instead.
  doCheck = false;
  passthru.bubblewrap = bubblewrap;
  passthru.tests.version = runCommand "strata-version-check" { } ''
    ${finalAttrs.finalPackage}/bin/strata --version | tee "$out"
    grep -Fx 'strata ${finalAttrs.version}' "$out"
  '';

  passthru.tests.packaging = runCommand "strata-packaging-check" { } ''
    pkg=${finalAttrs.finalPackage}
    test -x "$pkg/bin/strata"
    test -s "$pkg/share/applications/io.github.lgse.Strata.desktop"
    test -s "$pkg/share/icons/hicolor/scalable/apps/io.github.lgse.Strata.svg"
    grep -Fx "Exec=$pkg/bin/strata %U" "$pkg/share/applications/io.github.lgse.Strata.desktop"
    grep -F "$pkg/bin/strata" "$pkg/share/strata/io.github.lgse.Strata.FileManager1.service"
    grep -Fx 'manager = "Nix"' "$pkg/share/strata/install-source.toml"
    test -s "$pkg/share/licenses/strata/third-party/UnRAR.txt"
    test -s "${gdk-pixbuf}/lib/gdk-pixbuf-2.0/2.10.0/loaders.cache"
    ${lib.concatMapStringsSep "\n" (tool: "test -x ${tool}") [
      "${lib.getBin bubblewrap}/bin/bwrap"
      "${lib.getBin util-linux}/bin/prlimit"
      "${lib.getBin ffmpeg}/bin/ffmpeg"
      "${lib.getBin ffmpeg}/bin/ffprobe"
      "${lib.getBin ffmpegthumbnailer}/bin/ffmpegthumbnailer"
      "${lib.getBin imagemagick}/bin/magick"
      "${lib.getBin libraw}/bin/simple_dcraw"
      "${lib.getBin squashfsTools}/bin/unsquashfs"
      "${lib.getBin coreutils}/bin/nice"
      "${lib.getBin fontconfig}/bin/fc-list"
    ]}
    touch "$out"
  '';

  meta = {
    description = "A fast, keyboard-first file manager for Linux";
    homepage = "https://github.com/lgse/strata";
    changelog = "https://github.com/lgse/strata/releases/tag/v${finalAttrs.version}";
    # The application is MIT; the default binary also contains non-free UnRAR.
    license = [ lib.licenses.mit lib.licenses.unfree ];
    mainProgram = "strata";
    platforms = lib.platforms.linux;
  };
})
