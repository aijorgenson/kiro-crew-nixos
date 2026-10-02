{
  lib,
  stdenv,
  fetchurl,
  unzip,
  autoPatchelfHook,
}:

let
  sourcesJson = lib.importJSON ./sources.json;
  cli = sourcesJson.kiroCli;
  srcInfo =
    cli.sources.${stdenv.hostPlatform.system}
      or (throw "kiro-cli: unsupported system ${stdenv.hostPlatform.system}");
in
stdenv.mkDerivation {
  pname = "kiro-cli";
  inherit (cli) version;

  src = fetchurl { inherit (srcInfo) url hash; };

  # GNU build. NixOS glibc is newer than the 2.34 / 2.39 floor these
  # binaries require. The musl zips are the installer's fallback for
  # older glibc, not what we want here.
  nativeBuildInputs = [
    unzip
    autoPatchelfHook
  ];

  buildInputs = [ stdenv.cc.cc.lib ];

  sourceRoot = "kirocli";

  dontBuild = true;
  # The chat binary is a large Rust executable. Stripping it is slow and
  # unnecessary for a prebuilt.
  dontStrip = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    # q and qchat in the zip are shell wrappers hardcoded to ~/.local/bin.
    # Crew looks up the name kiro-cli, and that binary calls the other two
    # next to it.
    install -m755 bin/kiro-cli bin/kiro-cli-chat bin/kiro-cli-term $out/bin
    runHook postInstall
  '';

  meta = {
    description = "Kiro CLI, the terminal agent Kiro Crew talks to";
    homepage = "https://kiro.dev/cli/";
    downloadPage = "https://cli.kiro.dev/install";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    mainProgram = "kiro-cli";
  };
}
