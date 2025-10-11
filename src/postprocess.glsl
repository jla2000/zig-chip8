/// Post-processing shader that adds a vignette plus some simulated scanlines.

#version 330

in vec2 fragTexCoord;

uniform sampler2D texture0;
uniform float time;

out vec4 finalColor;

void main() {
  float freq = 32;
  float globalPos = (fragTexCoord.y + time) * freq;
  float wavePos = cos((fract(globalPos) - 0.5) * 3.14);

  vec3 pixel = texture(texture0, fragTexCoord).r > 0 ? vec3(1) : vec3(0);

  float dist = length((fragTexCoord - 0.5) * 2.0);
  float radius = 1.3;
  float strength = 0.5;
  float vignette = smoothstep(radius, radius - strength, dist);

  finalColor.rgb = mix(vec3(0.02), pixel, wavePos) * vignette;
  finalColor.w = 1;
}
