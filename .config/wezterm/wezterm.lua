-- Pull in the wezterm API
local wezterm = require 'wezterm'

-- This will hold the configuration.
local config = wezterm.config_builder()

-- This is where you actually apply your config choices

config.default_prog = {"wsl.exe"}

config.color_scheme = 'Tokyo Night Moon'
config.font = wezterm.font 'MesloLGS Nerd Font Mono'
config.font_size = 13

config.enable_tab_bar = false

config.window_decorations = 'RESIZE'
config.window_background_opacity = 0.90
-- config.macos_window_background_blur = 10

if wezterm.target_triple:find("windows") == nil then
config.keys = {
  {key="g", mods="CTRL", action=wezterm.action{SpawnCommandInNewTab={args={"gitui"}}}},
}
end

-- and finally, return the configuration to wezterm
return config

