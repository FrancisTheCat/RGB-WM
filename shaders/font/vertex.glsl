#version 450 core

layout (location = 0) in vec2 aPos;
layout (location = 1) in vec2 aTex;

out vec2 tex_coords;

uniform float z;

void main()
{
    tex_coords = aTex;
    gl_Position = vec4(aPos.x, -aPos.y, z, 1);
}
