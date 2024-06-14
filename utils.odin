package wm

import "core:fmt"
import "core:log"
import "core:os"
import "core:strings"
import "core:sync"
import "core:time"

import win32 "core:sys/windows"

Rect :: win32.RECT

create_helper_window :: proc() {
	class := win32.WNDCLASSW {
		win32.CS_OWNDC,
		win32.DefWindowProcW,
		0,
		0,
		nil,
		nil,
		nil,
		nil,
		nil,
		L("Window manager helper window class"),
	}

	win32.RegisterClassW(&class)

	win32.CreateWindowExW(
		win32.WS_EX_TOOLWINDOW | win32.WS_EX_LAYERED,
		L("Window manager helper window class"),
		L("Window manager helper window"),
		win32.WS_POPUP | win32.WS_SYSMENU,
		0,
		0,
		0,
		0,
		nil,
		nil,
		nil,
		nil,
	)
}

get_window_rect :: proc "contextless" (hwnd: win32.HWND) -> (rect: Rect) {
	if win32.SUCCEEDED(
		win32.DwmGetWindowAttribute(
			hwnd,
			u32(win32.DWMWINDOWATTRIBUTE.DWMWA_EXTENDED_FRAME_BOUNDS),
			&rect,
			size_of(rect),
		),
	) {
		return rect
	} else {
		win32.GetWindowRect(hwnd, &rect)
		return
	}
}

ctrl_handler :: proc "system" (ctrl_type: win32.DWORD) -> win32.BOOL {
	switch ctrl_type {
	case win32.CTRL_C_EVENT, win32.CTRL_CLOSE_EVENT:
		restore_windows()
	// NOTE(Franz): we could consume the event and prevent stopping but I dont think we actually want that
	// return true
	}
	return false
}

get_window_behaviour :: proc(window: Window) -> (behaviour: Window_Behaviour) {
	hwnd := window.hwnd
	ex_style := window.ex_style
	style := window.style
	title := window.title
	class := window.class

	if hwnd == nil {
		return
	}

	parent_window := Window {
		hwnd = win32.GetParent(hwnd),
	}
	if parent_window.hwnd != nil {
		collect_window_information(&parent_window, context.temp_allocator)
	}
	pok := parent_window.hwnd != nil && get_window_behaviour(parent_window) != .Ignore

	is_tool := ex_style & win32.WS_EX_TOOLWINDOW != 0
	is_app := ex_style & win32.WS_EX_APPWINDOW != 0
	no_activate := ex_style & win32.WS_EX_NOACTIVATE != 0
	is_resizeable := style & win32.WS_THICKFRAME != 0
	is_disabled := style & win32.WS_DISABLED != 0

	if len(title) == 0 || is_disabled || window.cloaked || window.hidden || no_activate {
		return .Ignore
	}

	if ((class == "Windows.UI.Core.CoreWindow") &&
		   ((title == "Windows Shell Experience Host") ||
				   (title == "Microsoft Text Input Application") ||
				   (title == "Action center") ||
				   (title == "New Notification") ||
				   (title == "Date and Time Information") ||
				   (title == "Volume Control") ||
				   (title == "Network Connections") ||
				   (title == "Cortana") ||
				   (title == "Start") ||
				   (title == "Windows Default ock Screen") ||
				   (title == "Windows Input Experience") ||
				   (title == "Search"))) {
		return .Ignore
	}

	if ((class == "ForegroundStaging") ||
		   (class == "ApplicationManager_DesktopShellWindow") ||
		   (class == "Static") ||
		   (class == "Scrollbar") ||
		   (class == "TaskManagerWindow") ||
		   (title == "Snipping Tool Overlay") ||
		   (class == "Progman")) {
		return .Ignore
	}

	if ((parent_window.hwnd == nil && win32.IsWindowVisible(hwnd)) || pok) {
		if title == "Fluent Search" {
			return .Floating
		}

		if ((!is_tool && parent_window.hwnd == nil) || (is_tool && pok)) {
			return is_resizeable ? .Tiling : .Floating
		}
		if (is_app && parent_window.hwnd != nil) {
			return is_resizeable ? .Tiling : .Floating
		}
	}

	return .Ignore
}

set_window_border_delta :: proc(window: ^Window) {
	DEFAULT_WINDOW_BORDER_DELTA :: Rect {
		left   = 7,
		right  = 7,
		bottom = 7,
	}

	window.border_delta = DEFAULT_WINDOW_BORDER_DELTA

	switch window.class {
	case "MozillaWindowClass":
		window.border_delta = {
			left   = 5,
			right  = 5,
			bottom = 5,
		}
		return
	case "Chrome_WidgetWin_1", "Chrome_WidgetWin_0":
		window.border_delta = {}
		return
	case "ApplicationFrameWindow":
		return
	}

	switch window.title {
	case "Fluent Search - Settings":
		window.border_delta = {
			top    = 19,
			left   = 19,
			right  = 19,
			bottom = 19,
		}
		return
	case "Fluent Search":
		window.border_delta = {
			top    = 19,
			left   = 19,
			right  = 19,
			bottom = 19,
		}
		return
	}

	if window.style == win32.WS_POPUPWINDOW {
		window.border_delta = {}
	}
}

get_window_title :: proc(
	hwnd: win32.HWND,
	allocator := context.allocator,
	location := #caller_location,
) -> string {
	text_len := win32.GetWindowTextLengthW(hwnd)
	if text_len == 0 {
		return {}
	}
	str_buf := make([^]u16, text_len + 1, context.temp_allocator)
	text_len = win32.GetWindowTextW(hwnd, str_buf, text_len + 1)

	str, _ := win32.utf16_to_utf8(str_buf[:text_len], allocator)
	return str
}

get_window_class :: proc(
	hwnd: win32.HWND,
	allocator := context.allocator,
	location := #caller_location,
) -> string {
	str_buf := make([dynamic]u16, 128, context.temp_allocator)
	str_len: i32 = 128
	for {
		len := win32.GetClassNameW(hwnd, raw_data(str_buf), str_len)
		if len < str_len - 1 {
			break
		} else {
			str_len *= 2
			reserve(&str_buf, int(str_len))
		}
	}

	str, _ := win32.utf16_to_utf8(str_buf[:str_len], allocator)
	return str
}

is_cloaked :: proc(hwnd: win32.HWND) -> bool {
	cloaked_val: bool
	h_res := win32.DwmGetWindowAttribute(
		hwnd,
		cast(u32)transmute(u64)win32.DWMWINDOWATTRIBUTE.DWMWA_CLOAKED,
		&cloaked_val,
		size_of(cloaked_val),
	)
	if h_res != 0 {
		return false
	}
	return cloaked_val
}

unhandled_exception_filter :: proc "system" (
	ExceptionInfo: ^win32.EXCEPTION_POINTERS,
) -> win32.LONG {
	restore_windows()
	return 0
}

collect_window_information :: proc(window: ^Window, allocator := window_text_allocator) {
	assert(window.hwnd != nil)

	window.title = get_window_title(window.hwnd, allocator)
	window.class = get_window_class(window.hwnd, allocator)
	window.style = cast(win32.DWORD)win32.GetWindowLongW(window.hwnd, win32.GWL_STYLE)
	window.ex_style = cast(win32.DWORD)win32.GetWindowLongW(window.hwnd, win32.GWL_EXSTYLE)

	set_window_border_delta(window)

	window.rect = get_window_rect(window.hwnd)
}

remove_window_title_bar :: proc(hwnd: win32.HWND) -> bool {
	if hwnd == nil {
		return false
	}

	preference := 2
	result := win32.DwmSetWindowAttribute(
		hwnd,
		auto_cast win32.DWMWINDOWATTRIBUTE.DWMWA_WINDOW_CORNER_PREFERENCE,
		&preference,
		size_of(preference),
	)

	(win32.SUCCEEDED(result) &&
		win32.SetWindowLongW(hwnd, win32.GWL_STYLE, transmute(i32)win32.WS_POPUPWINDOW) !=
			0) or_return

	(win32.PostMessageW(hwnd, win32.WM_PAINT, 0, 0)) or_return
	win32.ShowWindow(hwnd, win32.SW_HIDE)
	win32.ShowWindow(hwnd, win32.SW_SHOW)

	return true
}

set_window_pos :: proc "contextless" (hwnd: win32.HWND, rect: Rect, parent: win32.HWND) {
	win32.SetWindowPos(
		hwnd,
		parent,
		rect.left,
		rect.top,
		rect.right - rect.left,
		rect.bottom - rect.top,
		win32.SWP_FRAMECHANGED |
		win32.SWP_NOACTIVATE |
		win32.SWP_NOCOPYBITS |
		win32.SWP_NOSENDCHANGING |
		win32.SWP_ASYNCWINDOWPOS,
	)
}

create_logger :: proc() -> log.Logger {
	logger_proc :: proc(
		data: rawptr,
		level: log.Level,
		text: string,
		options: log.Options,
		location := #caller_location,
	) {
		data := cast(^Logger_Data)data

		data.file.procedure(data.file.data, level, text, options, location)
		data.console.procedure(data.console.data, level, text, options, location)

		if int(level) >= int(log.Level.Warning) {
			backing: [1024]byte
			buf := strings.builder_from_bytes(backing[:])

			log.do_level_header(options, &buf, level)

			sync.guard(&error_mutex)

			if log.Full_Timestamp_Opts & options != nil {
				fmt.sbprint(&buf, "[")
				t := time.now()
				y, m, d := time.date(t)
				h, min, s := time.clock(t)
				if .Date in options {fmt.sbprintf(&buf, "%d-%02d-%02d ", y, m, d)}
				if .Time in options {fmt.sbprintf(&buf, "%02d:%02d:%02d", h, min, s)}
				fmt.sbprint(&buf, "] ")

				last_error_time = t
			}

			log.do_location_header(options, &buf, location)

			if .Thread_Id in options {
				fmt.sbprintf(&buf, "[{}] ", os.current_thread_id())
			}
			delete(last_error_string, window_text_allocator)
			last_error_string = fmt.aprintf(
				"%s%s",
				strings.to_string(buf),
				text,
				allocator = window_text_allocator,
			)
		}
	}

	Logger_Data :: struct {
		file, console: log.Logger,
	}

	context.allocator = permanent_allocator

	data := new(Logger_Data)

	log_file, err := os.open("log.txt", os.O_RDWR | os.O_TRUNC | os.O_CREATE)
	if err != os.ERROR_NONE {
		fmt.panicf("Failed to open log file: %i", err)
	}

	data.file = log.create_file_logger(log_file, LOGGER_LEVEL)
	data.console = log.create_console_logger(LOGGER_LEVEL)

	return {
		procedure = logger_proc,
		options = ({.Level, .Short_File_Path, .Line, .Procedure} | log.Full_Timestamp_Opts),
		data = data,
		lowest_level = LOGGER_LEVEL,
	}
}

