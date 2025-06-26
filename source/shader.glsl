//------------------------------------------------------------------------------
//  Shader code for texcube-sapp sample.
//
//  NOTE: This source file also uses the '#pragma sokol' form of the
//  custom tags.
//------------------------------------------------------------------------------
@header package game
@header import sg "sokol/gfx"
@ctype mat4 Mat4

// ============================================================================
// SPRITE SHADER
// ============================================================================
@vs sprite_vs
layout(binding=0) uniform sprite_vs_params {
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

@fs sprite_fs
layout(binding=0) uniform texture2D tex;
layout(binding=1) uniform sampler smp;
layout(binding=2) uniform sprite_fs_params{
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
@program sprite sprite_vs sprite_fs

// ============================================================================
// PARTICLE SHADER
// ============================================================================
@vs particle_vs
layout(binding=0) uniform particle_vs_params {
    mat4 projection;
    vec2 offset;
    vec4 color;
};
in vec4 vertex;
out vec2 TexCoords;
out vec4 ParticleColor;

void main() {
    float scale = 10.0f;
    TexCoords = vertex.zw;
    ParticleColor = color;
    gl_Position = projection * vec4((vertex.xy * scale) + offset, 0.0f, 1.0f);
}
@end

@fs particle_fs
layout(binding=0) uniform texture2D particle_tex;
layout(binding=1) uniform sampler particle_smp;

in vec2 TexCoords;
in vec4 ParticleColor;
out vec4 frag_color;

void main() {
    // frag_color = vec4(1.0f, 0.0f, 0.0f, 1.0f);
    // frag_color = texture(sampler2D(tex, smp), uv) ; //* color;
    frag_color = ParticleColor * texture(sampler2D(particle_tex, particle_smp), TexCoords);
}
@end
@program particle particle_vs particle_fs
