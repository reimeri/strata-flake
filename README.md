# Strata for NixOS

A flake packaging [Strata](https://github.com/lgse/strata) **v1.1.1** for
`x86_64-linux` and `aarch64-linux`. Requires Nix with flakes enabled and a
graphical session with session D-Bus.

## Run or install

```sh
# Run without installing, optionally opening a directory.
nix run github:reimeri/strata-flake#strata -- "$HOME/Documents"

# Install for your user.
nix profile add github:reimeri/strata-flake#strata
strata

# From a local checkout:
nix build .#strata
./result/bin/strata --version
nix run .#strata
```

On older Nix releases, use `nix profile install` instead of `nix profile add`.
The package includes a desktop entry and icon. Use `nix profile list` and
`nix profile remove <entry-name>` to manage installations.

The first source build can take several minutes and substantial memory; use
`nix build .#strata --cores 4` to limit parallelism. Installing the package alone
**does not change your default file manager or file chooser**.

## NixOS setup

Add the input to your system flake and include `strata` in its `outputs` arguments:

```nix
inputs.strata.url = "github:reimeri/strata-flake";
```

Add these entries to your existing `nixosConfigurations.<hostname>.modules` list:

```nix
strata.nixosModules.default
({ ... }: {
  programs.strata = {
    enable = true;
    # Optional, independent integrations; both default to false.
    defaultFileManager = true;
    fileChooser.enable = true;
  };

  # Recommended for network locations, trash, and removable media.
  services.gvfs.enable = true;
  services.udisks2.enable = true;
})
```

For installation only, omit the optional integrations. No separate
`environment.systemPackages` entry is needed. Do not make this input follow an
older system nixpkgs: it needs recent Rust/GTK.

```sh
sudo nixos-rebuild switch --flake /path/to/system-config#hostname
```

**Log out and back in** after enabling integrations. Use Nix, not Strata's
**Complete setup** / **Restore default** buttons: its installer may reject store
paths and status indicators may miss system-wide setup. Do not change store
permissions to work around this.

### Module options

All options below are under `programs.strata`:

| Option                  | Default                    | Purpose                                                    |
| ----------------------- | -------------------------- | ---------------------------------------------------------- |
| `enable`                | `false`                    | Install Strata                                             |
| `package`               | Flake's Strata package     | Override the package                                       |
| `defaultFileManager`    | `false`                    | Folder MIME default and preferred FileManager1 provider    |
| `fileChooser.enable`    | `false`                    | Select Strata for portal-aware file dialogs                |
| `fileChooser.desktops`  | Enabled supported desktops | Portal configuration targets                               |
| `fileChooser.fallbacks` | `[]`                       | Already-installed backends after Strata; not live failover |

Desktop detection uses NixOS options: GNOME → `gnome`, Plasma 6 → `kde`,
Hyprland → `hyprland`, Niri → `niri`. An explicit list replaces detection:

```nix
programs.strata.fileChooser.desktops = [ "niri" ];
```

For other desktops, supply a target and a complete base configuration through
`xdg.portal.config.<desktop>`, `xdg.portal.config.common`, or
`xdg.portal.configPackages`, with the referenced backends installed. Use `common`
to target generic `portals.conf`; desktop-specific files can take precedence.
Configure preferences through those options, not conflicting `environment.etc`
portal files. The module changes only FileChooser, preserving other preferences.

User preferences or an already-running file manager can override these defaults.
Native, non-portal dialogs are unchanged. Test `xdg-open "$HOME"`, browser
**Reveal/Open Containing Folder**, and portal-aware open/save dialogs. Portal logs:
`journalctl --user -b -u xdg-desktop-portal.service`. Previews need user namespaces
or a system-managed bubblewrap wrapper; do not disable isolation.
Disable the options and rebuild to remove integrations.

## Home Manager and overlay

With `strata` available in your Home Manager module:

```nix
home.packages = [ strata.packages.${pkgs.stdenv.hostPlatform.system}.strata ];
```

`strata.overlays.default` provides `pkgs.strata` using your nixpkgs and unfree
policy. It needs recent Rust/GTK and an unfree exception for
`lib.getName pkg == "strata"`; preserve existing exceptions. Set
`programs.strata.package = pkgs.strata;` to use it in the NixOS module.

## Updates and checks

Update your system flake's `strata` input lock and rebuild to pick up changes.
Updating nixpkgs alone does not upgrade the pinned Strata version.
`nix flake check` checks version/packaging, not desktop routing.
