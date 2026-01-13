{ config, pkgs, ... }: {

  darwin-config-manager = {
    enableSudoTouch = true;
    enableExtras = true;
    enableProf = false;
    theme = "nord";
  };

  # Force U.S. keyboard layout so ~ is produced directly instead of as a dead key
  system.defaults.CustomUserPreferences."com.apple.HIToolbox" = {
    AppleCurrentKeyboardLayoutInputSourceID = "com.apple.keylayout.US";
    AppleEnabledInputSources = [{
      "InputSourceKind" = "Keyboard Layout";
      "KeyboardLayout ID" = 0;
      "KeyboardLayout Name" = "U.S.";
    }];
    AppleSelectedInputSources = [{
      "InputSourceKind" = "Keyboard Layout";
      "KeyboardLayout ID" = 0;
      "KeyboardLayout Name" = "U.S.";
    }];
  };

  imports = [ ../../darwin ];
}
