package wm

import "core:log"
import "core:mem"
import "core:os"
import "core:reflect"
import "core:strconv"
import "core:strings"
import "core:testing"

import win32 "core:sys/windows"

keybinds: []Keybind
keybind_allocators: [2]mem.Allocator

Key :: enum u8 {
	Back                = win32.VK_BACK,
	Tab                 = win32.VK_TAB,
	Clear               = win32.VK_CLEAR,
	Return              = win32.VK_RETURN,
	Shift               = win32.VK_SHIFT,
	Control             = win32.VK_CONTROL,
	Menu                = win32.VK_MENU,
	Pause               = win32.VK_PAUSE,
	Capital             = win32.VK_CAPITAL,
	Kana                = win32.VK_KANA,
	Hangeul             = win32.VK_HANGEUL,
	Hangul              = win32.VK_HANGUL,
	Ime_on              = win32.VK_IME_ON,
	Junja               = win32.VK_JUNJA,
	Final               = win32.VK_FINAL,
	Hanja               = win32.VK_HANJA,
	Kanji               = win32.VK_KANJI,
	Ime_off             = win32.VK_IME_OFF,
	Escape              = win32.VK_ESCAPE,
	Convert             = win32.VK_CONVERT,
	Nonconvert          = win32.VK_NONCONVERT,
	Accept              = win32.VK_ACCEPT,
	Modechange          = win32.VK_MODECHANGE,
	Space               = win32.VK_SPACE,
	Prior               = win32.VK_PRIOR,
	Next                = win32.VK_NEXT,
	End                 = win32.VK_END,
	Home                = win32.VK_HOME,
	Left                = win32.VK_LEFT,
	Up                  = win32.VK_UP,
	Right               = win32.VK_RIGHT,
	Down                = win32.VK_DOWN,
	Select              = win32.VK_SELECT,
	Print               = win32.VK_PRINT,
	Execute             = win32.VK_EXECUTE,
	Snapshot            = win32.VK_SNAPSHOT,
	Insert              = win32.VK_INSERT,
	Delete              = win32.VK_DELETE,
	Help                = win32.VK_HELP,
	_0                  = win32.VK_0,
	_1                  = win32.VK_1,
	_2                  = win32.VK_2,
	_3                  = win32.VK_3,
	_4                  = win32.VK_4,
	_5                  = win32.VK_5,
	_6                  = win32.VK_6,
	_7                  = win32.VK_7,
	_8                  = win32.VK_8,
	_9                  = win32.VK_9,
	A                   = win32.VK_A,
	B                   = win32.VK_B,
	C                   = win32.VK_C,
	D                   = win32.VK_D,
	E                   = win32.VK_E,
	F                   = win32.VK_F,
	G                   = win32.VK_G,
	H                   = win32.VK_H,
	I                   = win32.VK_I,
	J                   = win32.VK_J,
	K                   = win32.VK_K,
	L                   = win32.VK_L,
	M                   = win32.VK_M,
	N                   = win32.VK_N,
	O                   = win32.VK_O,
	P                   = win32.VK_P,
	Q                   = win32.VK_Q,
	R                   = win32.VK_R,
	S                   = win32.VK_S,
	T                   = win32.VK_T,
	U                   = win32.VK_U,
	V                   = win32.VK_V,
	W                   = win32.VK_W,
	X                   = win32.VK_X,
	Y                   = win32.VK_Y,
	Z                   = win32.VK_Z,
	L_Win               = win32.VK_LWIN,
	R_Win               = win32.VK_RWIN,
	Apps                = win32.VK_APPS,
	Sleep               = win32.VK_SLEEP,
	Num_0               = win32.VK_NUMPAD0,
	Num_1               = win32.VK_NUMPAD1,
	Num_2               = win32.VK_NUMPAD2,
	Num_3               = win32.VK_NUMPAD3,
	Num_4               = win32.VK_NUMPAD4,
	Num_5               = win32.VK_NUMPAD5,
	Num_6               = win32.VK_NUMPAD6,
	Num_7               = win32.VK_NUMPAD7,
	Num_8               = win32.VK_NUMPAD8,
	Num_9               = win32.VK_NUMPAD9,
	Multiply            = win32.VK_MULTIPLY,
	Add                 = win32.VK_ADD,
	Separator           = win32.VK_SEPARATOR,
	Subtract            = win32.VK_SUBTRACT,
	Decimal             = win32.VK_DECIMAL,
	Divide              = win32.VK_DIVIDE,
	F1                  = win32.VK_F1,
	F2                  = win32.VK_F2,
	F3                  = win32.VK_F3,
	F4                  = win32.VK_F4,
	F5                  = win32.VK_F5,
	F6                  = win32.VK_F6,
	F7                  = win32.VK_F7,
	F8                  = win32.VK_F8,
	F9                  = win32.VK_F9,
	F10                 = win32.VK_F10,
	F11                 = win32.VK_F11,
	F12                 = win32.VK_F12,
	F13                 = win32.VK_F13,
	F14                 = win32.VK_F14,
	F15                 = win32.VK_F15,
	F16                 = win32.VK_F16,
	F17                 = win32.VK_F17,
	F18                 = win32.VK_F18,
	F19                 = win32.VK_F19,
	F20                 = win32.VK_F20,
	F21                 = win32.VK_F21,
	F22                 = win32.VK_F22,
	F23                 = win32.VK_F23,
	F24                 = win32.VK_F24,
	Numlock             = win32.VK_NUMLOCK,
	Scroll              = win32.VK_SCROLL,
	L_Shift             = win32.VK_LSHIFT,
	R_Shift             = win32.VK_RSHIFT,
	L_Control           = win32.VK_LCONTROL,
	R_Control           = win32.VK_RCONTROL,
	L_Menu              = win32.VK_LMENU,
	R_Menu              = win32.VK_RMENU,
	Browser_Back        = win32.VK_BROWSER_BACK,
	Browser_Rorward     = win32.VK_BROWSER_FORWARD,
	Browser_Refresh     = win32.VK_BROWSER_REFRESH,
	Browser_Stop        = win32.VK_BROWSER_STOP,
	Browser_Search      = win32.VK_BROWSER_SEARCH,
	Browser_Favorites   = win32.VK_BROWSER_FAVORITES,
	Browser_Home        = win32.VK_BROWSER_HOME,
	Volume_Mute         = win32.VK_VOLUME_MUTE,
	Volume_Down         = win32.VK_VOLUME_DOWN,
	Volume_Up           = win32.VK_VOLUME_UP,
	Media_Next_Track    = win32.VK_MEDIA_NEXT_TRACK,
	Media_Nrev_Track    = win32.VK_MEDIA_PREV_TRACK,
	Media_Stop          = win32.VK_MEDIA_STOP,
	Media_Play_Pause    = win32.VK_MEDIA_PLAY_PAUSE,
	Launch_Mail         = win32.VK_LAUNCH_MAIL,
	Launch_Media_Select = win32.VK_LAUNCH_MEDIA_SELECT,
	Launch_App1         = win32.VK_LAUNCH_APP1,
	Launch_App2         = win32.VK_LAUNCH_APP2,
}

Modifier :: enum u8 {
	Alt = 0,
	L_Alt,
	R_Alt,
	Ctrl,
	L_Ctrl,
	R_Ctrl,
	Shift,
	L_Shift,
	R_Shift,
}

modifier_keys := [Modifier]Key {
	.Alt     = Key.Menu,
	.L_Alt   = Key.R_Menu,
	.R_Alt   = Key.R_Menu,
	.Ctrl    = Key.Control,
	.L_Ctrl  = Key.R_Control,
	.R_Ctrl  = Key.R_Control,
	.Shift   = Key.Shift,
	.L_Shift = Key.L_Shift,
	.R_Shift = Key.R_Shift,
}

Keybind :: struct {
	input:  Input,
	action: Action,
}

input_matches_keybind :: proc "contextless" (input: Input, keybind: Input) -> bool {
	if input.key != keybind.key {
		return false
	}

	for mod in keybind.modifiers {
		if mod not_in input.modifiers {
			return false
		}
	}

	NON_GENERIC_MODIFIERS :: bit_set[Modifier] {
		.L_Alt,
		.R_Alt,
		.L_Ctrl,
		.R_Ctrl,
		.L_Shift,
		.R_Shift,
	}

	GENERIC_MODIFIERS :: bit_set[Modifier]{.Alt, .Ctrl, .Shift}

	NON_GENERIC_TO_GENERIC := [Modifier]Modifier {
		.L_Alt   = .Alt,
		.R_Alt   = .Alt,
		.L_Ctrl  = .Ctrl,
		.R_Ctrl  = .Ctrl,
		.L_Shift = .Shift,
		.R_Shift = .Shift,
		.Alt     = .Alt,
		.Shift   = .Shift,
		.Ctrl    = .Ctrl,
	}

	for mod in input.modifiers {
		if mod in NON_GENERIC_MODIFIERS {
			if mod not_in keybind.modifiers &&
			   NON_GENERIC_TO_GENERIC[mod] not_in keybind.modifiers {
				return false
			}
		}
	}

	return true
}

reload_keybinds :: proc() {
	file, ok := os.read_entire_file("keybinds.txt", context.temp_allocator)
	if !ok {
		log.error("failed to read keybind file")
	}
	keybinds_: [dynamic]Keybind
	keybinds_, ok = parse_keybind_list(string(file), keybind_allocators.x)
	if ok {
		keybinds = keybinds_[:]
		log.info("loaded keybinds")
		keybind_allocators.xy = keybind_allocators.yx
		free_all(keybind_allocators.x)
	} else {
		log.error("failed to reload keybinds")
		free_all(keybind_allocators.x)
	}
}

generate_default_keybinds :: proc() {
	if !os.exists("keybinds.txt") {
		log.assert(
			os.write_entire_file("keybinds.txt", #load("default_keybinds.txt")),
			"failed to write default keybinds",
		)
	}
}

ACTION_STRINGS := map[string]Action {
	"remove titlebar"       = Action_Remove_Titlebar{},
	"toggle floating"       = Action_Toggle_Floating{},
	"toggle focus"          = Action_Toggle_Focus_Floating{},
	"flip vertical"         = Action_Flip{true},
	"flip horizontal"       = Action_Flip{false},
	"set floating"          = Action_Move(true),
	"set tiling"            = Action_Move(false),
	"focus floating"        = Action_Focus(true),
	"focus tiling"          = Action_Focus(false),
	"focus left"            = Action_Focus(Direction.Left),
	"focus right"           = Action_Focus(Direction.Right),
	"focus up"              = Action_Focus(Direction.Up),
	"focus down"            = Action_Focus(Direction.Down),
	"move left"             = Action_Move(Direction.Left),
	"move right"            = Action_Move(Direction.Right),
	"move up"               = Action_Move(Direction.Up),
	"move down"             = Action_Move(Direction.Down),
	"focus workspace $"     = Action_Focus(int{}),
	"move workspace $"      = Action_Move(int{}),
	"quit"                  = Action_Quit{},
	"close window"          = Action_Window_Close{},
	"launch $"              = Action_Start_Process{},
	"retile"                = Action_Retile{},
	"print debug info"      = Action_Log_Debug{},
	"set layout vertical"   = Action_Set_Layout.Vertical,
	"set layout horizontal" = Action_Set_Layout.Horizontal,
	"set layout monocle"    = Action_Set_Layout.Monocle,
	"set layout stack"      = Action_Set_Layout.Stack,
	"set layout dwindle"    = Action_Set_Layout.Dwindle,
	"reload config"         = Action_Reload_Config{},
}

Action :: union {
	Action_Focus,
	Action_Move,
	Action_Window_Close,
	Action_Quit,
	Action_Retile,
	Action_Start_Process,
	Action_Log_Debug,
	Action_Toggle_Layout,
	Action_Set_Layout,
	Action_Reload_Config,
	Action_Set_Behaviour,
	Action_Toggle_Floating,
	Action_Toggle_Focus_Floating,
	Action_Flip,
	Action_Remove_Titlebar,
}

Action_Focus :: union {
	int,
	Direction,
	bool,
}

Action_Move :: union {
	int,
	Direction,
	bool,
}

Action_Window_Close :: struct {}

Action_Reload_Config :: struct {}

Direction :: enum {
	Left,
	Right,
	Up,
	Down,
}

Action_Quit :: struct {}

Action_Retile :: struct {}

Action_Log_Debug :: struct {}

Action_Toggle_Layout :: struct {
	a, b: Layout,
}

Action_Set_Layout :: distinct Layout

Action_Start_Process :: struct {
	path, dir, args: string,
}

Action_Set_Behaviour :: struct {
	behaviour: Window_Behaviour,
}

Action_Toggle_Floating :: struct {}

Action_Toggle_Focus_Floating :: struct {}

Action_Flip :: struct {
	vertical: bool,
}

Input :: struct {
	key:       Key,
	modifiers: bit_set[Modifier],
}

Action_Remove_Titlebar :: struct {}

input_queue := make([dynamic]Action)

find_keybind :: proc "contextless" (input: Input) -> (action: Action, found: bool) {
	for keybind in keybinds {
		if input_matches_keybind(input, keybind.input) {
			return keybind.action, true
		}
	}
	return
}

keyboard_hook_proc :: proc "stdcall" (
	n_code: i32,
	w_param: win32.WPARAM,
	l_param: win32.LPARAM,
) -> win32.LRESULT {
	if dragging || sizing {
		return 1
	}
	if n_code != 0 || !(w_param == win32.WM_KEYDOWN || w_param == win32.WM_SYSKEYDOWN) {
		return win32.CallNextHookEx(nil, n_code, w_param, l_param)
	}

	input_event := cast(^win32.KBDLLHOOKSTRUCT)cast(uintptr)l_param

	if action, ok := find_keybind({key = Key(input_event.vkCode), modifiers = get_modifiers()});
	   ok {
		context = {}
		append(&input_queue, action)
		return 1
	}

	return win32.CallNextHookEx(nil, n_code, w_param, l_param)
}

get_modifiers :: proc "contextless" () -> (modifiers: bit_set[Modifier]) {
	for m in Modifier {
		if is_key_pressed(modifier_keys[m]) {
			modifiers += {m}
		}
	}
	return
}

is_key_pressed :: proc "contextless" (key: Key) -> bool {
	return u16(win32.GetKeyState(i32(key))) & 0x8000 == 0x8000
}

parse_key :: proc(str: string) -> (key: Key, ok: bool) {
	str := strings.to_lower(str, context.temp_allocator)
	ti := reflect.type_info_base(type_info_of(Key)).variant.(reflect.Type_Info_Enum)

	for value_name, i in ti.names {
		if len(value_name) == 0 {
			continue
		}
		value_name := value_name
		if value_name[0] == '_' {
			value_name = value_name[1:]
		}
		if strings.to_lower(value_name, context.temp_allocator) != str {
			continue
		}
		v := ti.values[i]
		key = Key(v)
		ok = true
		for mk in modifier_keys {
			if mk == key {
				ok = false
				break
			}
		}
		return
	}
	return
}

parse_modifier :: proc(mod_str: string) -> (mod: Modifier, ok: bool) {
	mod_str := strings.to_lower(mod_str, context.temp_allocator)
	mod_str_no_underscore, _ := strings.remove_all(mod_str, "_")
	ti := reflect.type_info_base(type_info_of(Modifier)).variant.(reflect.Type_Info_Enum)
	for value_name, i in ti.names {
		lower := strings.to_lower(value_name, context.temp_allocator)
		if lower == mod_str || lower == mod_str_no_underscore {
			v := ti.values[i]
			mod = Modifier(v)
			ok = true
			return
		}
	}
	return
}

parse_keybind :: proc(str: string) -> (keybind: Keybind, ok: bool) {
	strs := strings.split_n(str, ":", 2, context.temp_allocator)
	if len(strs) != 2 {
		return
	}

	keybind.input = parse_key_combination(strs[0]) or_return
	keybind.action = parse_action(strs[1]) or_return

	ok = true
	return
}

parse_key_combination :: proc(str: string) -> (input: Input, ok: bool) {
	parts := strings.split(str, "+", context.temp_allocator)
	for part in parts[:len(parts) - 1] {
		input.modifiers += {parse_modifier(strings.trim(part, " ")) or_return}
	}
	input.key = parse_key(strings.trim(parts[len(parts) - 1], " ")) or_return
	ok = true
	return
}

parse_action :: proc(str: string) -> (action: Action, ok: bool) {
	str := strings.to_lower(strings.trim_space(str), context.temp_allocator)
	if action, ok = ACTION_STRINGS[str]; ok {
		return
	}

	for match, a in ACTION_STRINGS {
		if match[len(match) - 1] == '$' {
			if len(str) < len(match) {
				continue
			}
			if str[:len(match) - 1] != match[:len(match) - 1] {
				continue
			}
			args := strings.split(str[len(match) - 1:], " ")

			action = a
			a := any(action)
			for {
				t := reflect.type_info_base(type_info_of(a.id))
				_, ok := t.variant.(reflect.Type_Info_Union)
				if !ok {
					break
				}
				a.id = reflect.union_variant_typeid(any{data = a.data, id = t.id})
			}

			t := reflect.type_info_base(type_info_of(a.id))
			#partial switch t in t.variant {
			case reflect.Type_Info_Struct:
				if len(args) > len(t.names) {
					return
				}
				for arg, i in args {
					#partial switch _ in t.types[i].variant {
					case reflect.Type_Info_String:
						str, allocated := strconv.unquote_string(arg) or_return
						if !allocated {
							str = strings.clone(str)
						}
						(^string)(uintptr(a.data) + t.offsets[i])^ = str
					case:
						return
					}
				}

				ok = true
				return
			case reflect.Type_Info_Integer:
				if len(args) != 1 {
					return
				}

				(^int)(a.data)^ = strconv.parse_int(args[0]) or_return
				ok = true
				return
			}
		}
	}

	return
}

parse_literal_any :: proc(a: any, str: string) -> (ok: bool) {
	switch &v in a {
	case int:
		v = strconv.parse_int(str) or_return
		return true
	case string:
		v, _ = strconv.unquote_string(str, context.temp_allocator) or_return
		return true
	}
	return
}

parse_keybind_list :: proc(
	str: string,
	allocator := context.allocator,
) -> (
	[dynamic]Keybind,
	bool,
) {
	context.allocator = allocator
	s := str
	keybinds := make([dynamic]Keybind)
	i: int
	for line in strings.split_lines_iterator(&s) {
		i += 1
		l := strings.trim(line, " \t\r\n")
		if len(l) == 0 {
			continue
		}
		if l[0] == '#' {
			continue
		}

		if k, ok := parse_keybind(l); ok {
			append(&keybinds, k)
		} else {
			log.error("Error parsing config on line", i)
		}
	}

	return keybinds, true
}

@(test)
test_key_parsing :: proc(t: ^testing.T) {
	ok: bool
	_, ok = parse_key("K")
	testing.expect(t, ok)
	_, ok = parse_key("E")
	testing.expect(t, ok)
	_, ok = parse_key("y")
	testing.expect(t, ok)
	_, ok = parse_key("Ctrl")
	testing.expect(t, !ok)
	_, ok = parse_key("CTRL")
	testing.expect(t, !ok)
	_, ok = parse_key("Return")
	testing.expect(t, ok)
	_, ok = parse_key("Shift")
	testing.expect(t, !ok)
	_, ok = parse_key("Shiftsdfl;kij")
	testing.expect(t, !ok)
}

@(test)
test_modifier_parsing :: proc(t: ^testing.T) {
	ok: bool
	_, ok = parse_modifier("Ctrl")
	testing.expect(t, ok)
	_, ok = parse_modifier("asdf")
	testing.expect(t, !ok)
	_, ok = parse_modifier("ShIFt")
	testing.expect(t, ok)
	_, ok = parse_modifier("SHIFT")
	testing.expect(t, ok)
	_, ok = parse_modifier("K")
	testing.expect(t, !ok)
}

@(test)
test_key_combination_parsing :: proc(t: ^testing.T) {
	ok: bool
	_, ok = parse_key_combination("ctrl+shift+q")
	testing.expect(t, ok)
	_, ok = parse_key_combination("ctrl+alt+x")
	testing.expect(t, ok)
	_, ok = parse_key_combination("ctrl+alt+Esc")
	testing.expect(t, !ok)
	_, ok = parse_key_combination("alt+Enter")
	testing.expect(t, !ok)
	_, ok = parse_key_combination("alt+Return")
	testing.expect(t, ok)
	_, ok = parse_key_combination("alt+Escape")
	testing.expect(t, ok)
}

@(test)
test_action_parsing :: proc(t: ^testing.T) {
	parse_action("Quit")
	parse_action("Launch 'asdf'")
	parse_action("Focus Workspace 8")
}

