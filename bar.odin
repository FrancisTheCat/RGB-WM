package wm

import "base:intrinsics"
import "base:runtime"

import "core:fmt"
import "core:log"
import "core:reflect"
import "core:strings"
import "core:sync"
import "core:thread"
import "core:time"

import gl "vendor:OpenGL"
import "vendor:glfw"

import win32 "core:sys/windows"

bar_hwnd: win32.HWND
@(private = "file")
bar_window_handle: glfw.WindowHandle

create_bar_window :: proc() {
	win32.SetLastError(0)

	t := thread.create_and_start(proc() {
		context.logger = log.create_console_logger(LOGGER_LEVEL)

		glfw.Init()
		glfw.WindowHint(glfw.TRANSPARENT_FRAMEBUFFER, true)
		glfw.WindowHint(glfw.DECORATED, false)
		bar_window_handle = glfw.CreateWindow(
			1920 - config.bar.margin.x * 2,
			config.bar.height,
			"Bar Window",
			nil,
			nil,
		)

		hwnd := glfw.GetWin32Window(bar_window_handle)
		ex_style := i32(win32.WS_EX_NOACTIVATE | win32.WS_EX_TOOLWINDOW)
		win32.SetWindowLongW(hwnd, win32.GWL_EXSTYLE, ex_style)
		glfw.MakeContextCurrent(bar_window_handle)

		glfw.SetWindowPos(bar_window_handle, expand_values(config.bar.margin))

		gl.load_up_to(4, 5, glfw.gl_set_proc_address)

		vertices := [?]f32{1, 1, 1, 1, 1, -1, 1, 0, -1, -1, 0, 0, -1, 1, 0, 1}
		indices := [?]i32{0, 1, 3, 1, 2, 3}

		VAO, VBO, EBO: u32
		gl.GenVertexArrays(1, &VAO)
		gl.GenBuffers(1, &VBO)
		gl.GenBuffers(1, &EBO)
		gl.BindVertexArray(VAO)
		gl.BindBuffer(gl.ARRAY_BUFFER, VBO)
		gl.BufferData(gl.ARRAY_BUFFER, size_of(vertices), &vertices, gl.STATIC_DRAW)
		gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, EBO)
		gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, size_of(indices), &indices, gl.STATIC_DRAW)
		gl.VertexAttribPointer(0, 2, gl.FLOAT, gl.FALSE, 4 * size_of(f32), 0)
		gl.VertexAttribPointer(1, 2, gl.FLOAT, gl.FALSE, 4 * size_of(f32), size_of(f32) * 2)
		gl.EnableVertexAttribArray(0)
		gl.EnableVertexAttribArray(1)

		bar_vao = VAO

		gl.Enable(gl.BLEND)
		gl.BlendFunc(gl.ONE, gl.ONE_MINUS_SRC_ALPHA)
		gl.BlendEquation(gl.FUNC_ADD)

		fonts_init()

		load_program(.Ui, "shaders/border/vertex.vert", "shaders/border/fragment.frag")
		load_program(.Font, "shaders/font/vertex.glsl", "shaders/font/fragment.glsl")

		use_program(.Ui)
		gl.Uniform1i(get_uniform(.Ui, "chroma"), config.bar.border.chroma.enabled ? 1 : 0)
		gl.Uniform4f(get_uniform(.Ui, "border_color"), expand_values(config.bar.border.color))
		gl.Uniform4f(
			get_uniform(.Ui, "background_color"),
			expand_values(config.bar.background_color),
		)
		gl.Uniform1f(get_uniform(.Ui, "width"), f32(config.bar.border.width))
		gl.Uniform1f(
			get_uniform(.Ui, "radius"),
			f32(config.bar.border.width + config.bar.border.radius),
		)

		glfw.SetWindowRefreshCallback(bar_window_handle, bar_refresh_proc)

		intrinsics.atomic_exchange(&bar_hwnd, hwnd)

		t: runtime.Default_Temp_Allocator
		runtime.default_temp_allocator_init(&t, runtime.DEFAULT_TEMP_ALLOCATOR_BACKING_SIZE)
		bar_temp_allocator = runtime.default_temp_allocator(&t)

		for !glfw.WindowShouldClose(bar_window_handle) {
			bar_refresh_proc(bar_window_handle)

			if config.bar.border.chroma.enabled && config.bar.border.chroma.fps != 0 {
				glfw.WaitEventsTimeout(min(1.0 / f64(config.bar.border.chroma.fps), 1))
			} else {
				glfw.WaitEventsTimeout(1)
			}
		}
	})

	free(t)

	for intrinsics.atomic_load(&bar_hwnd) == nil {
		intrinsics.cpu_relax()
	}

	win32.ShowWindow(bar_hwnd, win32.SW_SHOW)
}

@(private = "file")
bar_vao: u32

@(private = "file")
bar_refresh_proc :: proc "c" (window: glfw.WindowHandle) {
	sync.guard(&bar_state_mutex)
	width, height := glfw.GetWindowSize(window)
	gl.Viewport(0, 0, width, height)
	gl.Clear(gl.COLOR_BUFFER_BIT)

	use_program(.Ui)

	if config.bar.border.chroma.enabled {
		gl.Uniform1f(
			get_uniform(.Ui, "chroma_time"),
			f32(time.duration_seconds(time.since(start_time))) * config.bar.border.chroma.speed,
		)
		gl.Uniform2f(
			get_uniform(.Ui, "chroma_offset"),
			f32(config.bar.margin.x),
			f32(config.bar.margin.y),
		)
	}
	gl.Uniform2f(get_uniform(.Ui, "resolution"), f32(width), f32(height))
	gl.BindVertexArray(bar_vao)
	gl.DrawElements(gl.TRIANGLES, 6, gl.UNSIGNED_INT, nil)

	x := config.bar.text_padding + config.bar.border.width

	context = {}
	if config.bar.workspaces.enabled {
		for workspace, i in bar_state.workspaces {
			color := Text_Color.Workspace_Inactive
			if i == bar_state.focused_workspace {
				color = .Workspace_Focused
			} else if workspace.active {
				color = .Workspace_Active
			}
			if color != .Workspace_Inactive || config.bar.workspaces.show_inactive {
				x +=
					draw_string_ex(
						fmt.aprint(i + 1, allocator = bar_temp_allocator),
						{i32(x), i32(config.bar.height) / 2},
						color = color,
						shadow = config.bar.text_shadow,
						align = {.Left, .Center},
					) +
					config.bar.text_padding
			}
		}
	}

	if config.bar.layout.enabled {
		layout_str :=
			reflect.enum_name_from_value(
				bar_state.workspaces[bar_state.focused_workspace].layout,
			) or_else log.panic("Failed to convert layout enum to string")
		x +=
			draw_string_ex(
				layout_str,
				{x, config.bar.height / 2},
				color = .Layout,
				shadow = config.bar.text_shadow,
				align = {.Left, .Center},
			) +
			config.bar.text_padding

		flip_str: string

		switch ([2]bool {
				bar_state.workspaces[bar_state.focused_workspace].v_flip,
				bar_state.workspaces[bar_state.focused_workspace].h_flip,
			}) {
		case {true, false}:
			flip_str = "Flip(V)"
		case {true, true}:
			flip_str = "Flip(V, H)"
		case {false, true}:
			flip_str = "Flip(H)"
		case {false, false}:
		}

		if flip_str != "" {
			draw_string_ex(
				flip_str,
				{x, config.bar.height / 2},
				color = .Layout,
				shadow = config.bar.text_shadow,
				align = {.Left, .Center},
			)
		}
	}

	BAR_WIDTH := width
	{
		sync.guard(&error_mutex)

		ERROR_DISPLAY_TIME :: time.Second * 5
		if time.since(last_error_time) < ERROR_DISPLAY_TIME {
			draw_string_ex(
				last_error_string,
				{BAR_WIDTH / 2, config.bar.height / 2},
				color = .Error,
				shadow = config.bar.text_shadow,
				align = {.Center, .Center},
			)
		} else if config.bar.title.enabled {
			draw_string_ex(
				fmt.aprintf(
					config.bar.title.format_string,
					bar_state.focused_title,
					allocator = bar_temp_allocator,
				),
				{BAR_WIDTH / 2, config.bar.height / 2},
				color = .Title,
				shadow = config.bar.text_shadow,
				align = {.Center, .Center},
			)
		}
	}

	clock_x: i32
	if config.bar.clock.enabled {
		t := time.time_add(time.now(), time.Hour * 2)
		clock_x = draw_string_ex(
			fmt.aprintf(
				config.bar.clock.format_string,
				time.date(t),
				time.clock(t),
				allocator = bar_temp_allocator,
			),
			{BAR_WIDTH - config.bar.text_padding - config.bar.border.width, config.bar.height / 2},
			color = .Clock,
			shadow = config.bar.text_shadow,
			align = {.Right, .Center},
		) + config.bar.text_padding
	}

	if config.bar.battery.enabled {
		power_status: win32.SYSTEM_POWER_STATUS
		if win32.GetSystemPowerStatus(&power_status) {
			color := Text_Color.Battery
			if .Charging in power_status.BatteryFlag {
				color = .Battery_Charging
			} else if power_status.SystemStatusFlag == 1 {
				color = .Battery_Saver
			}

			draw_string_ex(
				fmt.aprintf(
					"Battery: %d%%",
					power_status.BatteryLifePercent,
					allocator = bar_temp_allocator,
				),
				{
					BAR_WIDTH - config.bar.text_padding - clock_x - config.bar.border.width,
					config.bar.height / 2,
				},
				color = color,
				shadow = config.bar.text_shadow,
				align = {.Right, .Center},
			)
		}
	}

	render_strings()
	glfw.SwapBuffers(window)

	free_all(bar_temp_allocator)
}

@(private = "file")
bar_temp_allocator: runtime.Allocator

@(private = "file")
Workspace_State :: struct {
	layout:         Layout,
	v_flip, h_flip: bool,
	active:         bool,
}

@(private = "file")
Bar_State :: struct {
	workspaces:        [10]Workspace_State,
	focused_workspace: int,
	focused_title:     string,
	last_error:        string,
	last_error_time:   time.Time,
}

@(private = "file")
bar_state: Bar_State

@(private = "file")
bar_state_mutex: sync.Mutex

update_bar_state :: proc() {
	sync.guard(&bar_state_mutex)
	for w, i in workspaces {
		bar_state.workspaces[i].active = !(len(w.windows) == 0 && len(w.floating_windows) == 0)
		bar_state.workspaces[i].layout = w.layout
		bar_state.workspaces[i].v_flip = w.v_flip
		bar_state.workspaces[i].h_flip = w.h_flip
	}
	bar_state.focused_workspace = focused_workspace
	w := workspaces[focused_workspace]
	delete(bar_state.focused_title)
	if window := get_focused_window(w); window != nil {
		if i32(len(window.title)) < config.bar.title.max_length ||
		   config.bar.title.max_length == 0 {
			bar_state.focused_title = strings.clone(window.title)
		} else {
			bar_state.focused_title = strings.concatenate(
				{window.title[:config.bar.title.max_length], "..."},
			)
		}
	} else {
		bar_state.focused_title = strings.clone("Desktop")
	}

	win32.PostMessageW(bar_hwnd, win32.WM_PAINT, 0, 0)
}

update_bar_position :: proc() {
	glfw.SetWindowPos(bar_window_handle, expand_values(config.bar.margin))
	glfw.SetWindowSize(bar_window_handle, 1920 - config.bar.margin.x * 2, config.bar.height)
}

