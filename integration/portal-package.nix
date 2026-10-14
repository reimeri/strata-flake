{ lib, runCommand, strata }:

runCommand "strata-portal-${strata.version}" {
  meta = {
    description = "Opt-in FileChooser portal registration for Strata";
    license = lib.licenses.mit; # Registration text only; the binary retains its own license.
    inherit (strata.meta) platforms;
  };
} ''
  install -Dm644 ${strata.src}/data/portal/strata.portal \
    "$out/share/xdg-desktop-portal/portals/strata.portal"
  install -Dm644 ${strata.src}/data/portal/org.freedesktop.impl.portal.desktop.strata.service.in \
    "$out/share/dbus-1/services/org.freedesktop.impl.portal.desktop.strata.service"
  substituteInPlace "$out/share/dbus-1/services/org.freedesktop.impl.portal.desktop.strata.service" \
    --replace-fail '@STRATA_EXECUTABLE@' '${lib.getExe strata}'
''
