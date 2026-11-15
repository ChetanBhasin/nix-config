ObjC.import("AppKit");

function run(args) {
  var image = $.NSURL.fileURLWithPath(args[0]);
  var workspace = $.NSWorkspace.sharedWorkspace;
  var screens = $.NSScreen.screens;
  for (var i = 0; i < screens.count; i++) {
    var screen = screens.objectAtIndex(i);
    var current = workspace.desktopImageURLForScreen(screen);
    if (current && current.isEqual(image)) continue;
    if (!workspace.setDesktopImageURLForScreenOptionsError(
      image, screen, $.NSDictionary.dictionary, null
    )) throw new Error("Could not set desktop wallpaper");
  }
}
