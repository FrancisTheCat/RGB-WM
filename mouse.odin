package wm

import win32 "core:sys/windows"

@(private = "file")
window_drag_offset: [2]i32
dragged_window: int

dragging: bool
sizing: bool

get_window_under_cursor :: proc "contextless" (pt: win32.POINT) -> int {
	for window, i in workspaces[focused_workspace].floating_windows {
		if window.rect.left > pt.x || window.rect.right < pt.x {
			continue
		}
		if window.rect.top > pt.y || window.rect.bottom < pt.y {
			continue
		}
		return i
	}
	return -1
}

end_window_drag :: proc "contextless" () {
	if len(workspaces[focused_workspace].floating_windows) > dragged_window {
		window := &workspaces[focused_workspace].floating_windows[dragged_window]
		window.rect = get_window_rect(window.hwnd)
	}
	workspaces[focused_workspace].dirty = true
	dragging = false
}

end_window_resize :: proc "contextless" () {
	if len(workspaces[focused_workspace].floating_windows) > dragged_window {
		window := &workspaces[focused_workspace].floating_windows[dragged_window]
		window.rect = get_window_rect(window.hwnd)
	}
	workspaces[focused_workspace].dirty = true
	sizing = false
}

mouse_hook_proc :: proc "system" (
	n_code: i32,
	w_param: win32.WPARAM,
	l_param: win32.LPARAM,
) -> win32.LRESULT {
	if n_code != 0 {
		return win32.CallNextHookEx(nil, n_code, w_param, l_param)
	}

	if len(workspaces[focused_workspace].floating_windows) <= dragged_window {
		return win32.CallNextHookEx(nil, n_code, w_param, l_param)
	}

	input := transmute(^win32.MSLLHOOKSTRUCT)l_param
	switch w_param {
	case win32.WM_MBUTTONDOWN:
		if is_key_pressed(.Menu) {
			window_index := get_window_under_cursor(input.pt)

			if window_index == -1 {
				break
			}
			workspaces[focused_workspace].focused_window = {
				index    = window_index,
				floating = true,
			}
			window := &workspaces[focused_workspace].floating_windows[window_index]
			center_window(window)
			workspaces[focused_workspace].dirty = true
			return -1
		}
	case win32.WM_LBUTTONDOWN:
		if is_key_pressed(.Menu) {
			window_index := get_window_under_cursor(input.pt)

			if window_index == -1 {
				break
			}
			workspaces[focused_workspace].focused_window = {
				index    = window_index,
				floating = true,
			}
			window := workspaces[focused_workspace].floating_windows[window_index]
			dragging = true
			dragged_window = window_index
			window_drag_offset = {window.rect.left, window.rect.top} - transmute([2]i32)input.pt

			return -1
		}
	case win32.WM_LBUTTONUP:
		if dragging {
			end_window_drag()
			return -1
		}
	case win32.WM_RBUTTONDOWN:
		if is_key_pressed(.Menu) {
			window_index := get_window_under_cursor(input.pt)

			if window_index == -1 {
				break
			}
			workspaces[focused_workspace].focused_window = {
				index    = window_index,
				floating = true,
			}
			sizing = true
			dragged_window = window_index
			window_drag_offset = transmute([2]i32)input.pt

			return -1
		}
	case win32.WM_RBUTTONUP:
		if sizing {
			end_window_resize()
			return -1
		}
	case win32.WM_MOUSEMOVE:
		if dragging {
			win32.SetCursorPos(input.pt.x, input.pt.y)

			window := workspaces[focused_workspace].floating_windows[dragged_window]
			win32.MoveWindow(
				window.hwnd,
				window_drag_offset.x + input.pt.x,
				window_drag_offset.y + input.pt.y,
				window.rect.right - window.rect.left,
				window.rect.bottom - window.rect.top,
				false,
			)

			return -1
		} else if sizing {
			win32.SetCursorPos(input.pt.x, input.pt.y)

			window := workspaces[focused_workspace].floating_windows[dragged_window]
			win32.MoveWindow(
				window.hwnd,
				window.rect.left,
				window.rect.top,
				window.rect.right - window.rect.left + input.pt.x - window_drag_offset.x,
				window.rect.bottom - window.rect.top + input.pt.y - window_drag_offset.y,
				false,
			)
			return -1
		}
	}

	return win32.CallNextHookEx(nil, n_code, w_param, l_param)
}

