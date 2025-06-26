//------------------------------------------------------------------------------
//  Shader code for texcube-sapp sample.
//
//  NOTE: This source file also uses the '#pragma sokol' form of the
//  custom tags.
//------------------------------------------------------------------------------
@header package game
@header import sg "sokol/gfx"
@ctype mat4 Mat4

@vs vs
layout(binding=0) uniform vs_params {
    mat4 mvp;
};

in vec2 pos;
in vec2 texcoord0;

out vec2 uv;

void main() {
    gl_Position = mvp * vec4(pos, 0.0f, 1.0f);
    uv = texcoord0;
}
@end

@fs fs
layout(binding=0) uniform texture2D tex;
layout(binding=1) uniform sampler smp;
layout(binding=2) uniform fs_params{
    vec3 sprite_color;
};

in vec2 uv;
out vec4 frag_color;

void main() {
    // frag_color = vec4(1.0f, 0.0f, 0.0f, 1.0f);
    // frag_color = texture(sampler2D(tex, smp), uv) ; //* color;
    frag_color = vec4(sprite_color, 1.0) * texture(sampler2D(tex, smp), uv);
}
@end
@program game vs fs
