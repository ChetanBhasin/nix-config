{
  alsa-lib,
  at-spi2-core,
  autoPatchelfHook,
  cairo,
  dbus,
  fetchurl,
  fontconfig,
  freetype,
  gdk-pixbuf,
  glib,
  gtk3,
  lib,
  libX11,
  libXcomposite,
  libXdamage,
  libXext,
  libXfixes,
  libXi,
  libXcursor,
  libXrandr,
  libXrender,
  libxcb,
  pango,
  stdenvNoCC,
}:

let
  version = "1.22.1b";
  system = stdenvNoCC.hostPlatform.system;
  assets = {
    "aarch64-linux" = "zen.linux-aarch64.tar.xz";
    "x86_64-linux" = "zen.linux-x86_64.tar.xz";
  };
  # No signature ships with the release; each SRI hash was computed from
  # the official GitHub release asset for this version.
  hashes = {
    "aarch64-linux" = "sha256-EvkiV6EX5OhIgDNFOBKpRNKKb7pHqvfkBHw8boAd7cM=";
    "x86_64-linux" = "sha256-GdOSNArIr7/a45Mlm/ucS6OThEx3x+7j/b2FjNJgKK4=";
  };
  asset = assets.${system} or (throw "zen does not provide a binary for ${system}");
in
stdenvNoCC.mkDerivation {
  pname = "zen";
  inherit version;

  src = fetchurl {
    url = "https://github.com/zen-browser/desktop/releases/download/${version}/${asset}";
    hash = hashes.${system};
  };

  dontBuild = true;

  # The tarball is a self-contained Mozilla app: a small `zen` bootstrap
  # (byte-identical to `zen-bin`) plus `libxul.so` and every other resource
  # in one directory. The bootstrap locates its siblings relative to its
  # resolved path (/proc/self/exe), so the directory must stay intact.
  # autoPatchelfHook rewrites the system-library references of the bundled
  # shared objects (GTK, X11, ...) to store paths; the Mozilla libraries
  # that ship inside the tarball keep their bare SONAMEs.
  nativeBuildInputs = [
    autoPatchelfHook
    alsa-lib
    at-spi2-core
    cairo
    dbus
    fontconfig
    freetype
    gdk-pixbuf
    glib
    gtk3
    libX11
    libXcomposite
    libXdamage
    libXext
    libXfixes
    libXi
    libXcursor
    libXrandr
    libXrender
    libxcb
    pango
  ];

  installPhase = ''
    runHook preInstall

    # Keep the app directory intact under $out/lib/zen and expose the
    # bootstrap on PATH through a symlink, so /proc/self/exe still
    # resolves inside the app directory at runtime. The source root (the
    # tarball's single top-level directory) is the current directory.
    install -d "$out/lib/zen"
    cp -a . "$out/lib/zen/"
    install -d "$out/bin"
    ln -s ../lib/zen/zen "$out/bin/zen"

    # Minimal desktop entry so the browser shows up in app pickers.
    install -d "$out/share/applications"
    cat > "$out/share/applications/zen.desktop" <<'EOF'
[Desktop Entry]
Version=1.0
Name=Zen
Comment=Web browser
Exec=zen %U
Terminal=false
Type=Application
Categories=Network;WebBrowser;
MimeType=x-scheme-handler/http;x-scheme-handler/https;
Icon=zen
EOF

    install -d "$out/share/icons/hicolor/48x48/apps"
    ln -s "$out/lib/zen/browser/chrome/icons/default/default48.png" \
      "$out/share/icons/hicolor/48x48/apps/zen.png"

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    test "$($out/bin/zen --version | awk '{print $NF}')" = "${version}"
    runHook postInstallCheck
  '';

  meta = {
    description = "Privacy-first, Firefox-based web browser with Spaces and split views";
    homepage = "https://zen-browser.app/";
    changelog = "https://github.com/zen-browser/desktop/releases/tag/${version}";
    license = lib.licenses.mpl20;
    mainProgram = "zen";
    platforms = builtins.attrNames assets;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
