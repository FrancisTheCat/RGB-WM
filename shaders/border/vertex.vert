#version 450

layout (location = 0) in vec2 a_pos;

out vec2 v_position;

uniform float ux;
uniform float uy;

void main() {
    vec2 pos = a_pos;
    if (pos.x > 1.5) {
        pos.x = ux;
    }
    if (pos.x < -1.5) {
        pos.x = -ux;
    }
    if (pos.y > 1.5) {
        pos.y = uy;
    }
    if (pos.y < -1.5) {
        pos.y = -uy;
    }
    v_position = pos;
    gl_Position = vec4(pos, 0, 1);
}
