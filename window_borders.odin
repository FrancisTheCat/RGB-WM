package wm

import "base:intrinsics"

import "core:thread"
import "core:time"

import gl "vendor:OpenGL"
import "vendor:glfw"

import win32 "core:sys/windows"

selected_window_border: Window_Border

Window_Border :: struct {
	hwnd:  win32.HWND,
	color: win32.COLORREF,
}

@(thread_local, private = "file")
window_width, window_height: i32
@(thread_local, private = "file")
border_window_handle: glfw.WindowHandle

create_window_border :: proc(id: int) -> Window_Border {
	hwnd: win32.HWND

	t := thread.create_and_start_with_poly_data(
	&hwnd,
	proc(ref_hwnd: ^win32.HWND) {
		draw_border :: proc "contextless" () {
			gl.Viewport(0, 0, window_width, window_height)
			gl.Clear(gl.COLOR_BUFFER_BIT)
			gl.Uniform1f(
				get_uniform(.Ui, "ux"),
				1 -
				f32(config.border.inset + config.border.width + config.border.radius) /
					f32(window_width),
			)
			gl.Uniform1f(
				get_uniform(.Ui, "uy"),
				1 -
				f32(config.border.inset + config.border.width + config.border.radius) /
					f32(window_height),
			)
			gl.Uniform2f(get_uniform(.Ui, "resolution"), f32(window_width), f32(window_height))
			gl.Uniform2f(get_uniform(.Ui, "screen_resolution"), f32(monitor_resolution.x), f32(monitor_resolution.y))
			if config.border.chroma.enabled {
				gl.Uniform1f(
					get_uniform(.Ui, "chroma_time"),
					f32(time.duration_seconds(time.since(start_time))) *
					config.border.chroma.speed,
				)
				x, y := glfw.GetWindowPos(border_window_handle)
				gl.Uniform2f(get_uniform(.Ui, "chroma_offset"), f32(x), f32(y))
			}
			gl.DrawElements(gl.TRIANGLES, 8 * 3, gl.UNSIGNED_INT, nil)
			glfw.SwapBuffers(border_window_handle)
		}

		size_callback :: proc "c" (window: glfw.WindowHandle, width, height: i32) {
			window_width, window_height = width, height
			draw_border()
		}

		glfw.Init()
		glfw.WindowHint(glfw.TRANSPARENT_FRAMEBUFFER, true)
		glfw.WindowHint(glfw.SAMPLES, 16)
		glfw.WindowHint(glfw.DECORATED, false)
		border_window_handle = glfw.CreateWindow(
			1000,
			400,
			"opengl window border window",
			nil,
			nil,
		)

		hwnd := glfw.GetWin32Window(border_window_handle)
		ex_style := i32(win32.WS_EX_NOACTIVATE | win32.WS_EX_TOOLWINDOW)
		win32.SetWindowLongW(hwnd, win32.GWL_EXSTYLE, ex_style)

		glfw.MakeContextCurrent(border_window_handle)

		gl.load_up_to(4, 5, glfw.gl_set_proc_address)

		// NOTE(Franz): a value bigger than 1.5 signals to the vertex shader that it should replace
		// the vertex position with a uniform set to the required inset for the window border
		// allowing us to only run the fragment shader where the border is
		
				// odinfmt: disable
			vertices := [10][2]f32 {
				{-1,  1},
				{-1, -1},
				{-2, -2},
				{ 2, -1},
				{ 2, -2},
				{ 1, -1},
				{ 2,  2},
				{ 1,  1},
				{-2,  1},
				{-2,  2},
			}
		
			indices := [8 * 3]i32 {
				0, 1, 2,
				1, 2, 3,
				2, 3, 4,
				3, 5, 6,
				5, 6, 7,
				6, 7, 8,
				6, 8, 9,
				0, 2, 8,
			}
			// odinfmt: enable

		VAO, VBO, EBO: u32
		gl.GenVertexArrays(1, &VAO)
		gl.GenBuffers(1, &VBO)
		gl.GenBuffers(1, &EBO)
		gl.BindVertexArray(VAO)
		gl.BindBuffer(gl.ARRAY_BUFFER, VBO)
		gl.BufferData(gl.ARRAY_BUFFER, size_of(vertices), &vertices, gl.STATIC_DRAW)
		gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, EBO)
		gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, size_of(indices), &indices, gl.STATIC_DRAW)
		gl.VertexAttribPointer(0, 2, gl.FLOAT, gl.FALSE, 2 * size_of(f32), 0)
		gl.EnableVertexAttribArray(0)

		gl.Enable(gl.BLEND)
		gl.BlendFunc(gl.ONE, gl.ONE_MINUS_SRC_ALPHA)
		gl.BlendEquation(gl.FUNC_ADD)

		load_program(.Ui, "shaders/border/vertex.vert", "shaders/border/fragment.frag")

		use_program(.Ui)

		gl.Uniform1f(get_uniform(.Ui, "ux"), 0.99)
		gl.Uniform1f(get_uniform(.Ui, "uy"), 0.99)
		gl.Uniform4f(get_uniform(.Ui, "border_color"), expand_values(config.border.color))
		gl.Uniform1f(get_uniform(.Ui, "width"), f32(config.border.width + config.border.inset))
		gl.Uniform1f(get_uniform(.Ui, "radius"), f32(config.border.radius + config.border.width))

		gl.Uniform1i(get_uniform(.Ui, "chroma"), config.border.chroma.enabled ? 1 : 0)

		glfw.SetWindowSizeCallback(border_window_handle, size_callback)

		intrinsics.atomic_exchange(ref_hwnd, hwnd)

		for !glfw.WindowShouldClose(border_window_handle) {
			draw_border()

			if config.border.chroma.enabled && config.border.chroma.fps != 0 {
				glfw.WaitEventsTimeout(min(1.0 / f64(config.border.chroma.fps), 1))
			} else {
				glfw.WaitEventsTimeout(1)
			}
		}
	},
	)
	free(t)

	for intrinsics.atomic_load(&hwnd) == nil {
		intrinsics.cpu_relax()
	}

	win32.ShowWindow(hwnd, win32.SW_SHOW)

	return {hwnd = hwnd}
}

update_window_border :: proc(
	window_border: Window_Border,
	rect: Rect,
	parent: win32.HWND,
	location := #caller_location,
) {
	real_rect: Rect
	win32.GetWindowRect(window_border.hwnd, &real_rect)
	if rect != real_rect || true {
		win32.SetWindowPos(
			window_border.hwnd,
			parent,
			rect.left,
			rect.top,
			rect.right - rect.left,
			rect.bottom - rect.top,
			win32.SWP_SHOWWINDOW | win32.SWP_NOACTIVATE,
		)
	}
}

hide_window_border :: proc(window_border: Window_Border) {
	win32.SetWindowPos(window_border.hwnd, win32.HWND_BOTTOM, 0, 0, 0, 0, win32.SWP_HIDEWINDOW)
}

hook_proc :: proc "system" (
	hWinEventHook: win32.HWINEVENTHOOK,
	event: win32.DWORD,
	hwnd: win32.HWND,
	idObject, idChild: win32.LONG,
	idEventThread, dwmsEventTime: win32.DWORD,
) {
	if !(idChild == 0 && idObject == 0 && hwnd != nil) {
		return
	}
	context = {}
	append(&message_queue, Window_Message{hwnd = hwnd, event = Window_Event(event)})
}

