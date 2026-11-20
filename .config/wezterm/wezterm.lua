-- Pull in the wezterm API
local wezterm = require("wezterm")

local is_windows = wezterm.target_triple:find("windows") ~= nil

-- ---------------------
-- Wezterm configuration
-- ---------------------
local config = wezterm.config_builder()

-- Set the first distro found by 'wsl -l -v' to Wezterm's default_domain
if is_windows then
	local wsl_domains = wezterm.default_wsl_domains()
	if #wsl_domains > 0 then
		config.default_domain = wsl_domains[1].name
	end
end

if wezterm.hostname() == "msipc" then
	config.default_domain = "WSL:archlinux"
end

-- Render on the dedicated GPU when there is one. Pick it by type, not by index:
-- the enumeration order changes between drivers and WezTerm builds.
if is_windows and wezterm.gui then
	for _, gpu in ipairs(wezterm.gui.enumerate_gpus()) do
		if gpu.backend == "Vulkan" and gpu.device_type == "DiscreteGpu" then
			config.webgpu_preferred_adapter = gpu
			config.front_end = "WebGpu"
			break
		end
	end
end

config.initial_rows = 50
config.initial_cols = 180

config.color_scheme = "Tokyo Night Moon"

config.font = wezterm.font_with_fallback({
	"MesloLGS Nerd Font Mono",
	"Symbols Nerd Font Mono",
})
config.font_size = 14

config.window_decorations = "TITLE|RESIZE"
config.hide_tab_bar_if_only_one_tab = true
config.window_background_opacity = 0.8

config.keys = {
	-- {key="g", mods="CTRL", action=wezterm.action.SendString("gitui\n")},
}

-- and finally, return the configuration to wezterm
return config
