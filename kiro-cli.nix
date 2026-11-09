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
    # Since 3.x the zip ships a single kiro-cli binary. 2.x also shipped
    # kiro-cli-chat and kiro-cli-term next to it; install those if present.
    install -m755 bin/kiro-cli $out/bin
    for extra in kiro-cli-chat kiro-cli-term; do
      if [ -e "bin/$extra" ]; then
        install -m755 "bin/$extra" $out/bin
      fi
    done
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
