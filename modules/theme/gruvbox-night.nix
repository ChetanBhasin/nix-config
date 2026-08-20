# A lower-saturation night variant of Base16 Gruvbox Dark Hard.
# The hard background comes from Jon Gjengset's Base16 setup; the foreground
# ladder and accents are deliberately softened for long sessions in low light.
rec {
  name = "gruvbox-night";

  base00 = "#1d2021";
  base01 = "#282828";
  base02 = "#3c3836";
  base03 = "#948676";
  base04 = "#a89984";
  base05 = "#bdae93";
  base06 = "#d5c4a1";
  base07 = "#ebdbb2";

  # Softer accents: each stays readable on base00 while avoiding Gruvbox's
  # high-saturation bright variants.
  base08 = "#d66b64";
  base09 = "#d58a54";
  base0A = "#c9a257";
  base0B = "#a3ad62";
  base0C = "#7fa98a";
  base0D = "#749fa0";
  base0E = "#b77f91";
  base0F = "#b47b57";

  inactiveBorder = "#504945";
  activeBorder = base0A;

  alacritty = {
    indexed_colors = [
      {
        index = 16;
        color = base09;
      }
      {
        index = 17;
        color = base0F;
      }
      {
        index = 18;
        color = base01;
      }
      {
        index = 19;
        color = base02;
      }
      {
        index = 20;
        color = base04;
      }
      {
        index = 21;
        color = base06;
      }
    ];

    bright = {
      black = base03;
      blue = base0D;
      cyan = base0C;
      green = base0B;
      magenta = base0E;
      red = base08;
      white = base06;
      yellow = base0A;
    };

    cursor = {
      cursor = base05;
      text = base00;
    };

    normal = {
      black = base00;
      blue = base0D;
      cyan = base0C;
      green = base0B;
      magenta = base0E;
      red = base08;
      white = base05;
      yellow = base0A;
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

  fzf = [
    "--color=dark"
    "--color=fg:${base05},bg:-1,hl:${base0E},fg+:${base07},bg+:${base02},hl+:${base09}"
    "--color=info:${base0B},prompt:${base0D},pointer:${base08},marker:${base0A},spinner:${base0D},header:${base0D},border:${base03}"
  ];

  # Bat uses TextMate themes rather than Base16 tables, so keep its syntax
  # mapping here alongside the canonical palette instead of falling back to
  # Bat's brighter stock Gruvbox theme.
  bat = ''
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>name</key>
      <string>${name}</string>
      <key>settings</key>
      <array>
        <dict>
          <key>settings</key>
          <dict>
            <key>background</key><string>${base00}</string>
            <key>caret</key><string>${base05}</string>
            <key>foreground</key><string>${base05}</string>
            <key>invisibles</key><string>${base03}</string>
            <key>lineHighlight</key><string>${base01}</string>
            <key>selection</key><string>${base02}</string>
          </dict>
        </dict>
        <dict>
          <key>name</key><string>Comments</string>
          <key>scope</key><string>comment, punctuation.definition.comment</string>
          <key>settings</key>
          <dict>
            <key>fontStyle</key><string>italic</string>
            <key>foreground</key><string>${base03}</string>
          </dict>
        </dict>
        <dict>
          <key>name</key><string>Punctuation</string>
          <key>scope</key><string>punctuation, meta.brace, meta.delimiter</string>
          <key>settings</key><dict><key>foreground</key><string>${base04}</string></dict>
        </dict>
        <dict>
          <key>name</key><string>Variables</string>
          <key>scope</key><string>variable, variable.parameter, meta.definition.variable, entity.name.tag</string>
          <key>settings</key><dict><key>foreground</key><string>${base08}</string></dict>
        </dict>
        <dict>
          <key>name</key><string>Constants</string>
          <key>scope</key><string>constant, support.constant, constant.language, constant.numeric</string>
          <key>settings</key><dict><key>foreground</key><string>${base09}</string></dict>
        </dict>
        <dict>
          <key>name</key><string>Strings</string>
          <key>scope</key><string>string, punctuation.definition.string</string>
          <key>settings</key><dict><key>foreground</key><string>${base0B}</string></dict>
        </dict>
        <dict>
          <key>name</key><string>Keywords</string>
          <key>scope</key><string>keyword, storage, storage.type, storage.modifier</string>
          <key>settings</key><dict><key>foreground</key><string>${base0E}</string></dict>
        </dict>
        <dict>
          <key>name</key><string>Functions</string>
          <key>scope</key><string>entity.name.function, support.function, meta.function-call, variable.function</string>
          <key>settings</key><dict><key>foreground</key><string>${base0D}</string></dict>
        </dict>
        <dict>
          <key>name</key><string>Types</string>
          <key>scope</key><string>entity.name.type, entity.name.class, support.type, support.class</string>
          <key>settings</key><dict><key>foreground</key><string>${base0A}</string></dict>
        </dict>
        <dict>
          <key>name</key><string>Regular expressions and escapes</string>
          <key>scope</key><string>string.regexp, constant.character.escape, support.other</string>
          <key>settings</key><dict><key>foreground</key><string>${base0C}</string></dict>
        </dict>
        <dict>
          <key>name</key><string>Deprecated and embedded</string>
          <key>scope</key><string>invalid.deprecated, meta.embedded, entity.other.inherited-class</string>
          <key>settings</key><dict><key>foreground</key><string>${base0F}</string></dict>
        </dict>
        <dict>
          <key>name</key><string>Invalid</string>
          <key>scope</key><string>invalid.illegal</string>
          <key>settings</key>
          <dict>
            <key>background</key><string>${base08}</string>
            <key>foreground</key><string>${base00}</string>
          </dict>
        </dict>
        <dict>
          <key>name</key><string>Diff inserted</string>
          <key>scope</key><string>markup.inserted, meta.diff.header.to-file</string>
          <key>settings</key><dict><key>foreground</key><string>${base0B}</string></dict>
        </dict>
        <dict>
          <key>name</key><string>Diff changed</string>
          <key>scope</key><string>markup.changed, meta.diff.header.from-file</string>
          <key>settings</key><dict><key>foreground</key><string>${base0E}</string></dict>
        </dict>
        <dict>
          <key>name</key><string>Diff deleted</string>
          <key>scope</key><string>markup.deleted</string>
          <key>settings</key><dict><key>foreground</key><string>${base08}</string></dict>
        </dict>
      </array>
    </dict>
    </plist>
  '';
}
