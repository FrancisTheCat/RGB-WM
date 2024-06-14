package wm

import "core:encoding/json"
import "core:log"
import "core:mem"
import "core:os"

config: Config
config_allocators: [2]mem.Allocator

Config :: struct {
	border:         Border_Config,
	bar:            Bar_Config,
	padding:        Rect,
	gap:            i32,
	default_layout: Layout,
	window_rules:   Window_Rule_Config,
}

Border_Config :: struct {
	enabled:              bool,
	width, inset, radius: i32,
	color:                ColorRGBA,
	chroma:               Chroma_Config,
}

Chroma_Config :: struct {
	enabled: bool,
	speed:   f32,
	fps:     i32,
}

Bar_Config :: struct {
	enabled:          bool,
	height:           i32,
	margin:           struct {
		x, y: i32,
	},
	border:           Border_Config,
	text_padding:     i32,
	font_size:        i32,
	text_shadow:      bool,
	background_color: ColorRGBA,
	workspaces:       Bar_Workspaces_Config,
	layout:           Bar_Layout_Config,
	title:            Bar_Title_Config,
	clock:            Bar_Clock_Config,
	battery:          Bar_Battery_Config,
}

Bar_Workspaces_Config :: struct {
	enabled:                                   bool,
	focus_color, active_color, inactive_color: ColorRGBA,
	show_inactive:                             bool,
}

Bar_Layout_Config :: struct {
	enabled: bool,
	color:   ColorRGBA,
}

Bar_Title_Config :: struct {
	enabled:       bool,
	color:         ColorRGBA,
	format_string: string,
	max_length:    i32,
}

Bar_Battery_Config :: struct {
	enabled:                                    bool,
	color, charging_color, battery_saver_color: ColorRGBA,
}

Bar_Clock_Config :: struct {
	enabled:       bool,
	color:         ColorRGBA,
	format_string: string,
}

generate_default_config :: proc() {
	if !os.exists("config.json") {
		log.assert(
			os.write_entire_file("config.json", #load("default_config.json")),
			"failed to write default config",
		)
	}
}

reload_config :: proc() {
	data, ok := os.read_entire_file("config.json", context.temp_allocator)
	if !ok {
		log.error("Failed to read config.json")
		return
	}
	c: Config
	if err := json.unmarshal(data, &c, allocator = config_allocators.x); err == nil {
		log.info("reloaded config")

		config = c
		config_allocators.xy = config_allocators.yx
		free_all(config_allocators.x)
	} else {
		log.error("Failed to parse config.json:", err)
		free_all(config_allocators.x)
	}
}

Window_Rule_Config :: distinct []Window_Rule

Window_Rule :: struct {
	titles, classes:  []string,
	behaviour:        Window_Behaviour,
	border:           Maybe(Rect),
	remove_title_bar: bool,
}

