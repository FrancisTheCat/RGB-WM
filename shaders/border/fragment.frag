#version 450

in vec2 v_position;

out vec4 frag_color;

uniform vec4  border_color;
uniform vec4  background_color;
uniform float width;
uniform float radius;

uniform bool  chroma;
uniform float chroma_time;
uniform vec2  chroma_offset;

uniform float aspect;
uniform vec2  resolution;
uniform vec2  screen_resolution;

uniform bool border;

float box(vec2 position, vec2 halfSize, float cornerRadius) {
   position = abs(position) - halfSize + cornerRadius;
   return length(max(position, 0.0)) + min(max(position.x, position.y), 0.0) - cornerRadius;
}

vec4 get_border_color() {
    vec2 tex_coords = vec2(1, -1) * v_position * 0.5 + 0.5;
    vec2 position   = (tex_coords * resolution + chroma_offset) / screen_resolution;
    if (chroma) {
        return vec4(
            sqrt(vec3(
                0.5 + 0.5 * sin(position.x + position.y + (chroma_time + 0.0 / 3) * 2 * 3.14159265359),
                0.5 + 0.5 * sin(position.x + position.y + (chroma_time + 1.0 / 3) * 2 * 3.14159265359),
                0.5 + 0.5 * sin(position.x + position.y + (chroma_time + 2.0 / 3) * 2 * 3.14159265359)
            )),
            border_color.a
        );
    } else {
        return border_color;
    }
}

void main() {
    float l = box(v_position * resolution, resolution, radius * 2) * 0.5;
    float a = 1;
    vec4 color = vec4(0);
    if (l > 0) {
        a = 0;
    } else if (l > -1) {
        a = -l;
        color = get_border_color();
    } else if (l < -width - 1) {
        color = background_color;
    } else if (l < -width) {
        color = mix(background_color, get_border_color(), 1 + l + width);
    } else {
        color = get_border_color();
    }

    frag_color.rgb = color.rgb * a * color.a;
    frag_color.a = a * color.a;
}
