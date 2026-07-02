#version 330

uniform sampler2D skyboxTexture;
uniform float cameraYaw;
uniform float cameraPitch;
uniform float horizontalFov;
uniform float aspect;
uniform float yawOffset;
uniform float pitchOffset;
uniform float exposure;

in vec2 fragUv;
out vec4 fragColor;

const float PI = 3.14159265358979323846;
const float TWO_PI = 6.28318530717958647692;

void main()
{
	vec2 screen = vec2(fragUv.x * 2.0 - 1.0, (1.0 - fragUv.y) * 2.0 - 1.0);
	float halfHorizontalFov = horizontalFov * 0.5;
	float halfVerticalFov = atan(tan(halfHorizontalFov) / max(aspect, 0.1));
	vec3 ray = normalize(vec3(
		screen.x * tan(halfHorizontalFov),
		screen.y * tan(halfVerticalFov),
		1.0
	));

	float pitchAngle = cameraPitch + pitchOffset;
	float pitchSin = sin(pitchAngle);
	float pitchCos = cos(pitchAngle);
	ray = vec3(ray.x, ray.y * pitchCos - ray.z * pitchSin, ray.y * pitchSin + ray.z * pitchCos);

	float yawAngle = cameraYaw + yawOffset;
	float yawSin = sin(yawAngle);
	float yawCos = cos(yawAngle);
	ray = vec3(ray.x * yawCos + ray.z * yawSin, ray.y, ray.z * yawCos - ray.x * yawSin);

	float yaw = atan(ray.x, ray.z);
	float pitch = asin(clamp(ray.y, -1.0, 1.0));

	float u = yaw / TWO_PI;
	float v = clamp(0.5 + pitch / PI, 0.0, 1.0);
	vec3 color = textureLod(skyboxTexture, vec2(u, v), 0.0).rgb;

	color = vec3(1.0) - exp(-color * exposure);
	fragColor = vec4(color, 1.0);
}
