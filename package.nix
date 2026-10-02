{
  lib,
  stdenv,
  fetchurl,
  appimageTools,
  kiro-cli,
}:

let
  sourcesJson = lib.importJSON ./sources.json;
  pname = "kirocrew-desktop";
  inherit (sourcesJson) version;
  src =
    sourcesJson.sources.${stdenv.hostPlatform.system}
      or (throw "kiro-crew: unsupported system ${stdenv.hostPlatform.system}");
  appimage = fetchurl { inherit (src) url hash; };
  appimageContents = appimageTools.extract {
    inherit pname version;
    src = appimage;
  };
in
appimageTools.wrapType2 {
  inherit pname version;
  src = appimage;

  # The gateway finds Kiro CLI with shutil.which("kiro-cli"). extraPkgs
  # lands that binary on /usr/bin inside the FHS, which stays on PATH
  # after the bubblewrap profile prepends /usr/bin.
  extraPkgs = pkgs: [
    pkgs.libsecret
    kiro-cli
  ];

  extraInstallCommands = ''
    install -Dm444 ${appimageContents}/kirocrew-desktop.desktop \
      $out/share/applications/kirocrew-desktop.desktop
    sed -i -E \
      -e 's|^Exec=.*|Exec=kirocrew-desktop %U|' \
      -e 's|^Icon=.*|Icon=kirocrew-desktop|' \
      $out/share/applications/kirocrew-desktop.desktop

    find ${appimageContents}/usr/share/icons/hicolor -type f -name 'kirocrew-desktop.png' |
      while read -r icon; do
        rel=''${icon#${appimageContents}/usr/}
        install -Dm444 "$icon" "$out/$rel"
      done

    install -Dm444 \
      ${appimageContents}/usr/share/icons/hicolor/128x128/apps/kirocrew-desktop.png \
      $out/share/pixmaps/kirocrew-desktop.png

    # wrapType2 execs the binary and skips AppRun. AppRun adds --no-sandbox
    # when user namespaces are unavailable, which they are on NixOS, and
    # Electron registers the window class against CHROME_DESKTOP.
    mv $out/bin/kirocrew-desktop $out/bin/.kirocrew-desktop-bwrap
    cat > $out/bin/kirocrew-desktop <<EOF
    #!/bin/sh
    export CHROME_DESKTOP="\''${CHROME_DESKTOP:-kirocrew-desktop.desktop}"
    flags="--no-sandbox"
    if [ -n "\''${NIXOS_OZONE_WL:-}" ] && [ -n "\''${WAYLAND_DISPLAY:-}" ]; then
      flags="\$flags --ozone-platform-hint=auto --enable-features=WaylandWindowDecorations --enable-wayland-ime=true"
    fi
    exec $out/bin/.kirocrew-desktop-bwrap \$flags "\$@"
    EOF
    chmod +x $out/bin/kirocrew-desktop

    # Same binaries, on the host PATH, so `kiro-cli login` works from a
    # normal shell once the desktop package is installed.
    ln -s ${kiro-cli}/bin/kiro-cli $out/bin/kiro-cli
    ln -s ${kiro-cli}/bin/kiro-cli-chat $out/bin/kiro-cli-chat
    ln -s ${kiro-cli}/bin/kiro-cli-term $out/bin/kiro-cli-term
  '';

  meta = {
    description = "Kiro Crew desktop app";
    homepage = "https://kiro.dev/docs/crew/";
    downloadPage = "https://download.crew.kiro.dev/desktop/stable/latest/KiroCrew-x86_64.AppImage";
    license = lib.licenses.asl20;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    mainProgram = "kirocrew-desktop";
  };
}
