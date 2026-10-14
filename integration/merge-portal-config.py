"""Select a declarative portal configuration and change only FileChooser.

Run during a Nix build, never against the live /etc or home directory. Explicit
NixOS configurations precede package configurations; a complete config file is
selected, not layered with unrelated lower-priority files.
"""

import configparser
import json
import pathlib
import sys

FILE_CHOOSER = "org.freedesktop.impl.portal.FileChooser"


def merge(spec):
    parser = configparser.ConfigParser(interpolation=None, strict=False)
    parser.optionxform = str
    explicit = spec["explicit"]
    if explicit:
        parser.read_dict({"preferred": explicit})
    else:
        # Config packages share one XDG directory after installation. Desktop
        # names precede the generic file, regardless of package list order.
        filenames = ([f'{spec["desktop"]}-portals.conf'] if spec["desktop"] != "common" else []) + ["portals.conf"]
        candidates = [
            pathlib.Path(package) / "share/xdg-desktop-portal" / filename
            for filename in filenames
            for package in spec["packages"]
        ]
        source = next((path for path in candidates if path.is_file()), None)
        if source is None:
            raise ValueError(
                f'No declarative portal configuration found for {spec["desktop"]!r}. '
                'Provide xdg.portal.config.<desktop> (including default and other '
                'interface preferences), xdg.portal.config.common, or a '
                'configuration package in xdg.portal.configPackages.'
            )
        with source.open() as stream:
            parser.read_file(stream)
    if not parser.has_section("preferred"):
        raise ValueError("Portal configuration has no [preferred] section")
    parser.set("preferred", FILE_CHOOSER, ";".join(["strata", *spec["fallbacks"]]))
    return parser


def main():
    spec = json.loads(pathlib.Path(sys.argv[1]).read_text())
    parser = merge(spec)
    with pathlib.Path(sys.argv[2]).open("w") as stream:
        parser.write(stream, space_around_delimiters=False)


if __name__ == "__main__":
    main()
