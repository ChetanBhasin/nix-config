{ lib
, bash
, claude-code
, writeTextFile
, defaultProfile ? "default"
}:

# ccode - profile proxy for claude-code.
#
# The script invokes claude by store path, which keeps this package's
# claude-code alive as a content reference of the built output.

let
  script = lib.replaceStrings
    [
      "@DEFAULT_PROFILE@"
      "@CLAUDE_BIN@"
    ]
    [
      defaultProfile
      "${claude-code}/bin/claude"
    ]
    (builtins.readFile ./ccode.sh);
in
writeTextFile {
  name = "ccode-0.1.0";
  destination = "/bin/ccode";
  executable = true;
  text = ''
    #!${bash}/bin/bash

    ${script}
  '';
  checkPhase = ''
    ${bash}/bin/bash -n "$target"
  '';
  meta = with lib; {
    description = "Profile proxy for claude-code: per-profile CLAUDE_CONFIG_DIR under ~/.ccode/profiles";
    license = licenses.mit;
    mainProgram = "ccode";
    platforms = platforms.all;
  };
}
