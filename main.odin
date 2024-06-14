package wm

import "base:runtime"

import "core:fmt"
import "core:log"
import "core:mem"
import "core:mem/virtual"
import "core:os"
import "core:strings"
import "core:sync"
import "core:text/match"
import "core:time"

import win32 "core:sys/windows"

LOGGER_LEVEL :: log.Level.Info

L :: win32.L

Window_Event :: enum u32 {
	Foreground    = 0x0003,
	MoveSizeEnd   = 0x000B,
	MinimizeStart = 0x0016,
	MinimizeEnd   = 0x0017,
	Destroy       = 0x8001,
	Show          = 0x8002,
	Hide          = 0x8003,
	NameChange    = 0x800C,
	Cloaked       = 0x8017,
	Uncloaked     = 0x8018,
}

Window_Message :: struct {
	hwnd:  win32.HWND,
	event: Window_Event,
}

message_queue := make([dynamic]Window_Message)

Layout :: enum {
	Vertical,
	Horizontal,
	Monocle,
	Stack,
	Dwindle,
}

Window_Behaviour :: enum {
	Invalid = 0,
	Ignore,
	Tiling,
	Floating,
	Hidden,
	Fullscreen,
}

Padding :: struct {
	left, right, top, bottom: i32,
}

Workspace :: struct {
	windows:          [dynamic]Window,
	floating_windows: [dynamic]Window,
	focused_window:   Window_Index,
	layout:           Layout,
	h_flip, v_flip:   bool,
	dirty:            bool,
}

Window_Index :: bit_field int {
	index:    int  | 63,
	floating: bool | 1,
}

Window :: struct {
	rect, border_delta:         Rect,
	class, title:               string,
	hwnd:                       win32.HWND,
	style, ex_style:            win32.DWORD `fmt:"8x"`,
	minimized, cloaked, hidden: bool,
}

workspaces: [10]Workspace
focused_workspace: int

start_time := time.now()

permanent_allocator: mem.Allocator
window_text_allocator: mem.Allocator

last_error_time: time.Time
last_error_string: string
error_mutex: sync.Mutex

work_area: Rect
monitor_resolution: [2]i32

allocators_init :: proc() {
	{
		arena := new(virtual.Arena)
		if err := virtual.arena_init_growing(arena); err != nil {
			fmt.panicf("Failed to initialize permanent allocator: %v", err)
		}
		permanent_allocator = virtual.arena_allocator(arena)
	}

	for &a in config_allocators {
		arena := new(virtual.Arena)
		if err := virtual.arena_init_growing(arena); err != nil {
			fmt.panicf("Failed to initialize config allocator: %v", err)
		}
		a = virtual.arena_allocator(arena)
	}

	for &a in keybind_allocators {
		arena := new(virtual.Arena)
		if err := virtual.arena_init_growing(arena); err != nil {
			fmt.panicf("Failed to initialize keybind allocator: %v", err)
		}
		a = virtual.arena_allocator(arena)
	}
}

main :: proc() {
	win32.SetUnhandledExceptionFilter(unhandled_exception_filter)
	win32.SetConsoleOutputCP(win32.CP_UTF8)

	allocators_init()

	when ODIN_DEBUG {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		defer mem.tracking_allocator_destroy(&track)
		context.allocator = mem.tracking_allocator(&track)

		defer {
			for _, leak in track.allocation_map {
				fmt.printf("%v leaked %m\n", leak.location, leak.size)
			}
			for bad_free in track.bad_free_array {
				fmt.printf(
					"%v allocation %p was freed badly\n",
					bad_free.location,
					bad_free.memory,
				)
			}
		}
	}

	window_text_allocator = context.allocator

	context.logger = create_logger()

	context.assertion_failure_proc =
	proc(prefix, message: string, loc: runtime.Source_Code_Location) -> ! {
		restore_windows()
		log.fatal(prefix, message)
		runtime.trap()
	}

	win32.SetWindowsHookExW(win32.WH_KEYBOARD_LL, keyboard_hook_proc, nil, 0)
	win32.SetWindowsHookExW(win32.WH_MOUSE_LL, mouse_hook_proc, nil, 0)

	for event in Window_Event {
		win32.SetWinEventHook(win32.DWORD(event), win32.DWORD(event), nil, hook_proc, 0, 0, {})
	}

	generate_default_config()
	reload_config()

	generate_default_keybinds()
	reload_keybinds()

	area: Rect
	win32.SystemParametersInfoW(win32.SPI_GETWORKAREA, 0, &area, 0)

	monitor_resolution.x = area.right
	monitor_resolution.y = area.bottom

	work_area = {
		config.padding.left,
		config.bar.margin.y + config.padding.top + config.bar.height,
		monitor_resolution.x - config.padding.right,
		monitor_resolution.y - config.padding.bottom,
	}

	create_helper_window()

	for &workspace in workspaces {
		workspace.windows = make([dynamic]Window, permanent_allocator)
		workspace.floating_windows = make([dynamic]Window, permanent_allocator)
		// workspace.hidden_windows = make([dynamic]Window, permanent_allocator)
		workspace.layout = config.default_layout
	}

	{
		enum_windows_proc :: proc(hwnd: win32.HWND) -> win32.BOOL {
			manage_window(hwnd)
			return true
		}

		_context := context
		win32.EnumWindows(auto_cast enum_windows_proc, transmute(win32.LPARAM)&_context)
	}

	create_bar_window()

	selected_window_border = create_window_border(69)

	retile(workspaces[0])
	if window := get_focused_window(workspaces[0]); window != nil {
		focus_window(window^)
	}

	update_bar_state()

	win32.SetConsoleCtrlHandler(ctrl_handler, true)

	msg: win32.MSG
	for {
		for win32.PeekMessageW(&msg, nil, 0, 0, 1) {
			win32.TranslateMessage(&msg)
			win32.DispatchMessageW(&msg)
		}

		log.debug("Handling Inputs")
		if handle_inputs(workspaces[:], &focused_workspace) do break

		log.debug("Handling Messages")
		handle_window_messages(&workspaces[focused_workspace])

		if workspaces[focused_workspace].dirty {
			log.debug("Retiling")
			retile(workspaces[focused_workspace])
			workspaces[focused_workspace].dirty = false
		}

		free_all(context.temp_allocator)

		win32.WaitMessage()
	}

	log.info("Quitting WM")

	restore_windows()
}

workspace_get_next_window :: proc(workspace: Workspace, direction: Direction) -> int {
	assert(!workspace.focused_window.floating)
	if len(workspace.windows) < 2 {
		return 0
	}

	direction := direction

	if workspace.h_flip {
		if direction == .Left {
			direction = .Right
		} else if direction == .Right {
			direction = .Left
		}
	}

	if workspace.v_flip {
		if direction == .Up {
			direction = .Down
		} else if direction == .Down {
			direction = .Up
		}
	}

	index := workspace.focused_window.index
	new_index := workspace.focused_window.index

	switch workspace.layout {
	case .Vertical:
		#partial switch direction {
		case .Left:
			if index > 0 {
				new_index = index - 1
			}
		case .Right:
			if index < len(workspace.windows) - 1 {
				new_index = index + 1
			}
		}
	case .Horizontal:
		#partial switch direction {
		case .Up:
			if index > 0 {
				new_index = index - 1
			}
		case .Down:
			if index < len(workspace.windows) - 1 {
				new_index = index + 1
			}
		}
	case .Monocle:
		#partial switch direction {
		case .Left, .Down:
			if index > 0 {
				new_index = index - 1
			}
		case .Right, .Up:
			if index < len(workspace.windows) - 1 {
				new_index = index + 1
			}
		}
	case .Dwindle:
		if index % 2 == 0 {
			#partial switch direction {
			case .Left:
				if index > 1 {
					new_index = index - 2
				}
			case .Right:
				if index < len(workspace.windows) - 1 {
					new_index = index + 1
				}
			case .Up:
				if index > 0 {
					new_index = index - 1
				}
			case .Down:
			}
		} else {
			#partial switch direction {
			case .Left:
				if index > 0 {
					new_index = index - 1
				}
			case .Right:
			case .Up:
				if index > 1 {
					new_index = index - 2
				}
			case .Down:
				if index < len(workspace.windows) - 1 {
					new_index = index + 1
				}
			}
		}
	case .Stack:
		switch direction {
		case .Left:
			new_index = 0
		case .Right:
			if index == 0 {
				if workspace.v_flip {
					new_index = len(workspace.windows) - 1
				} else {
					new_index = 1
				}
			}
		case .Up:
			if index > 1 {
				new_index -= 1
			} else if index == 1 {
				new_index = len(workspace.windows) - 1
			}
		case .Down:
			if index > 0 {
				if index < len(workspace.windows) - 1 {
					new_index += 1
				} else {
					new_index = 1
				}
			}
		}
	}

	return new_index
}

workspace_move_focus :: proc(workspace: ^Workspace, direction: Direction) {
	if workspace.focused_window.floating {
		if len(workspace.floating_windows) == 0 {
			return
		}
		switch direction {
		case .Left, .Up:
			workspace.focused_window.index =
				(workspace.focused_window.index - 1) %% len(workspace.floating_windows)
		case .Right, .Down:
			workspace.focused_window.index =
				(workspace.focused_window.index + 1) %% len(workspace.floating_windows)
		}
		workspace.dirty = true
	} else {
		if new_index := workspace_get_next_window(workspace^, direction);
		   new_index != workspace.focused_window.index {
			workspace.focused_window = {
				index    = new_index,
				floating = false,
			}
			focus_window(workspace.windows[workspace.focused_window.index])
			update_bar_state()
		}
	}
}

workspace_move_window :: proc(workspace: ^Workspace, direction: Direction) {
	if workspace.focused_window.floating {
		if window := get_focused_window(workspace^); window != nil {
			d: [2]i32
			switch direction {
			case .Left:
				d.x = -50
			case .Right:
				d.x = 50
			case .Up:
				d.y = -50
			case .Down:
				d.y = 50
			}

			window.rect.left += d.x
			window.rect.right += d.x
			window.rect.top += d.y
			window.rect.bottom += d.y

			set_window_pos(window.hwnd, window.rect, win32.HWND_TOPMOST)
			update_focused_window_border(workspace^)
		}
		return
	}
	if new_index := workspace_get_next_window(workspace^, direction);
	   new_index != workspace.focused_window.index {
		tmp := workspace.windows[workspace.focused_window.index]

		// this makes windows that move by more than one index behaive more intuitively than just swapping them
		if new_index > workspace.focused_window.index {
			copy(
				workspace.windows[workspace.focused_window.index:new_index],
				workspace.windows[1:][workspace.focused_window.index:new_index],
			)
		} else {
			copy(
				workspace.windows[1:][new_index:workspace.focused_window.index],
				workspace.windows[new_index:workspace.focused_window.index],
			)
		}

		workspace.windows[new_index] = tmp

		workspace.dirty = true
		workspace.focused_window.index = new_index
		focus_window(workspace.windows[workspace.focused_window.index])
	}
}

get_focused_window :: proc "contextless" (workspace: Workspace) -> ^Window {
	if workspace.focused_window.floating {
		if len(workspace.floating_windows) == 0 {
			return nil
		}
		return &workspace.floating_windows[workspace.focused_window.index]
	} else {
		if len(workspace.windows) == 0 {
			return nil
		}
		return &workspace.windows[workspace.focused_window.index]
	}
}

center_window :: proc "contextless" (window: ^Window) {
	mid: [2]i32 = {window.rect.left + window.rect.right, window.rect.top + window.rect.bottom} / 2
	d := [2]i32{work_area.right + work_area.left, work_area.bottom + work_area.top} / 2 - mid

	window.rect.left += d.x
	window.rect.right += d.x
	window.rect.top += d.y
	window.rect.bottom += d.y

	set_window_pos(window.hwnd, window.rect, win32.HWND_TOPMOST)
}

handle_inputs :: proc(workspaces: []Workspace, selected_workspace: ^int) -> (should_close: bool) {
	workspace := &workspaces[selected_workspace^]
	for {
		input := pop_safe(&input_queue) or_break

		switch v in input {
		case Action_Focus:
			switch v in v {
			case Direction:
				workspace_move_focus(workspace, v)
			case int:
				new_workspace := v
				if new_workspace != selected_workspace^ {
					hide_workspace(workspaces[selected_workspace^])
					show_workspace(workspaces[new_workspace])
					selected_workspace^ = new_workspace
					update_bar_state()
				}
			case bool:
				if workspace.focused_window.floating == v {
					break
				}
				old_focus := workspace.focused_window
				workspace.focused_window = {
					index    = 0,
					floating = v,
				}
				if window := get_focused_window(workspace^); window == nil {
					workspace.focused_window = old_focus
				}
				workspace.dirty = true
			}
		case Action_Move:
			switch v in v {
			case int:
				new_workspace := v
				if new_workspace != selected_workspace^ {
					moved_window: Maybe(Window)

					floating := workspace.focused_window.floating

					if floating {
						if len(workspace.floating_windows) != 0 {
							moved_window =
								workspace.floating_windows[workspace.focused_window.index]
							ordered_remove(
								&workspace.floating_windows,
								workspace.focused_window.index,
							)
							workspace.dirty = true

							if len(workspace.floating_windows) == 0 {
								workspace.focused_window = {}
							} else if workspace.focused_window.index ==
							   len(workspace.floating_windows) {
								workspace.focused_window.index -= 1
							}
						}
					} else {
						if len(workspace.windows) != 0 {
							moved_window = workspace.windows[workspace.focused_window.index]
							ordered_remove(&workspace.windows, workspace.focused_window.index)
							workspace.dirty = true

							if len(workspace.windows) == 0 {
								workspace.focused_window.index = 0
							} else if workspace.focused_window.index == len(workspace.windows) {
								workspace.focused_window.index -= 1
							}
						}
					}

					hide_workspace(workspaces[selected_workspace^])

					if window, ok := moved_window.?; ok {
						if floating {
							workspaces[new_workspace].focused_window = {
								index    = len(workspaces[new_workspace].floating_windows),
								floating = true,
							}
							append(&workspaces[new_workspace].floating_windows, window)
							workspaces[new_workspace].dirty = true
						} else {
							workspaces[new_workspace].focused_window = {
								index    = len(workspaces[new_workspace].windows),
								floating = false,
							}
							append(&workspaces[new_workspace].windows, window)
							workspaces[new_workspace].dirty = true
						}

					}
					show_workspace(workspaces[new_workspace])
					selected_workspace^ = new_workspace
					update_bar_state()
				}
			case Direction:
				workspace_move_window(workspace, v)
			case bool:
				if v == workspace.focused_window.floating {
					break
				}
				if window := get_focused_window(workspace^); window != nil {
					if v {
						window := workspace.windows[workspace.focused_window.index]
						ordered_remove(&workspace.windows, workspace.focused_window.index)
						center_window(&window)
						workspace.focused_window = {
							index    = len(workspace.floating_windows),
							floating = true,
						}
						append(&workspace.floating_windows, window)
					} else {
						window := workspace.floating_windows[workspace.focused_window.index]
						ordered_remove(&workspace.floating_windows, workspace.focused_window.index)
						workspace.focused_window = {
							index    = len(workspace.windows),
							floating = false,
						}
						append(&workspace.windows, window)
					}
					workspace.dirty = true
				}
			}
		case Action_Window_Close:
			window := get_focused_window(workspace^)
			if window == nil {
				continue
			}
			if win32.SUCCEEDED(win32.PostMessageW(window.hwnd, win32.WM_CLOSE, 0, 0)) {
				if workspace.focused_window.floating {
					if len(workspace.floating_windows) == 1 {
						workspace.focused_window = {
							index    = 0,
							floating = false,
						}
						break
					}
					if workspace.focused_window.index == len(workspace.floating_windows) - 1 {
						workspace.focused_window.index -= 1
					}
					focus_window(workspace.floating_windows[workspace.focused_window.index])
				} else {
					if len(workspace.windows) == 1 {
						workspace.focused_window.index = 0
						break
					}
					if workspace.focused_window.index == len(workspace.windows) - 1 {
						workspace.focused_window.index -= 1
					}
					focus_window(workspace.windows[workspace.focused_window.index])
				}
			} else {
				log.error("Failed to destroy window:", window.title, window.hwnd)
			}
			update_bar_state()
		case Action_Toggle_Layout:
			if workspace.layout == v.a {
				workspace.layout = v.b
			} else {
				workspace.layout = v.a
			}
			workspace.dirty = true
			update_bar_state()
		case Action_Set_Layout:
			layout := Layout(v)
			if workspace.layout != layout {
				workspace.layout = layout
				workspace.dirty = true
			}
			update_bar_state()
		case Action_Start_Process:
			win32.CoInitializeEx(
				nil,
				win32.COINIT.APARTMENTTHREADED | win32.COINIT.DISABLE_OLE1DDE,
			)
			defer win32.CoUninitialize()
			result := win32.ShellExecuteW(
				nil,
				nil,
				win32.utf8_to_wstring(v.path),
				nil,
				win32.utf8_to_wstring(v.dir),
				win32.SW_SHOWNORMAL,
			)
			if uintptr(result) > 32 {
				log.info("Opened terminal")
			} else {
				log.error("Failed to open terminal")
			}
		case Action_Quit:
			return true
		case Action_Log_Debug:
			for workspace in workspaces {
				for window in workspace.windows {
					log.infof("%#v", window)
					log.info(get_window_rect(window.hwnd))
				}
				for window in workspace.floating_windows {
					log.infof("%#v", window)
					log.info(get_window_rect(window.hwnd))
				}
			}
		case Action_Retile:
			retile(workspace^)
			update_bar_state()
		case Action_Reload_Config:
			reload_config()
			reload_keybinds()

			workspace.dirty = true
			update_bar_state()

			work_area = {
				config.padding.left,
				config.bar.margin.y + config.padding.top + config.bar.height,
				monitor_resolution.x - config.padding.right,
				monitor_resolution.y - config.padding.bottom,
			}

			update_bar_position()

		case Action_Toggle_Floating:
			if window := get_focused_window(workspace^); window != nil {
				window := window^
				if workspace.focused_window.floating {
					ordered_remove(&workspace.floating_windows, workspace.focused_window.index)
					workspace.focused_window = {
						index    = len(workspace.windows),
						floating = false,
					}
					append(&workspace.windows, window)
				} else {
					ordered_remove(&workspace.windows, workspace.focused_window.index)
					center_window(&window)
					workspace.focused_window = {
						index    = len(workspace.floating_windows),
						floating = true,
					}
					append(&workspace.floating_windows, window)
				}
				workspace.dirty = true
			}
		case Action_Set_Behaviour:
			switch v.behaviour {
			case .Invalid:
			case .Ignore:
			case .Floating:
			case .Tiling:
			case .Hidden:
			case .Fullscreen:
			}

		case Action_Toggle_Focus_Floating:
			old_focus := workspace.focused_window
			workspace.focused_window = {
				index    = 0,
				floating = !workspace.focused_window.floating,
			}
			if window := get_focused_window(workspace^); window == nil {
				workspace.focused_window = old_focus
			} else {
				workspace.dirty = true
			}
		case Action_Flip:
			if v.vertical {
				workspace.v_flip = !workspace.v_flip
			} else {
				workspace.h_flip = !workspace.h_flip
			}
			workspace.dirty = true
			update_bar_state()
		case Action_Remove_Titlebar:
			window := get_focused_window(workspace^)
			if window == nil {
				break
			}
			if !remove_window_title_bar(window.hwnd) {
				log.error("Failed to remove titlebar from window", window.title)
			} else {
				window.border_delta = {}
				workspace.dirty = true
			}
		}
	}

	return
}

update_focused_window_border :: proc(workspace: Workspace) {
	window := get_focused_window(workspace)
	if window == nil {
		hide_window_border(selected_window_border)
		return
	}
	if workspace.focused_window.floating {
		rect := window.rect
		rect.left -= config.border.width - window.border_delta.left
		rect.top -= config.border.width - window.border_delta.top
		rect.right += config.border.width - window.border_delta.right
		rect.bottom += config.border.width - window.border_delta.bottom
		update_window_border(selected_window_border, rect, window.hwnd)
	} else {
		update_window_border(selected_window_border, window.rect, window.hwnd)
	}
}

handle_window_message :: proc(
	workspace: ^Workspace,
	msg: Window_Message,
	window: ^Window,
	window_index: Window_Index,
) {
	switch msg.event {
	case .Foreground:
		workspace.focused_window = window_index
		update_bar_state()
		workspace.dirty = true
	case .MoveSizeEnd:
		window.rect = get_window_rect(window.hwnd)
		workspace.dirty = true
	case .Destroy, .Cloaked, .Hide, .MinimizeStart:
		delete(window.class, window_text_allocator)
		delete(window.title, window_text_allocator)
		if window_index.floating {
			ordered_remove(&workspace.floating_windows, window_index.index)
			if workspace.focused_window.index == len(workspace.floating_windows) &&
			   len(workspace.floating_windows) != 0 {
				workspace.focused_window.index -= 1
			}
		} else {
			ordered_remove(&workspace.windows, window_index.index)
			if workspace.focused_window.index == len(workspace.windows) &&
			   len(workspace.windows) != 0 {
				workspace.focused_window.index -= 1
			}
		}
		if window_index == {index = dragged_window, floating = true} {
			if sizing {
				end_window_resize()
			}
			if dragging {
				end_window_drag()
			}
		}
		update_bar_state()
		workspace.dirty = true
	case .Show:
		window.hidden = false
		workspace.dirty = true
	case .MinimizeEnd:
		window.hidden = false
		workspace.dirty = true
	case .Uncloaked:
		window.cloaked = false
		workspace.dirty = true
	case .NameChange:
		delete(window.title, window_text_allocator)
		window.title = get_window_title(window.hwnd, window_text_allocator)
		update_bar_state()
	}
}

// TODO(Franz): filter out messages from other workspaces
handle_window_messages :: proc(workspace: ^Workspace) {
	msg_loop: for {
		msg := pop_safe(&message_queue) or_break
		for &window, i in workspace.floating_windows {
			if window.hwnd == msg.hwnd {
				handle_window_message(workspace, msg, &window, {index = i, floating = true})
				continue msg_loop
			}
		}
		for &window, i in workspace.windows {
			if window.hwnd == msg.hwnd {
				handle_window_message(workspace, msg, &window, {index = i, floating = false})
				continue msg_loop
			}
		}

		#partial switch msg.event {
		case .Show, .Uncloaked, .MinimizeEnd:
			manage_window(msg.hwnd, true)
		}
	}
}

hide_workspace :: proc(workspace: Workspace) {
	for window in workspace.windows {
		win32.ShowWindow(window.hwnd, win32.SW_HIDE)
	}

	for window in workspace.floating_windows {
		win32.ShowWindow(window.hwnd, win32.SW_HIDE)
	}
}

show_workspace :: proc(workspace: Workspace) {
	for window in workspace.windows {
		win32.ShowWindow(window.hwnd, win32.SW_SHOWNA)
	}

	for window in workspace.floating_windows {
		win32.ShowWindow(window.hwnd, win32.SW_SHOWNA)
	}

	if focused_window := get_focused_window(workspace); focused_window != nil {
		focus_window(focused_window^)
	} else {
		hide_window_border(selected_window_border)
	}
}

retile :: proc(workspace: Workspace) {
	n := i32(len(workspace.windows))
	if n != 0 {
		switch workspace.layout {
		case .Vertical:
			x: i32
			window_width := (work_area.right - work_area.left + config.gap) / n
			for &window in workspace.windows {
				window.rect = {
					work_area.left + x,
					work_area.top,
					work_area.left + x + window_width - config.gap,
					work_area.bottom,
				}
				x += window_width
			}
		case .Horizontal:
			y: i32
			window_height := (work_area.bottom - work_area.top + config.gap) / n
			for &window in workspace.windows {
				window.rect = {
					work_area.left,
					work_area.top + y,
					work_area.right,
					work_area.top + y + window_height - config.gap,
				}
				y += window_height
			}
		case .Monocle:
			// NOTE(Franz): this doesn't work with floating windows but I usually dont use this layout with floating windows...
			for &window, i in workspace.windows {
				if i == workspace.focused_window.index {
					window.rect = work_area
				} else {
					window.rect = {
						left   = monitor_resolution.x,
						top    = monitor_resolution.y,
						right  = monitor_resolution.x + work_area.right - work_area.left,
						bottom = monitor_resolution.y + work_area.bottom - work_area.top,
					}
				}
			}
		case .Stack:
			switch n {
			case 1:
				workspace.windows[0].rect = work_area
			case:
				window_width := (work_area.right - work_area.left - config.gap) / 2
				workspace.windows[0].rect = {
					work_area.left,
					work_area.top,
					work_area.left + window_width,
					work_area.bottom,
				}

				y: i32
				window_height := (work_area.bottom - work_area.top + config.gap) / (n - 1)
				for &window in workspace.windows[1:] {
					window.rect = {
						work_area.left + window_width + config.gap,
						work_area.top + y,
						work_area.right,
						work_area.top + y + window_height - config.gap,
					}
					y += window_height
				}
			}
		case .Dwindle:
			window_width := work_area.right - work_area.left + config.gap
			window_height := work_area.bottom - work_area.top + config.gap

			x, y := work_area.left, work_area.top

			for &window, i in workspace.windows[:len(workspace.windows) - 1] {
				if i % 2 == 0 {
					window_width /= 2
				} else {
					window_height /= 2
				}
				window.rect = {x, y, x + window_width - config.gap, y + window_height - config.gap}
				if i % 2 == 0 {
					x += window_width
				} else {
					y += window_height
				}
			}

			workspace.windows[len(workspace.windows) - 1].rect = {
				x,
				y,
				x + window_width - config.gap,
				y + window_height - config.gap,
			}
		}

		for &window in workspace.windows {
			if workspace.h_flip {
				new_rect: Rect = window.rect
				center := (work_area.right + work_area.left) / 2
				new_rect.left = 2 * center - window.rect.right
				new_rect.right = 2 * center - window.rect.left
				window.rect = new_rect
			}
			if workspace.v_flip {
				new_rect: Rect = window.rect
				center := (work_area.bottom + work_area.top) / 2
				new_rect.top = 2 * center - window.rect.bottom
				new_rect.bottom = 2 * center - window.rect.top
				window.rect = new_rect
			}

			set_window_pos(
				window.hwnd,
				{
					window.rect.left - window.border_delta.left + config.border.width,
					window.rect.top - window.border_delta.top + config.border.width,
					window.rect.right + window.border_delta.right - config.border.width,
					window.rect.bottom + window.border_delta.bottom - config.border.width,
				},
				win32.HWND_NOTOPMOST,
			)
		}
	}

	for window in workspace.floating_windows {
		set_window_pos(window.hwnd, window.rect, win32.HWND_TOPMOST)
	}

	update_focused_window_border(workspace)
}

focus_window :: proc(window: Window) {
	fake_input: win32.INPUT = {
		type = win32.INPUT_TYPE.KEYBOARD,
		ki   = {},
	}
	win32.SendInput(1, &fake_input, size_of(fake_input))
	win32.SetForegroundWindow(window.hwnd)
}

restore_windows :: proc "contextless" () {
	context = {}
	for &workspace in workspaces {
		for &window in workspace.windows {
			win32.ShowWindow(window.hwnd, win32.SW_SHOW)
			delete(window.class, window_text_allocator)
			delete(window.title, window_text_allocator)
			window.class = ""
			window.title = ""
		}
		for &window in workspace.floating_windows {
			win32.ShowWindow(window.hwnd, win32.SW_SHOW)
			delete(window.class, window_text_allocator)
			delete(window.title, window_text_allocator)
			window.class = ""
			window.title = ""
		}
	}
}

manage_window :: proc(hwnd: win32.HWND, focus: bool = false) {
	workspace := &workspaces[focused_workspace]
	window: Window = {
		hwnd = hwnd,
	}
	collect_window_information(&window)
	b := get_window_behaviour(window)
	set_window_border_delta(&window)
	if b_ := apply_window_rules(&window); b_ != nil {
		b = b_
	}
	#partial switch b {
	case .Tiling:
		if focus {
			workspace.focused_window = {
				index    = len(workspace.windows),
				floating = false,
			}
		}
		append(&workspace.windows, window)
		workspace.dirty = true
	case .Floating:
		if focus {
			workspace.focused_window = {
				index    = len(workspace.floating_windows),
				floating = true,
			}
		}
		append(&workspace.floating_windows, window)
		workspace.dirty = true
	case:
		delete(window.title, window_text_allocator)
		delete(window.class, window_text_allocator)
		return
	}

	if focus {
		focus_window(window)
		update_bar_state()
	}
}

apply_window_rules :: proc(window: ^Window) -> Window_Behaviour {
	for rule in config.window_rules {
		title_match: bool = len(rule.titles) == 0
		for title in rule.titles {
			matcher := match.matcher_init(window.title, title)
			match.matcher_match(&matcher) or_continue
			title_match = true
			break
		}
		if !title_match {
			continue
		}
		class_match: bool = len(rule.classes) == 0
		for class in rule.classes {
			matcher := match.matcher_init(window.class, class)
			match.matcher_match(&matcher) or_continue
			class_match = true
			break
		}
		if !class_match {
			continue
		}

		if rule.remove_title_bar {
			remove_window_title_bar(window.hwnd)
		}
		if rule.border != nil {
			window.border_delta = rule.border.?
		}
		if rule.behaviour != nil {
			return rule.behaviour
		}
		return nil
	}

	return nil
}

