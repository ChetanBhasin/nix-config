local hyper = { 'option', 'command' }
local winMgmt = { 'ctrl', 'option' }

-- Terminal apps where Ctrl+Space should send CSI u sequence for tmux
local terminalApps = {
  ["Alacritty"] = true,
  ["Terminal"] = true,
  ["iTerm2"] = true,
  ["kitty"] = true,
  ["WezTerm"] = true,
}

-- Ctrl+Space handler for terminal apps
-- Sends CSI u sequence (ESC [ 32 ; 5 u) instead of NUL so tmux sees C-Space
hs.hotkey.bind({ "ctrl" }, "space", function()
  local app = hs.application.frontmostApplication()
  if app and terminalApps[app:name()] then
    -- Send the CSI u escape sequence for Ctrl+Space: ESC [ 32 ; 5 u
    -- This is what tmux expects when extended-keys is enabled
    hs.eventtap.keyStrokes("\x1b[32;5u")
  else
    -- For non-terminal apps, send the original Ctrl+Space (as NUL)
    hs.eventtap.keyStroke({ "ctrl" }, "space", 0, app)
  end
end)

-- Window Management
hs.hotkey.bind(winMgmt, "return", function()
  local win = hs.window.focusedWindow()
  if win then win:maximize() end
end)

hs.hotkey.bind(winMgmt, "left", function()
  local win = hs.window.focusedWindow()
  if win then
    local screen = win:screen():frame()
    win:setFrame({ x = screen.x, y = screen.y, w = screen.w / 2, h = screen.h })
  end
end)

hs.hotkey.bind(winMgmt, "right", function()
  local win = hs.window.focusedWindow()
  if win then
    local screen = win:screen():frame()
    win:setFrame({ x = screen.x + screen.w / 2, y = screen.y, w = screen.w / 2, h = screen.h })
  end
end)

hs.hotkey.bind(winMgmt, "up", function()
  local win = hs.window.focusedWindow()
  if win then
    local screen = win:screen():frame()
    win:setFrame({ x = screen.x, y = screen.y, w = screen.w, h = screen.h / 2 })
  end
end)

hs.hotkey.bind(winMgmt, "down", function()
  local win = hs.window.focusedWindow()
  if win then
    local screen = win:screen():frame()
    win:setFrame({ x = screen.x, y = screen.y + screen.h / 2, w = screen.w, h = screen.h / 2 })
  end
end)

hs.hotkey.bind(winMgmt, "c", function()
  local win = hs.window.focusedWindow()
  if win then win:centerOnScreen() end
end)

-- App Launchers
hs.hotkey.bind(hyper, "b", function() hs.application.launchOrFocus("Zen") end)
hs.hotkey.bind(hyper, "t", function() hs.application.launchOrFocus("Alacritty") end)
hs.hotkey.bind(hyper, "f", function() hs.application.launchOrFocus("Figma") end)
hs.hotkey.bind(hyper, "e", function() hs.application.launchOrFocus("Signal") end)
hs.hotkey.bind(hyper, "s", function() hs.application.launchOrFocus("Spotify") end)
hs.hotkey.bind(hyper, "m", function() hs.application.launchOrFocus("Mail") end)
hs.hotkey.bind(hyper, "o", function() hs.application.launchOrFocus("Messages") end)
hs.hotkey.bind(hyper, "w", function() hs.application.launchOrFocus("WhatsApp") end)
hs.hotkey.bind(hyper, "g", function() hs.application.launchOrFocus("Discord") end)
hs.hotkey.bind(hyper, "c", function() hs.application.launchOrFocus("Visual Studio Code") end)
hs.hotkey.bind(hyper, "x", function() hs.application.launchOrFocus("Xcode") end)
hs.hotkey.bind(hyper, "l", function() hs.application.launchOrFocus("Slack") end)
hs.hotkey.bind(hyper, "z", function() hs.application.launchOrFocus("zoom.us") end)
hs.hotkey.bind(hyper, "n", function() hs.application.launchOrFocus("Obsidian") end)
hs.hotkey.bind(hyper, "h", function() hs.application.launchOrFocus("IBKR Desktop") end)
hs.hotkey.bind(hyper, "v", function() hs.application.launchOrFocus("ProtonVPN") end)
