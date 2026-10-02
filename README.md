# kiro-crew for NixOS

> [Kiro Crew](https://kiro.dev/docs/crew/) desktop on NixOS, wrapping the
> official Linux AppImage. A GitHub Action bumps the pin when a new stable
> build ships.

Kiro publishes a Linux AppImage next to `.deb` and `.rpm` builds. This flake
takes the AppImage and wraps it in an FHS environment. The current pin is in
`sources.json`.

- [Try it without installing](#try-it-without-installing)
- [Add it to your flake](#add-it-to-your-flake)
- [Updating](#updating)
- [License](#license)

## Try it without installing

```sh
nix run github:aijorgenson/kiro-crew-nixos
```

`nix run` starts the desktop app. The app opens its own window and starts the
gateway it ships with. It does not install a system service.

The app looks up `kiro-cli` on `PATH`. This package bundles the official
[Kiro CLI](https://kiro.dev/cli/) binary, so that check passes without a
separate install. Sign in once with `kiro-cli login`. Installing the desktop
package puts `kiro-cli` on `PATH` as well.

## Add it to your flake

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    kiro-crew = {
      url = "github:aijorgenson/kiro-crew-nixos";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, kiro-crew, ... }: {
    nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./configuration.nix
        kiro-crew.nixosModules.default
      ];
    };
  };
}
```

Kiro CLI is published under the AWS Intellectual Property License, so the
package is unfree. This flake allows that one package for `nix build` and
`nix run`. A NixOS config that pulls the overlay needs the same exception:

```nix
{ lib, ... }:
{
  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (lib.getName pkg) [ "kiro-cli" ];
}
```

Linux only: `x86_64-linux` and `aarch64-linux`.

On Wayland, set `environment.sessionVariables.NIXOS_OZONE_WL = "1";` and the
wrapper adds the usual Ozone flags.

## Updating

`sources.json` pins the desktop AppImage and the Kiro CLI zip for each Linux
arch. A scheduled Action checks both once a day, and when either version
moved, runs `./update-package.sh`, builds, and pushes straight to `main`.

The desktop feed is `https://updates.crew.kiro.dev/feed/stable/latest-cli.json`,
and the script verifies its signature before prefetching. The AppImages are
`KiroCrew-x86_64.AppImage` and `KiroCrew-aarch64.AppImage` under
`https://download.crew.kiro.dev/desktop/stable/<version>/`.

Kiro CLI is a separate product with its own version. The script reads
`https://prod.download.cli.kiro.dev/stable/latest/manifest.json` and pins the
headless GNU zip, checking the manifest sha256 against the download.

Requirements for the Action:

- **Settings → Actions → General → Workflow permissions** = "Read and write
  permissions"
- If `main` is protected, allow `github-actions[bot]` to push

Trigger it by hand from the Actions tab ("Run workflow").

### Manual

```sh
./update-package.sh
```

It fetches the latest stable desktop manifest, verifies the signature,
fetches the Kiro CLI manifest, prefetches whichever archives moved, writes
`sources.json`, and `nix build`s. Nothing is committed.

## License

The Nix expressions and scripts in this repo are [MIT](LICENSE). That covers
the packaging only.

Kiro Crew itself is Apache-2.0. Kiro CLI is under the AWS Intellectual
Property License. This flake does not ship either binary; Nix downloads them
at build time. The AppImage bundles Electron and Chromium under their own
licenses. This project is unofficial and not affiliated with AWS or the Kiro
team.

---

> Built and tested on `x86_64-linux`.
