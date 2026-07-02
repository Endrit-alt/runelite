#version 330

layout(location = 0) in vec3 position;
layout(location = 1) in vec2 tex;

out vec2 fragUv;

void main()
{
	fragUv = tex;
	gl_Position = vec4(position.xy, 0.0, 1.0);
}
