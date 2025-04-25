-- Pull in the wezterm API
local wezterm = require("wezterm")

-- This will hold the configuration.
local config = wezterm.config_builder()

-- This is where you actually apply your config choices

if wezterm.target_triple == "x86_64-pc-windows-msvc" then
	config.default_prog = { "wsl.exe" }
else
	config.default_prog = { "zsh", "-l" }
end

config.color_scheme = "Tokyo Night Moon"
config.font = wezterm.font("MesloLGS Nerd Font Mono")
config.font_size = 14

--config.enable_tab_bar = false

config.window_decorations = "RESIZE"
config.hide_tab_bar_if_only_one_tab = true
config.window_background_opacity = 0.8

config.keys = {
	-- {key="g", mods="CTRL", action=wezterm.action.SendString("gitui\n")},
}

-- and finally, return the configuration to wezterm
return config
