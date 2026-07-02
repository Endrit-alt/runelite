/*
 * Copyright (c) 2018, Adam <Adam@sigterm.info>
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright notice, this
 *    list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright notice,
 *    this list of conditions and the following disclaimer in the documentation
 *    and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
 * ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 * ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */
#version 330

//#define FRAG_UVS
//#define ZBUF_DEBUG

#include colorblind_mode

uniform sampler2DArray textures;
uniform sampler2D skyboxFogTexture;
uniform float brightness;
uniform float smoothBanding;
uniform vec4 fogColor;
uniform float textureLightMode;
uniform int useSkyboxFog;
uniform vec4 skyboxFogViewport;
uniform float skyboxFogCameraYaw;
uniform float skyboxFogCameraPitch;
uniform float skyboxFogHorizontalFov;
uniform float skyboxFogAspect;
uniform float skyboxFogYawOffset;
uniform float skyboxFogPitchOffset;
uniform float skyboxFogExposure;

in vec4 fColor;
noperspective centroid in float fHsl;
flat in int fTextureId;
in vec2 fUv;
in float fFogAmount;
#ifdef ZBUF_DEBUG
in float fDepth;
#endif

out vec4 FragColor;

const float PI = 3.14159265358979323846;
const float TWO_PI = 6.28318530717958647692;
const float SKYBOX_FOG_MIP_LEVEL = 7.0;
const float SKYBOX_FOG_SAMPLE_STEP_U = 0.025;
const float SKYBOX_FOG_SAMPLE_STEP_V = 0.018;

#include "hsl_to_rgb.glsl"

#if COLORBLIND_MODE > 0
#include "colorblind.glsl"
#endif

#ifdef ZBUF_DEBUG
float linear_depth(float depth) {
  // depth is computed as 100/z, solve for z
  float z = 100 / depth;
  return 1 - z / 10000;  // we don't have a far plane, but the client uses 10000
}
#endif

vec3 sampleSkyboxFogAverage(float u, float v) {
  vec3 color = textureLod(skyboxFogTexture, vec2(u, clamp(v, 0.0, 1.0)), SKYBOX_FOG_MIP_LEVEL).rgb * 4.0;
  color += textureLod(skyboxFogTexture, vec2(u - SKYBOX_FOG_SAMPLE_STEP_U, clamp(v, 0.0, 1.0)), SKYBOX_FOG_MIP_LEVEL).rgb;
  color += textureLod(skyboxFogTexture, vec2(u + SKYBOX_FOG_SAMPLE_STEP_U, clamp(v, 0.0, 1.0)), SKYBOX_FOG_MIP_LEVEL).rgb;
  color += textureLod(skyboxFogTexture, vec2(u, clamp(v - SKYBOX_FOG_SAMPLE_STEP_V, 0.0, 1.0)), SKYBOX_FOG_MIP_LEVEL).rgb;
  color += textureLod(skyboxFogTexture, vec2(u, clamp(v + SKYBOX_FOG_SAMPLE_STEP_V, 0.0, 1.0)), SKYBOX_FOG_MIP_LEVEL).rgb;
  return color * 0.125;
}

vec3 sampleSkyboxFogColor() {
  vec2 viewportUv = clamp((gl_FragCoord.xy - skyboxFogViewport.xy) / max(skyboxFogViewport.zw, vec2(1.0)), vec2(0.0), vec2(1.0));
  vec2 screen = viewportUv * 2.0 - 1.0;
  float halfHorizontalFov = skyboxFogHorizontalFov * 0.5;
  float halfVerticalFov = atan(tan(halfHorizontalFov) / max(skyboxFogAspect, 0.1));
  vec3 ray = normalize(vec3(
    screen.x * tan(halfHorizontalFov),
    screen.y * tan(halfVerticalFov),
    1.0
  ));

  float pitchAngle = skyboxFogCameraPitch + skyboxFogPitchOffset;
  float pitchSin = sin(pitchAngle);
  float pitchCos = cos(pitchAngle);
  ray = vec3(ray.x, ray.y * pitchCos - ray.z * pitchSin, ray.y * pitchSin + ray.z * pitchCos);

  float yawAngle = skyboxFogCameraYaw + skyboxFogYawOffset;
  float yawSin = sin(yawAngle);
  float yawCos = cos(yawAngle);
  ray = vec3(ray.x * yawCos + ray.z * yawSin, ray.y, ray.z * yawCos - ray.x * yawSin);

  float yaw = atan(ray.x, ray.z);
  float pitch = asin(clamp(ray.y, -1.0, 1.0));

  float u = yaw / TWO_PI;
  float v = clamp(0.5 + pitch / PI, 0.0, 1.0);
  vec3 color = sampleSkyboxFogAverage(u, v);
  return vec3(1.0) - exp(-color * skyboxFogExposure);
}

void main() {
  vec4 c;

  if (fTextureId > 0) {
    int textureIdx = fTextureId - 1;

    vec4 textureColor = texture(textures, vec3(fUv, float(textureIdx)));
    vec4 textureColor0 = textureLod(textures, vec3(fUv, float(textureIdx)), 0.f);

    if (textureColor0.a < 1.f)
      discard;

    textureColor = vec4(textureColor.rgb, 1.f);

    textureColor = pow(textureColor, vec4(brightness, brightness, brightness, 1.f));

    // textured triangles hsl is a 7 bit lightness 2-126
    float light = fHsl / 127.f;
    vec3 mul = (1.f - textureLightMode) * vec3(light) + textureLightMode * fColor.rgb;
    c = textureColor * vec4(mul, fColor.a);
  } else {
    // pick interpolated hsl or rgb depending on smooth banding setting
    vec3 hsl = vec3(int(fHsl) >> 10 & 63, int(fHsl) >> 7 & 7, int(fHsl) & 127);
    vec3 rgb = mix(fColor.rgb, hslToRgb(hsl), smoothBanding);
    c = vec4(rgb, fColor.a);
  }

#if COLORBLIND_MODE > 0
  c.rgb = colorblind(c.rgb);
#endif

  vec3 targetFogColor = useSkyboxFog != 0 && fFogAmount > 0.0 ? sampleSkyboxFogColor() : fogColor.rgb;
  vec3 mixedColor = mix(c.rgb, targetFogColor, fFogAmount);
  FragColor = vec4(mixedColor, c.a);

#ifdef FRAG_UVS
  if (fTextureId > 0) {
    FragColor = vec4(fUv.x, 0, fUv.y, 1);
  }
#endif

#ifdef ZBUF_DEBUG
  float dc = linear_depth(fDepth);
  if (dc > 1.0) {
    FragColor = vec4(1, 0, 0, 1);
  } else if (dc < -1.0) {
    FragColor = vec4(0, 0, 1, 1);
  } else if (dc < 0.0) {
    FragColor = vec4(0, 1, 0, 1);
  } else {
    FragColor = vec4(dc, dc, dc, 1);
  }
#endif
}
