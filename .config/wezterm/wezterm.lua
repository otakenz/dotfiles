-- Pull in the wezterm API
local wezterm = require("wezterm")

-- --------------
-- Wezterm module
-- --------------
-- Return {} if no WSL
local wsl_domains = wezterm.default_wsl_domains()

-- ---------------------
-- Wezterm configuration
-- ---------------------
local config = wezterm.config_builder()

-- Set the first distro found by 'wsl -l -v' to Wezterm's default_domain
if wsl_domains and #wsl_domains > 0 then
	config.default_domain = wsl_domains[1].name
end

if wezterm.hostname() == "msipc" then
	config.default_domain = "WSL:archlinux"
end

config.initial_rows = 50
config.initial_cols = 180

config.color_scheme = "Tokyo Night Moon"

config.font = wezterm.font_with_fallback({ "MesloLGS Nerd Font Mono", "Symbols Nerd Font Mono" })
config.font_size = 13

config.window_decorations = "TITLE|RESIZE"
config.hide_tab_bar_if_only_one_tab = true
config.window_background_opacity = 0.8

config.keys = {
	-- {key="g", mods="CTRL", action=wezterm.action.SendString("gitui\n")},
}

-- and finally, return the configuration to wezterm
return config
