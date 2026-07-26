# Arabic (and Hebrew) in the terminal

Arabic looks "flipped" in Ghostty because Ghostty has no bidi engine, not because of a
locale, font, or `LANG` mistake. Terminals store one character per cell in *logical* order
(the order the bytes arrive). Rendering it correctly needs the Unicode Bidirectional
Algorithm (UAX #9) to reorder each line into *visual* order, plus Arabic joining so letters
connect. Ghostty does the joining, not the reordering, so a line reads right-to-left
backwards. Verify on any box:

```sh
otool -L /Applications/Ghostty.app/Contents/MacOS/ghostty | grep -iE 'fribidi|icu'   # no hits
ghostty +show-config --default | grep -i bidi                                        # no key
```

No hits, no key, no fix in config. Same story in kitty and Alacritty. Full bidi terminals:
Konsole and GNOME Terminal (Linux), `mlterm` anywhere, and WezTerm behind a flag.

## What is set up here

`[tools.fribidi]` installs the FriBidi CLI and defines a `bidi` filter in bash, zsh, and
fish. It converts logical order to visual order and shapes Arabic, so any terminal renders
the result correctly by drawing it left to right, unchanged:

```sh
bidi notes-ar.txt                       # read a file
curl -s "$url" | bidi                   # read a pipe
git --no-pager log --no-color | bidi    # plain text only, see the ANSI warning
bidi --ltr mixed.txt                    # force the paragraph base direction
```

Three limits worth knowing before reaching for it:

- **Plain text only.** ANSI escape sequences are just characters to FriBidi, and it happily
  reorders them into visual garbage. Strip color at the source (`--no-color`, `--color=never`)
  rather than after the fact.
- **Display only.** The output uses Arabic presentation forms (U+FE70..U+FEFF), not the
  normal letters. It is unsuitable for writing back to a file, searching, or diffing.
- **Output only.** Nothing here fixes *typing* Arabic at a prompt or editing it in Vim,
  because the shell's line editor and the cursor still work in logical order. For writing
  Arabic, use a real editor (VS Code, TextEdit) or a bidi terminal.

## If reading is not enough

Install WezTerm alongside Ghostty and keep it for RTL work. It implements bidi natively
(`bidi_enabled: bool` and `bidi_direction: ParagraphDirectionHint` in `config/src/config.rs`,
Arabic shaping applied per paragraph before line splitting):

```sh
brew install --cask wezterm
```

```lua
-- ~/.config/wezterm/wezterm.lua
local wezterm = require("wezterm")
return {
  bidi_enabled = true,
  bidi_direction = "AutoLeftToRight",   -- or LeftToRight / RightToLeft / AutoRightToLeft
}
```

Cursor movement and selection in RTL runs are still rough there, upstream calls the feature
experimental, and the paragraph-direction hint is per-window rather than per-line. It is
correct enough to read and roughly edit Arabic, which the filter above cannot do.

`mlterm` (`brew install mlterm`) is the other option: older interface, but the most complete
bidi and Arabic shaping of any terminal, including a proper RTL cursor.

## Fonts

macOS already ships Arabic coverage (`GeezaPro.ttc`, `SFArabic.ttf`), so Ghostty's fallback
finds glyphs without any config. What it cannot give is a *monospace* Arabic, so Arabic
columns will not line up with Latin ones. If aligned columns matter, install a dual-width
Arabic mono and list it as a fallback:

```
# ~/.config/ghostty/config
font-family = <your Latin mono>
font-family = Kawkab Mono
```

## Status of the real fix

Ghostty tracks bidi in [discussion #9774](https://github.com/ghostty-org/ghostty/discussions/9774)
(a FriBidi-based implementation with HarfBuzz joining, in progress) and
[issue #12183](https://github.com/ghostty-org/ghostty/issues/12183) for macOS layout
direction. When it lands, `bidi` becomes redundant for reading and `[tools.fribidi]` can be
flipped to `enabled = false`, which removes the shell block and keeps the binary.
