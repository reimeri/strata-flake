{ packageForSystem }:
{ config, lib, options, pkgs, ... }:

let
  cfg = config.programs.strata;
  inherit (lib) mkEnableOption mkIf mkOption types;
  enabled = path: lib.attrByPath path false config;
  detectedDesktops =
    lib.optional (enabled [ "services" "desktopManager" "gnome" "enable" ]) "gnome"
    ++ lib.optional (enabled [ "services" "desktopManager" "plasma6" "enable" ]) "kde"
    ++ lib.optional (enabled [ "programs" "hyprland" "enable" ]) "hyprland"
    ++ lib.optional (enabled [ "programs" "niri" "enable" ]) "niri";
  portalPackage = pkgs.callPackage ../integration/portal-package.nix { strata = cfg.package; };
  fileManagerPackage = pkgs.callPackage ../integration/file-manager-package.nix { strata = cfg.package; };
  portalConfigName = desktop:
    "xdg/xdg-desktop-portal/${if desktop == "common" then "portals.conf" else "${desktop}-portals.conf"}";
  # Reproduce system-profile priority/output selection for configPackages.
  configTree = pkgs.buildEnv {
    name = "strata-base-portal-configs";
    paths = config.xdg.portal.configPackages;
    pathsToLink = [ "/share/xdg-desktop-portal" ];
    inherit (config.environment) extraOutputsToInstall;
    ignoreCollisions = true;
  };
  # Do not silently replace custom environment.etc declarations. Standard
  # xdg.portal output is regenerated from its final options; other declarations
  # must be expressed through xdg.portal.config/configPackages instead.
  # Inspect presence only, respecting nested module properties without forcing
  # inactive branches or reading any generated file contents.
  activeDefinition = value:
    let kind = if builtins.isAttrs value then value._type or "" else "";
    in
    if kind == "if" then value.condition && activeDefinition value.content
    else if kind == "merge" then lib.any activeDefinition value.contents
    else if kind == "override" || kind == "order" then activeDefinition value.content
    else if builtins.isAttrs value && !(lib.isDerivation value) then
      lib.any activeDefinition (lib.attrValues value)
    else value != null;
  customEtcTargets = lib.filter (desktop:
    lib.any (definition:
      builtins.hasAttr (portalConfigName desktop) definition.value
      && !(lib.hasSuffix "/nixos/modules/config/xdg/portal.nix" definition.file)
      && definition.file != toString ./nixos.nix
      && activeDefinition definition.value.${portalConfigName desktop}
    ) options.environment.etc.definitionsWithLocations
  ) (lib.unique (cfg.fileChooser.desktops ++ [ "common" ]));
  portalConfig = desktop:
    let
      # An explicit /etc config is a complete replacement for packaged configs.
      # A generic /etc config likewise precedes any package-provided config.
      desktopConfig = config.xdg.portal.config.${desktop} or { };
      commonConfig = config.xdg.portal.config.common or { };
      spec = pkgs.writeText "strata-${desktop}-portal-spec.json" (builtins.toJSON {
        inherit desktop;
        explicit = if desktopConfig != { } then desktopConfig else commonConfig;
        packages = [ (toString configTree) ];
        fallbacks = cfg.fileChooser.fallbacks;
      });
    in
    pkgs.runCommand "strata-${desktop}-portals.conf" { nativeBuildInputs = [ pkgs.python3 ]; } ''
      python ${../integration/merge-portal-config.py} ${spec} "$out"
    '';
in
{
  _file = toString ./nixos.nix;

  options.programs.strata = {
    enable = mkEnableOption "Strata file manager";
    package = mkOption {
      type = types.package;
      default = packageForSystem pkgs.stdenv.hostPlatform.system;
      defaultText = lib.literalExpression "strata.packages.\${pkgs.stdenv.hostPlatform.system}.strata";
      description = "Strata package to install and use for desktop activation.";
    };
    defaultFileManager = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Make Strata the system folder MIME default and preferred session D-Bus
        FileManager1 provider. Per-user preferences can override these defaults;
        an already-running provider must exit before Strata can own the bus name.
      '';
    };
    fileChooser = {
      enable = mkEnableOption "Strata's FileChooser portal for the selected desktops";
      desktops = mkOption {
        type = types.listOf (types.strMatching "[a-z0-9][a-z0-9_-]*");
        default = detectedDesktops;
        defaultText = lib.literalExpression ''enabled GNOME, Plasma 6, Hyprland and Niri desktops'';
        example = [ "niri" ];
        description = ''
          Portal configuration targets. By default, all enabled supported
          desktops are selected (GNOME: gnome; Plasma 6: kde; Hyprland: hyprland;
          Niri: niri). An explicit list replaces detection. Other desktops require
          an explicit target and a declarative base portal configuration.
          Use common to target the generic portals.conf instead.
        '';
      };
      fallbacks = mkOption {
        type = types.listOf (types.strMatching "[a-z0-9][a-z0-9_-]*");
        default = [ ];
        example = [ "gtk" ];
        description = ''
          Installed FileChooser backends to prefer after Strata. No fallback is
          selected implicitly. This is backend-selection fallback, not live
          failover if Strata crashes during a request.
        '';
      };
    };
  };

  config = mkIf cfg.enable (lib.mkMerge [
    {
      environment.systemPackages = [ cfg.package ];
    }
    (mkIf cfg.defaultFileManager {
      xdg.mime.enable = true;
      xdg.mime.defaultApplications."inode/directory" = "io.github.lgse.Strata.desktop";
      services.dbus.packages = lib.mkBefore [ fileManagerPackage ];
      environment.sessionVariables.XDG_DATA_DIRS = lib.mkBefore [ "${fileManagerPackage}/share" ];
    })
    (mkIf cfg.fileChooser.enable {
      assertions = [
        {
          assertion = customEtcTargets == [ ];
          message = "Strata FileChooser: custom environment.etc portal declarations for ${lib.concatStringsSep ", " customEtcTargets} cannot be overwritten safely. Move their preferences to xdg.portal.config or xdg.portal.configPackages.";
        }
        {
          assertion = cfg.fileChooser.desktops != [ ];
          message = "Strata FileChooser: no supported desktop detected. Set programs.strata.fileChooser.desktops explicitly.";
        }
        {
          assertion = lib.length (lib.unique cfg.fileChooser.desktops) == lib.length cfg.fileChooser.desktops;
          message = "Strata FileChooser: desktops must not contain duplicates.";
        }
        {
          assertion = !(lib.elem "strata" cfg.fileChooser.fallbacks);
          message = "Strata FileChooser: fallbacks must not include strata (it is already first).";
        }
      ];
      xdg.portal.enable = true;
      xdg.portal.extraPortals = [ portalPackage ];
      environment.etc = lib.listToAttrs (map (desktop: {
        name = portalConfigName desktop;
        value = {
          # The standard portal module may also generate this file. Consume its
          # final declarative settings above, then replace only the output file.
          text = lib.mkForce null;
          source = lib.mkForce (portalConfig desktop);
        };
      }) cfg.fileChooser.desktops);
    })
  ]);
}
