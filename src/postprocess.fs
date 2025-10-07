#version 330

in vec2 fragTexCoord;

uniform sampler2D texture0;

out vec4 finalColor;

void main()
{
  finalColor.rgb = texture(texture0, fragTexCoord).r > 0 ? vec3(1) : vec3(0);
  finalColor.a = 1.0;
}
