package wm

import "core:fmt"

import gl "vendor:OpenGL"

get_uniform :: proc "contextless" (program: Program_Key, uniform: string) -> i32 {
	return programs[program].uniforms[uniform].location
}

@(thread_local)
programs: [Program_Key]Program

Program_Key :: enum {
	Ui,
	Font,
}

@(private = "file")
Program :: struct {
	uniforms:      gl.Uniforms,
	path_vertex:   string,
	path_fragment: string,
	path_geometry: Maybe(string),
	handle:        u32,
}

use_program :: proc "contextless" (program: Program_Key) {
	gl.UseProgram(programs[program].handle)
}

load_program :: proc(
	program: Program_Key,
	$vertex_path, $fragment_path: string,
	location := #caller_location,
) -> bool {
	p := &programs[program]

	p.handle =
		gl.load_shaders_source(#load(vertex_path), #load(fragment_path)) or_else fmt.panicf(
			"Failed to load %v program: %v, %v",
			program,
			gl.get_last_error_message(),
			location,
		)
	p.uniforms = gl.get_uniforms_from_program(p.handle)
	return true
}

