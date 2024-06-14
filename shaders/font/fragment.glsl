#version 450 core

in vec2 tex_coords;

out vec4 FragColor;

uniform vec4 color = vec4(1, 1, 1, 1);
uniform sampler2D tex;

void main() {
    FragColor = color * texture(tex, tex_coords).r;
}
