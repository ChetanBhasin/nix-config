ObjC.import("AppKit");

function run(args) {
  var image = $.NSURL.fileURLWithPath(args[0]);
  var screens = $.NSScreen.screens;
  for (var i = 0; i < screens.count; i++) {
    if (!$.NSWorkspace.sharedWorkspace.setDesktopImageURLForScreenOptionsError(
      image, screens.objectAtIndex(i), $.NSDictionary.dictionary, null
    )) throw new Error("Could not set desktop wallpaper");
  }
}
