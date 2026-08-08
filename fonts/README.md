# Bundled fonts

Two variable faces, declared under `fonts:` in the engine `pubspec.yaml` and
wired to Material 3 text roles in `lib/core/theme/app_theme.dart`.

| File | Family | Axes | Roles |
| --- | --- | --- | --- |
| `Inter-Variable.ttf` | Inter | `opsz` 14–32, `wght` 100–900 | title, body, label, and every widget that builds its own style |
| `SpaceGrotesk-Variable.ttf` | Space Grotesk | `wght` 300–700 | display, headline |

Both are SIL Open Font License 1.1. `OFL-Inter.txt` and `OFL-SpaceGrotesk.txt`
ship beside them because the licence requires the notice to travel with the
font, including inside an application binary.

## Updating

Download the family from Google Fonts ([Inter], [Space Grotesk]) and take the
`*-VariableFont_*.ttf` from the top level of the archive rather than anything
under `static/`, rename it as above, and copy `OFL.txt` alongside.

There is no script for this. `fonts.google.com/download?family=…` answers with
the site's HTML rather than an archive, so anything automated would be scraping
a page that is free to change. These files move once a year at most.

The italic file is deliberately not bundled: nothing in the shell sets
`FontStyle.italic`, and it would add roughly as much again for no rendering.

## Why variable, and why no `weight:` entries

`FontWeight` drives the `wght` axis directly; that landed in Flutter 3.41, and
this package requires 3.44, so the workaround it replaced is behind us. One
file per family covers every weight, and intermediate weights become available
for free.

Adding `weight:` entries to the `pubspec.yaml` declarations would put Flutter
back into matching a file per weight and defeat the axis, so there are none.

This replaced nine static Inter weights fetched from `fonts.gstatic.com` by
content hash. That approach pinned an Inter with no `opsz` axis, could not be
verified against anything, and cost 2.7 MB; both variable faces together are
under 1 MB.

Nothing sets `opsz`. It rests at its default of 14, Inter's text optical size,
which is the correct one for the roles Inter has here.

[Inter]: https://fonts.google.com/specimen/Inter
[Space Grotesk]: https://fonts.google.com/specimen/Space+Grotesk
