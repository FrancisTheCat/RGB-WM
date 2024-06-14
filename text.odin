package wm

import "core:fmt"
import "core:log"
import glm "core:math/linalg/glsl"
import "core:os"
import "core:strconv"

import gl "vendor:OpenGL"
import "vendor:stb/image"
import "vendor:stb/truetype"

fonts_init :: proc() {
	text_rendering_context_init()

	for &size, size_enum in FONT_SIZES {
		size = i32(
			strconv.parse_int(fmt.tprint(size_enum)[3:]) or_else log.panic(
				"Failed to parse font size enum name",
			),
		)
	}

	FONT_PATH :: "/Windows/Fonts/CascadiaCode.ttf"
	data, data_ok := os.read_entire_file(FONT_PATH)
	defer delete(data)
	log.assertf(data_ok, "failed to read font data from %s", FONT_PATH)

	for &font, size in fonts {
		MIN_ATLAS_RESOLUTION :: 64

		result: i32
		out_data: []byte

		for result <= 0 {
			font.atlas_resolution += MIN_ATLAS_RESOLUTION
			out_data = make(
				[]byte,
				font.atlas_resolution * font.atlas_resolution,
				context.temp_allocator,
			)

			result = truetype.BakeFontBitmap(
				raw_data(data),
				0,
				cast(f32)font_size_px(size) * 2,
				raw_data(out_data),
				font.atlas_resolution,
				font.atlas_resolution,
				0,
				256,
				&font.characters[0],
			)
		}

		// NOTE(Franz): This looks better imo, you might want to adjust this based on your font and font size
		for &pixel in out_data {
			pixel = u8(glm.pow(f32(pixel) / 255.0, 0.8) * 255.0)
		}

		font.atlas = load_texture_from_buffer(
			out_data[:],
			int(font.atlas_resolution),
			int(font.atlas_resolution),
			1,
		)

		gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST)
		gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST)
		gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_BORDER)
		gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_BORDER)

		result = image.write_jpg(
			fmt.ctprintf("font/atlas%v.jpg", font_size_px(size)),
			font.atlas_resolution,
			font.atlas_resolution,
			1,
			raw_data(out_data),
			90,
		)
	}
}

DEFAULT_FONT_SIZE :: Font_Size.Px_9

FONT_SIZES: [Font_Size]i32

Font_Size :: enum {
	Px_9,
}

font_size_px :: proc "contextless" (font_size: Font_Size) -> i32 {
	return FONT_SIZES[font_size]
}

Text_Color :: enum {
	Black = 0,
	Error,
	Workspace_Focused,
	Workspace_Active,
	Workspace_Inactive,
	Layout,
	Title,
	Battery,
	Battery_Charging,
	Battery_Saver,
	Clock,
}

@(private = "file", thread_local)
text_rendering_context: Text_Rendering_Context

@(private = "file")
Text_Rendering_Context :: struct {
	draw_calls:    [Font_Size][Text_Color][dynamic]String_Drawcall,
	vertex_buffer: [dynamic]Text_Vertex,
	vao, vbo:      u32,
}

@(private = "file")
text_rendering_context_init :: proc() {
	for &arrs in text_rendering_context.draw_calls {
		for &arr in arrs {
			arr = make([dynamic]String_Drawcall)
		}
	}
	text_rendering_context.vertex_buffer = make([dynamic]Text_Vertex)

	gl.GenVertexArrays(1, &text_rendering_context.vao)
	gl.BindVertexArray(text_rendering_context.vao)

	gl.GenBuffers(1, &text_rendering_context.vbo)
	gl.BindBuffer(gl.ARRAY_BUFFER, text_rendering_context.vbo)
	defer gl.BindBuffer(gl.ARRAY_BUFFER, 0)

	gl.VertexAttribPointer(
		0,
		2,
		gl.FLOAT,
		gl.FALSE,
		size_of(Text_Vertex),
		offset_of(Text_Vertex, position),
	)
	gl.EnableVertexAttribArray(0)

	gl.VertexAttribPointer(
		1,
		2,
		gl.FLOAT,
		gl.FALSE,
		size_of(Text_Vertex),
		offset_of(Text_Vertex, texture),
	)
	gl.EnableVertexAttribArray(1)
}

@(private = "file")
text_rendering_context_uninit :: proc() {
	for arrs in text_rendering_context.draw_calls {
		for arr in arrs {
			delete(arr)
		}
	}
	delete(text_rendering_context.vertex_buffer)

	gl.DeleteVertexArrays(1, &text_rendering_context.vao)
	gl.DeleteBuffers(1, &text_rendering_context.vbo)
}

@(private = "file")
String_Drawcall :: struct {
	text:     string,
	position: glm.ivec2,
}

Text_Align :: struct {
	horizontal: Text_Align_H,
	vertical:   Text_Align_V,
}

Text_Align_H :: enum {
	Center = 0,
	Left,
	Right,
}

Text_Align_V :: enum {
	Center = 0,
	Top,
	Bottom,
}

draw_string_ex :: proc "contextless" (
	str: string,
	position: glm.ivec2,
	font_size: Font_Size = DEFAULT_FONT_SIZE,
	color: Text_Color,
	align: Text_Align = {.Left, .Top},
	shadow: bool = false,
) -> i32 {
	position := position
	position.y += 1
	width := cast(i32)measure_text(str, font_size)

	switch align.vertical {
	case .Center:
		position.y += i32(font_size_px(font_size)) / 2
	case .Top:
		position.y += i32(font_size_px(font_size))
	case .Bottom:
	}

	switch align.horizontal {
	case .Center:
		position.x -= width / 2
	case .Right:
		position.x -= width
	case .Left:
	}

	SHADOW_OFFSET :: glm.ivec2{1, 1}
	if shadow {
		draw_string(str, position + SHADOW_OFFSET, font_size, TEXT_SHADOW_COLOR)
	}

	draw_string(str, position, font_size, color)

	return width
}

draw_string :: proc "contextless" (
	str: string,
	position: glm.ivec2,
	font_size: Font_Size = DEFAULT_FONT_SIZE,
	color: Text_Color,
) {
	context = {}
	append(
		&text_rendering_context.draw_calls[font_size][color],
		String_Drawcall{text = str, position = position},
	)
}

@(private = "file")
TEXT_SHADOW_COLOR :: Text_Color.Black

get_text_color :: proc "contextless" (color: Text_Color) -> ColorRGBA {
	switch color {
	case .Black:
		return {0, 0, 0, 1}
	case .Error:
		return {1, 0, 0, 1}
	case .Workspace_Focused:
		return config.bar.workspaces.focus_color
	case .Workspace_Active:
		return config.bar.workspaces.active_color
	case .Workspace_Inactive:
		return config.bar.workspaces.inactive_color
	case .Layout:
		return config.bar.layout.color
	case .Title:
		return config.bar.title.color
	case .Battery:
		return config.bar.battery.color
	case .Battery_Charging:
		return config.bar.battery.charging_color
	case .Battery_Saver:
		return config.bar.battery.battery_saver_color
	case .Clock:
		return config.bar.clock.color
	}

	return {1, 1, 0, 1}
}

render_strings :: proc "contextless" () {
	use_program(.Font)
	gl.Disable(gl.CULL_FACE)
	gl.BindBuffer(gl.ARRAY_BUFFER, text_rendering_context.vbo)
	gl.BindVertexArray(text_rendering_context.vao)
	gl.ActiveTexture(gl.TEXTURE0)

	for &draw_calls, font_size in text_rendering_context.draw_calls {
		gl.BindTexture(gl.TEXTURE_2D, fonts[font_size].atlas)
		for &draw_calls, font_color in draw_calls {
			(len(draw_calls) != 0) or_continue
			render_string_drawcalls(
				font_size,
				get_text_color(font_color),
				draw_calls[:],
				&text_rendering_context.vertex_buffer,
			)
			clear(&draw_calls)
		}
	}
}

@(private = "file")
render_string_drawcalls :: proc "contextless" (
	font_size: Font_Size,
	font_color: ColorRGBA,
	draw_calls: []String_Drawcall,
	vertex_buffer: ^[dynamic]Text_Vertex,
) {
	context = {}

	clear(vertex_buffer)

	// TODO(Franz): make this better
	window_dimensions: glm.vec2 = {f32(1920 - 2 * config.bar.margin.x), cast(f32)config.bar.height}

	font := fonts[font_size]

	for draw_call in draw_calls {
		position := glm.vec2{cast(f32)draw_call.position.x, cast(f32)draw_call.position.y}
		for char in draw_call.text {
			char := char
			if char >= len(font.characters) {
				char = '?'
			}
			q: truetype.aligned_quad
			truetype.GetBakedQuad(
				&font.characters[0],
				font.atlas_resolution,
				font.atlas_resolution,
				i32(char),
				&position.x,
				&position.y,
				&q,
				true,
			)

			append(
				vertex_buffer,
				Text_Vertex {
					position =  {
						2 * q.x1 / window_dimensions.x - 1,
						2 * q.y0 / window_dimensions.y - 1,
					},
					texture = {q.s1, q.t0},
				},
				Text_Vertex {
					position =  {
						2 * q.x1 / window_dimensions.x - 1,
						2 * q.y1 / window_dimensions.y - 1,
					},
					texture = {q.s1, q.t1},
				},
				Text_Vertex {
					position =  {
						2 * q.x0 / window_dimensions.x - 1,
						2 * q.y0 / window_dimensions.y - 1,
					},
					texture = {q.s0, q.t0},
				},
				Text_Vertex {
					position =  {
						2 * q.x1 / window_dimensions.x - 1,
						2 * q.y1 / window_dimensions.y - 1,
					},
					texture = {q.s1, q.t1},
				},
				Text_Vertex {
					position =  {
						2 * q.x0 / window_dimensions.x - 1,
						2 * q.y1 / window_dimensions.y - 1,
					},
					texture = {q.s0, q.t1},
				},
				Text_Vertex {
					position =  {
						2 * q.x0 / window_dimensions.x - 1,
						2 * q.y0 / window_dimensions.y - 1,
					},
					texture = {q.s0, q.t0},
				},
			)
		}
	}

	gl.Uniform4f(
		get_uniform(.Font, "color"),
		font_color.r,
		font_color.g,
		font_color.b,
		font_color.a,
	)

	gl.BufferData(
		gl.ARRAY_BUFFER,
		len(vertex_buffer) * size_of(Text_Vertex),
		raw_data(vertex_buffer^),
		gl.DYNAMIC_DRAW,
	)

	gl.DrawArrays(gl.TRIANGLES, 0, auto_cast len(vertex_buffer))
}

fonts_uninit :: proc() {
	text_rendering_context_uninit()
}

@(private = "file")
Text_Vertex :: struct {
	position: glm.vec2,
	texture:  glm.vec2,
}

Font :: struct {
	atlas_resolution: i32,
	atlas:            u32,
	characters:       [256]truetype.bakedchar,
}

fonts: [Font_Size]Font

measure_text :: proc "contextless" (
	text: string,
	font_size: Font_Size = DEFAULT_FONT_SIZE,
) -> (
	size: f32,
) {
	font := fonts[font_size]
	for char in text {
		if int(char) >= len(font.characters) {
			size += font.characters['^'].xadvance
			continue
		}
		size += font.characters[char].xadvance
	}
	return
}

load_texture_from_buffer :: proc(buf: []byte, width, height, channels: int) -> u32 {
	texture: u32
	gl.GenTextures(1, &texture)
	gl.BindTexture(gl.TEXTURE_2D, texture)
	gl.TexImage2D(
		gl.TEXTURE_2D,
		0,
		channels == 4 ? gl.RGBA : gl.RED,
		i32(width),
		i32(height),
		0,
		channels == 4 ? gl.RGBA : gl.RED,
		gl.UNSIGNED_BYTE,
		raw_data(buf),
	)
	gl.GenerateMipmap(gl.TEXTURE_2D)
	return texture
}

Color :: ColorRGB
ColorRGB :: [3]f32
ColorRGBA :: [4]f32

