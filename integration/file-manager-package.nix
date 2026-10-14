{ runCommand, strata }:

# Deliberately not installed into the system profile: other file managers may
# register this shared name there. The module gives this separate directory
# precedence through the session's XDG_DATA_DIRS and D-Bus package ordering.
runCommand "strata-file-manager-${strata.version}" { } ''
  install -Dm644 ${strata}/share/strata/io.github.lgse.Strata.FileManager1.service \
    "$out/share/dbus-1/services/org.freedesktop.FileManager1.service"
''
