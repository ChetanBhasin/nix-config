# Luna Comfort: a lower-strain local variant of luna.nvim's palette
# (https://github.com/WTFox/luna.nvim).
#
# Luna's near-black background and bright foreground are softened to a neutral
# surface ladder with gentler normal-text contrast. Its semantic accent hues
# remain unchanged. Traditional Base16 slot semantics keep warnings amber,
# functions blue, and errors red across every consumer (Helix, Waybar,
# Starship, Alacritty, and others); Neovim applies the same local palette via
# luna.nvim's supported on_colors hook while retaining upstream integrations.
rec {
  name = "luna";

  # Softer neutral surfaces and foregrounds, dark → light.
  base00 = "#151515"; # background
  base01 = "#232323"; # panels and status bars
  base02 = "#30343a"; # selection
  base03 = "#858585"; # comments and muted text
  base04 = "#a8a8a8"; # dim foreground
  base05 = "#c7c7c7"; # normal foreground
  base06 = "#d8d8dc"; # emphasized foreground
  base07 = "#d8d8dc"; # strongest foreground

  # Accents – Luna's four hues + the diagnostic quartet.
  base08 = "#e08585"; # error / variables / diff removed
  base09 = "#e19067"; # keyword-orange / integers, constants
  base0A = "#d9a35a"; # warning / types / attention (yellow slot)
  base0B = "#9eb38e"; # string / success / diff added
  base0C = "#8c9cb8"; # info / regex, escape, support
  base0D = "#75a1c7"; # func / functions, methods, headings
  base0E = "#c4a8d6"; # type / keywords, storage (purple slot)
  base0F = "#b09080"; # hint / deprecated, rare

  # Named extras that aren't part of the 16-slot ladder but that Luna
  # actively uses. Exposed here so consumers don't have to hardcode hex.
  signal = "#c2916a"; # warm signal (search, git-change, dashboard keys)
  dimNeutral = "#686868"; # low-priority UI text and invisibles
  hint = "#b09080";
  ok = "#6fbe80";
  warning = "#d9a35a";
  error = "#e08585";
  info = "#8c9cb8";

  inactiveBorder = "#454545";
  activeBorder = base0D; # blue = Luna's function accent

  alacritty = {
    # 16-21 are extended slots some TUIs read for extra highlights. Mirroring
    # luna.nvim's extras/alacritty so downstream apps get Luna's own choices.
    indexed_colors = [
      {
        index = 16;
        color = base04;
      }
      {
        index = 17;
        color = signal;
      }
      {
        index = 18;
        color = base01;
      }
      {
        index = 19;
        color = inactiveBorder;
      }
      {
        index = 20;
        color = base03;
      }
      {
        index = 21;
        color = base05;
      }
    ];

    bright = {
      black = base03;
      blue = base0C; # info
      cyan = base0D; # Luna aliases cyan to func-blue
      green = ok;
      magenta = base0E;
      red = base08;
      white = base07;
      yellow = warning;
    };

    cursor = {
      cursor = base05;
      text = base00;
    };

    normal = {
      black = base00;
      blue = base0D;
      cyan = base0D; # Luna aliases cyan to func-blue
      green = ok;
      magenta = base0E;
      red = base08;
      white = base05;
      yellow = signal;
    };

    primary = {
      background = base00;
      foreground = base05;
    };

    selection = {
      background = base02;
      text = base06;
    };
  };

  # fzf keeps Luna's semantic accents on the softer local surfaces.
  fzf = [
    "--color=dark"
    "--color=bg+:${base01},bg:${base00},spinner:${base04},hl:${signal}"
    "--color=fg:${base05},header:${signal},info:${base0C},pointer:${base04}"
    "--color=marker:${base0F},fg+:${base06},prompt:${base0D},hl+:${signal}"
    "--color=border:${inactiveBorder}"
  ];

  # Bat consumes TextMate themes. This starts from Luna's upstream mapping and
  # substitutes the shared softer surfaces and foreground ladder.
  bat = ''
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>name</key>
      <string>${name}</string>
      <key>author</key>
      <string>wtfox</string>
      <key>colorSpaceName</key>
      <string>sRGB</string>
      <key>settings</key>
      <array>
        <dict>
          <key>settings</key>
          <dict>
            <key>background</key><string>${base00}</string>
            <key>foreground</key><string>${base05}</string>
            <key>caret</key><string>${base05}</string>
            <key>lineHighlight</key><string>${base01}</string>
            <key>selection</key><string>${base02}</string>
            <key>invisibles</key><string>${dimNeutral}</string>
            <key>gutterForeground</key><string>${inactiveBorder}</string>
          </dict>
        </dict>
        <dict>
          <key>name</key><string>Comment</string>
          <key>scope</key><string>comment, punctuation.definition.comment</string>
          <key>settings</key><dict><key>foreground</key><string>${base03}</string></dict>
        </dict>
        <dict>
          <key>name</key><string>String</string>
          <key>scope</key><string>string, string.quoted, markup.raw, markup.inline.raw</string>
          <key>settings</key><dict><key>foreground</key><string>${base0B}</string></dict>
        </dict>
        <dict>
          <key>name</key><string>String escape / regexp</string>
          <key>scope</key><string>constant.character.escape, string.regexp</string>
          <key>settings</key><dict><key>foreground</key><string>${base04}</string></dict>
        </dict>
        <dict>
          <key>name</key><string>Keyword / Number / Language constant</string>
          <key>scope</key><string>keyword, keyword.control, storage, storage.type, constant.numeric, constant.language, constant.language.boolean, support.type.builtin, entity.name.tag.import</string>
          <key>settings</key><dict><key>foreground</key><string>${base09}</string></dict>
        </dict>
        <dict>
          <key>name</key><string>Import / include</string>
          <key>scope</key><string>keyword.other.import, keyword.control.import, meta.import, keyword.control.import.python</string>
          <key>settings</key><dict><key>foreground</key><string>${dimNeutral}</string></dict>
        </dict>
        <dict>
          <key>name</key><string>Function</string>
          <key>scope</key><string>entity.name.function, support.function, meta.function-call, variable.function</string>
          <key>settings</key><dict><key>foreground</key><string>${base0D}</string></dict>
        </dict>
        <dict>
          <key>name</key><string>Type / Class / Constant / Tag</string>
          <key>scope</key><string>entity.name.type, entity.name.class, support.class, support.type, entity.other.inherited-class, constant.other, support.constant, entity.name.tag</string>
          <key>settings</key><dict><key>foreground</key><string>${base0E}</string></dict>
        </dict>
        <dict>
          <key>name</key><string>Operator / Punctuation / Brace</string>
          <key>scope</key><string>keyword.operator, punctuation, meta.brace</string>
          <key>settings</key><dict><key>foreground</key><string>${base04}</string></dict>
        </dict>
        <dict>
          <key>name</key><string>Punctuation separator</string>
          <key>scope</key><string>punctuation.separator</string>
          <key>settings</key><dict><key>foreground</key><string>#989898</string></dict>
        </dict>
        <dict>
          <key>name</key><string>Variable / Property</string>
          <key>scope</key><string>variable, variable.other, meta.object-literal.key, support.type.property-name, entity.name.tag.yaml</string>
          <key>settings</key><dict><key>foreground</key><string>${base05}</string></dict>
        </dict>
        <dict>
          <key>name</key><string>Parameter</string>
          <key>scope</key><string>variable.parameter</string>
          <key>settings</key><dict><key>foreground</key><string>${base05}</string></dict>
        </dict>
        <dict>
          <key>name</key><string>Section / Heading</string>
          <key>scope</key><string>entity.name.section, markup.heading</string>
          <key>settings</key>
          <dict>
            <key>foreground</key><string>${base05}</string>
            <key>fontStyle</key><string>bold</string>
          </dict>
        </dict>
        <dict>
          <key>name</key><string>Bold</string>
          <key>scope</key><string>markup.bold</string>
          <key>settings</key>
          <dict>
            <key>foreground</key><string>${base04}</string>
            <key>fontStyle</key><string>bold</string>
          </dict>
        </dict>
        <dict>
          <key>name</key><string>Italic</string>
          <key>scope</key><string>markup.italic</string>
          <key>settings</key><dict><key>fontStyle</key><string>italic</string></dict>
        </dict>
        <dict>
          <key>name</key><string>Link</string>
          <key>scope</key><string>markup.underline.link, markup.link</string>
          <key>settings</key><dict><key>foreground</key><string>${ok}</string></dict>
        </dict>
        <dict>
          <key>name</key><string>List</string>
          <key>scope</key><string>markup.list</string>
          <key>settings</key><dict><key>foreground</key><string>${base04}</string></dict>
        </dict>
        <dict>
          <key>name</key><string>Diff inserted</string>
          <key>scope</key><string>markup.inserted, meta.diff.header.to-file</string>
          <key>settings</key><dict><key>foreground</key><string>${ok}</string></dict>
        </dict>
        <dict>
          <key>name</key><string>Diff deleted</string>
          <key>scope</key><string>markup.deleted</string>
          <key>settings</key><dict><key>foreground</key><string>${base08}</string></dict>
        </dict>
        <dict>
          <key>name</key><string>Diff changed</string>
          <key>scope</key><string>markup.changed, meta.diff.header.from-file</string>
          <key>settings</key><dict><key>foreground</key><string>${signal}</string></dict>
        </dict>
        <dict>
          <key>name</key><string>Invalid</string>
          <key>scope</key><string>invalid, invalid.illegal</string>
          <key>settings</key>
          <dict>
            <key>foreground</key><string>${base00}</string>
            <key>background</key><string>${base08}</string>
          </dict>
        </dict>
      </array>
    </dict>
    </plist>
  '';
}
