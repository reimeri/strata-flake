# Strata for NixOS

A reproducible source package of [Strata](https://github.com/lgse/strata)
**v1.0.0**, pinned to release commit
`0a086aa3bdb251842a1e8413e2a6b35970d0b409`. Nixpkgs is pinned in `flake.lock`;
upstream source and Cargo dependencies have fixed hashes.

Upstream's default **RAR support is enabled**. Strata itself is MIT-licensed,
but the resulting binary includes non-free UnRAR. This flake permits only the
`strata` unfree exception in its own package outputs; no `--impure` or global
`allowUnfree` setting is needed for the commands below. License notices are
installed under `share/licenses/strata`.

## Run directly from GitHub

With Nix flakes enabled:

```sh
nix run github:reimeri/strata-flake#strata
# Or build without installing:
nix build github:reimeri/strata-flake#strata
```

## Build and run

From this directory, with Nix flakes enabled:

```sh
nix build .#strata
./result/bin/strata --version
nix run .#strata
# Open a particular directory:
nix run .#strata -- "$HOME/Documents"
```

`nix run .` and `nix build .` also work. The first source build can take several
minutes and uses substantial memory (GTK's Rust bindings and release LTO).
To limit build parallelism, use `nix build .#strata --cores 4`.

These commands do not install anything into your system configuration or user
profile. They do download/build into the Nix store. GUI use requires your normal
graphical session and session D-Bus.

## Install for your user

```sh
nix profile add github:reimeri/strata-flake#strata
strata
```

On older Nix releases,
`nix profile install` is the equivalent of `nix profile add`.
The package includes a desktop entry and icon. If your launcher does not notice
profile changes immediately, log out and back in. `nix profile list` shows the
installed entry; remove it with `nix profile remove <entry-name>`.

## Install declaratively on NixOS

Add this flake as an input to your **system flake**:

```nix
inputs.strata.url = "github:reimeri/strata-flake";
```

Include `strata` in its `outputs` arguments, then add a module to the desired
`nixosConfigurations.<hostname>.modules` list:

```nix
({ pkgs, ... }: {
  environment.systemPackages = [
    strata.packages.${pkgs.stdenv.hostPlatform.system}.strata
  ];

  # Recommended for network locations, trash, and removable-media integration.
  services.gvfs.enable = true;
  services.udisks2.enable = true;
})
```

Rebuild with your usual command, for example:

```sh
sudo nixos-rebuild switch --flake /path/to/system-config#hostname
```

The package output has its own scoped unfree approval, so this approach does
not require enabling all unfree software in your system configuration.
**Do not make this input follow an older system nixpkgs**: the pinned package
needs recent Rust and GTK libraries.

### Make Strata the default file manager and file chooser

The flake exports a **NixOS module**, with no Home Manager dependency. Add it to
`nixosConfigurations.<hostname>.modules` alongside your existing desktop modules:

```nix
strata.nixosModules.default

({ ... }: {
  programs.strata = {
    enable = true;
    defaultFileManager = true;
    fileChooser.enable = true;
  };
})
```

Here `strata` is the flake input from your system flake's `outputs` arguments.
`nixosModules.strata` is an alias. The module installs the pinned package, so a
separate Strata entry in `environment.systemPackages` is unnecessary. The default
package retains the flake's scoped unfree approval; it does not enable unfree
software globally. `programs.strata.package` can override it explicitly.

Both integrations are **opt-in** and independent:

| Option | Default | Effect |
| --- | --- | --- |
| `programs.strata.enable` | `false` | Install Strata only |
| `programs.strata.defaultFileManager` | `false` | Set the folder MIME default and register a preferred FileManager1 provider for Reveal/Open Containing Folder |
| `programs.strata.fileChooser.enable` | `false` | Register and select Strata's FileChooser portal in the targeted sessions |
| `programs.strata.fileChooser.desktops` | Auto-detected | All enabled GNOME (`gnome`), Plasma 6 (`kde`), Hyprland (`hyprland`), and Niri (`niri`) desktops |
| `programs.strata.fileChooser.fallbacks` | `[]` | Explicitly chosen, installed FileChooser backends after Strata |

Automatic detection uses NixOS desktop enable options, **not the session running
when you build**. On a machine with GNOME and Niri enabled, both sessions are
selected. To restrict it to Niri, or configure another desktop, set an explicit
list (which replaces automatic detection):

```nix
programs.strata.fileChooser = {
  enable = true;
  desktops = [ "niri" ];
  # Optional; only list backends already installed for the target sessions.
  # fallbacks = [ "gtk" ];
};
```

If no supported desktop is enabled, you must supply `desktops`. Other desktop
targets also need a complete declarative base configuration in
`xdg.portal.config.<desktop>`, `xdg.portal.config.common`, or
`xdg.portal.configPackages`, and the backends it references. The special target
`"common"` updates the generic `portals.conf`; desktop-specific configurations
can still take precedence over it.

**Existing portal preferences are preserved.** The module selects the complete
base configuration using explicit NixOS settings first, otherwise package-shipped
settings with profile priority/output selection. It changes only
`org.freedesktop.impl.portal.FileChooser`. It does not replace ScreenCast,
Screenshot, Secret, Notification, or the desktop's default backend; nor does it
force applications to use portals. FileChooser fallbacks are for backend
selection, not live failover when a selected backend crashes.

Files are generated in the Nix store and linked through `/etc`; no activation
script edits your home directory or copies live desktop settings. Custom portal
files declared directly through `environment.etc` for a targeted desktop (or the
generic config) are rejected rather than silently discarded. Express those
preferences through `xdg.portal.config` or `xdg.portal.configPackages` instead.
User portal configuration can still override system configuration.

For FileManager1, a separate registration directory is prepended to the session's
`XDG_DATA_DIRS` and the NixOS D-Bus package list. It is **not** merged into the
system profile's D-Bus service directory, where another file manager may provide
the same shared name. Per-user registrations still take precedence; a running
file manager already owning the name is not displaced. User MIME defaults also
override the system folder default. No other file manager is removed or stopped.

After rebuilding, **log out and back in** to load the new session paths and
release any existing FileManager1 owner. Disable the corresponding options and
rebuild to remove these system integrations. No per-user installer state needs
to be restored, but user overrides remain yours to manage.

#### Test on your desktop

Manage integration through Nix, **not** Strata's **Complete setup** or
**Restore default** buttons. Upstream's status indicators look primarily for
per-user registration files, so they may still show crosses even when this
system-wide integration works. The UI is intentionally unchanged.

After a rebuild and fresh login:

```sh
# Expected: io.github.lgse.Strata.desktop
xdg-mime query default inode/directory
xdg-open "$HOME"

# Activate FileManager1 and open a folder through its interface.
busctl --user call org.freedesktop.FileManager1 /org/freedesktop/FileManager1 \
  org.freedesktop.FileManager1 ShowFolders ass 1 "file://$HOME" ""
```

Also test **Reveal/Open Containing Folder** on an existing downloaded file from
your browser. For dialogs, open and save a file in a **portal-aware** application.
Native pickers in applications that do not use the portal will not change.

To inspect the generated configuration and backend:

```sh
# Substitute gnome, kde, or hyprland for other targeted sessions.
cat /etc/xdg/xdg-desktop-portal/niri-portals.conf

gdbus call --session --dest org.freedesktop.impl.portal.desktop.strata \
  --object-path /org/freedesktop/portal/desktop \
  --method org.freedesktop.DBus.Properties.Get \
  org.freedesktop.impl.portal.FileChooser version

journalctl --user -b -u xdg-desktop-portal.service
```

The version call should report `uint32 4`; it tests backend activation, **not**
frontend routing. Verify actual dialogs too, and test screen sharing afterward
to confirm that the desktop's other portal backends remain functional. If Strata
is not selected, check for higher-priority user MIME/portal/D-Bus overrides and
an already-running competing file manager before changing system settings.

#### Portal registration without the module

`packages.<system>.strata-portal` is a small, optional registration package that
reuses the existing Strata binary. Installing the ordinary `strata` package does
not expose an eligible portal backend or active FileManager1 service. Advanced
users can add `strata-portal` to `xdg.portal.extraPortals` and manage the complete
portal preferences themselves; registering a backend alone does not select it.

### Optional overlay

`overlays.default` exposes `pkgs.strata` for consumers who prefer an overlay:

```nix
({ lib, pkgs, ... }: {
  nixpkgs.overlays = [ strata.overlays.default ];
  nixpkgs.config.allowUnfreePredicate = pkg: lib.getName pkg == "strata";
  environment.systemPackages = [ pkgs.strata ];
})
```

The overlay uses **your** nixpkgs and unfree policy, unlike the package output.
It needs Rust 1.98.1-compatible dependencies and GTK 4.12 or later; using the
package output is safer on older NixOS releases. Merge the predicate with any
existing unfree policy rather than replacing it blindly.

For Home Manager, use
`home.packages = [ strata.packages.${pkgs.stdenv.hostPlatform.system}.strata ];`
in a module with access to the `strata` input.

## Desktop and runtime integration

- GTK4 wrapping supplies the GUI resource paths and GStreamer plugins.
- FFmpeg, ffmpegthumbnailer, ImageMagick, LibRaw, SquashFS tools, Fontconfig,
  `prlimit`, and bubblewrap are supplied for previews. The obsolete, insecure
  standalone `dcraw` fallback is intentionally not included; LibRaw is included.
- Preview helpers use upstream's isolation, with `/nix/store` mounted read-only
  and fixed store paths compiled into Strata. This exposes the **whole store**,
  not just Strata's closure; as usual, never put secrets in the Nix store.
- Trusted host-tool lookup retains upstream's system-wrapper/system-profile
  precedence and appends packaged store directories as fallbacks. It does not
  trust an arbitrary inherited `PATH`.
- Preview sandboxing requires working user namespaces or an appropriate
  system-managed bubblewrap wrapper. If previews fail, diagnose the namespace
  policy; do not disable isolation to work around it.
- Optional activation services generated by Strata use the public GTK wrapper,
  while sandbox helpers keep using the unwrapped ELF.
- The package-managed marker tells Strata to update through Nix rather than
  replace its executable. It does not disable upstream's release checks.

Installing the ordinary package does **not** make Strata your default file
manager or portal backend. Use the opt-in NixOS module above for those features.
The FileManager1 service template remains inactive under `share/strata`; portal
assets live in the separate `strata-portal` package.

**Upstream GUI installer limitation:** its per-user FileManager1/portal installer
rejects executable paths with group-writable ancestors. This system's root-owned,
sticky `/nix/store` is group-writable, so it reports “The Strata executable path
must not be writable by other users”. The declarative module registers immutable
store executables without invoking that installer or weakening its security
checks. Do not alter store permissions to make the GUI installer work.

For a folder MIME default only, without the module, this standard NixOS option
still works alongside an installed Strata package:

```nix
xdg.mime.defaultApplications."inode/directory" = "io.github.lgse.Strata.desktop";
```

It does not configure FileManager1 or the file-chooser portal.

## Validation

```sh
nix flake check                 # Package, portal/module checks, private D-Bus precedence
nix flake check --no-build --all-systems  # Evaluate both architecture outputs
./scripts/smoke-test.sh          # Real bubblewrap image/PDF/audio/RAR helpers
```

The smoke test runs outside Nix's build sandbox because nested user namespaces
may be disallowed there. It creates fixtures in a temporary directory and
removes them afterward; it does not install Strata or change desktop settings.
The full upstream GUI test suite is not run by this flake.

Integration checks evaluate opt-in behavior and automatic/explicit targets,
exercise generated configurations with explicit and packaged bases, package
priorities, fallbacks, and conflicting declarations, and test activation-directory
precedence on a private `dbus-daemon` bus with mock providers. They do not start
Strata on your real session bus or validate interactive dialogs. Both D-Bus
implementations and real desktop routing still need desktop testing.

Verified for **v1.0.0** on this x86_64 NixOS workstation:

- Full release source build and both `nix flake check` package checks passed.
- `nix run .#strata -- --version` returned `strata 1.0.0`.
- Sandbox smoke tests passed for image/PDF thumbnails, audio waveform generation,
  and streaming RAR extraction with the expected filename and content.
- Both architecture outputs evaluated successfully; **aarch64 was not built**.
- The new native integration checks passed, and generated configurations from
  actual GNOME, KDE, Hyprland, and Niri packages retained their other preferences.
- Interactive folder/Reveal/portal routing with the new NixOS module is awaiting
  desktop testing; GUI startup was not retested for v1.0.0.

Previous v0.21.0 validation on this x86_64 NixOS workstation:

- Full release source build and both `nix flake check` package checks passed.
- `nix run .#strata -- --version` returned `strata 0.21.0`.
- The sandbox smoke tests passed for image/PDF thumbnails, audio waveform
  generation, and streaming extraction of a real RAR fixture (including its
  expected filename and content).
- An isolated Xvfb/D-Bus session presented a 1200×760 Strata window and completed
  directory loading. This is a startup smoke test, not full interactive QA.
- Both architecture outputs evaluated successfully; **aarch64 was not built**.
- The optional portal installer was tested with a temporary HOME and refused
  the group-writable store ancestor, as described above.

Outputs are available for `x86_64-linux` and `aarch64-linux`; this workstation
is x86_64. Evaluation of an architecture is not a substitute for building it.

## Updating

Strata's version, commit, source hash, and Cargo hash are deliberately pinned in
`package.nix`. To upgrade Strata, update those values together and rebuild/test.
`nix flake update nixpkgs` updates the dependency lock, **not** Strata's source
version. After modifying the package, reinstall/update your user profile entry
or update the system flake's `strata` input lock and rebuild NixOS, as appropriate.
