//------------------------------------------------------------------------------
//  Shader code for texcube-sapp sample.
//
//  NOTE: This source file also uses the '#pragma sokol' form of the
//  custom tags.
//------------------------------------------------------------------------------
@header package game
@header import sg "sokol/gfx"
@ctype mat4 Mat4f32

// ============================================================================
// SPRITE SHADER
// ============================================================================
@vs sprite_vs
layout(binding=0) uniform sprite_vs_params {
    mat4 mvp;
};

in vec2 pos;
in vec2 tex_coords;

out vec2 uv;

void main() {
    gl_Position = mvp * vec4(pos, 0.0f, 1.0f);
    uv = tex_coords;
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
};
in vec2 pos;
in vec2 tex_coords;
out vec2 uv;

void main() {
    float scale = 10.0f;
    uv = tex_coords;
    gl_Position = projection * vec4((pos * scale) + offset, 0.0f, 1.0f);
}
@end

@fs particle_fs
layout(binding=0) uniform texture2D particle_tex;
layout(binding=1) uniform sampler particle_smp;
layout(binding=2) uniform particle_fs_params{
    vec4 particle_color;
};

in vec2 uv;
out vec4 frag_color;

void main() {
    frag_color = particle_color * texture(sampler2D(particle_tex, particle_smp), uv);
}
@end
@program particle particle_vs particle_fs

// ============================================================================
// POSTPROCESS SHADER
// ============================================================================
@vs postprocess_vs
layout(binding=0) uniform postprocess_vs_params {
    float time;
    // ok to use int instead of bool, supposed industry standard for shader flags
    int chaos;
    int confuse;
    int shake;
};

in vec2 pos;
in vec2 tex_coords;
out vec2 uv;

void main() {
    gl_Position = vec4(pos, 0.0f, 1.0f); 
    vec2 texture = tex_coords;
    
    if (chaos != 0) {
        float strength = 0.3;
        vec2 pos = vec2(tex_coords.x + sin(time) * strength, tex_coords.y + cos(time) * strength);        
        uv = pos;
    }
    else if (confuse != 0) {
        uv = vec2(1.0 - tex_coords.x, 1.0 - tex_coords.y);
    }
    else {
        uv = tex_coords;
    }
    
    if (shake != 0) {
        float strength = 0.01;
        gl_Position.x += cos(time * 10) * strength;        
        gl_Position.y += cos(time * 15) * strength;        
    }
}
@end

@fs postprocess_fs
layout(binding=0) uniform texture2D scene_tex;
layout(binding=1) uniform sampler scene_smp;
layout(binding=2) uniform postprocess_fs_params {
    vec4 offsets[9];
    ivec4 edge_kernel[3];
    vec4 blur_kernel[3];
    int chaos;
    int confuse;
    int shake;
};

in vec2 uv;
out vec4 frag_color;

void main() {
    frag_color = vec4(0.0f);
    vec3 color_samples[9];
    
    // Sample from texture offsets if using convolution matrix
    if(chaos != 0 || shake != 0) {
        for(int i = 0; i < 9; i++)
            color_samples[i] = vec3(texture(sampler2D(scene_tex, scene_smp), uv + offsets[i].xy));
    }

    // Process effects
    if (chaos != 0) {
        // Unpack edge kernel from ivec4 array
        int edge[9];
        edge[0] = edge_kernel[0].x; edge[1] = edge_kernel[0].y; edge[2] = edge_kernel[0].z;
        edge[3] = edge_kernel[0].w; edge[4] = edge_kernel[1].x; edge[5] = edge_kernel[1].y;
        edge[6] = edge_kernel[1].z; edge[7] = edge_kernel[1].w; edge[8] = edge_kernel[2].x;

        for(int i = 0; i < 9; i++)
            frag_color += vec4(color_samples[i] * float(edge[i]), 0.0f);
        frag_color.a = 1.0f;
    }
    else if (confuse != 0) {
        frag_color = vec4(1.0 - texture(sampler2D(scene_tex, scene_smp), uv).rgb, 1.0);
    }
    else if (shake != 0) {
        // Unpack blur kernel from vec4 array
        float blur[9];
        blur[0] = blur_kernel[0].x; blur[1] = blur_kernel[0].y; blur[2] = blur_kernel[0].z;
        blur[3] = blur_kernel[0].w; blur[4] = blur_kernel[1].x; blur[5] = blur_kernel[1].y;
        blur[6] = blur_kernel[1].z; blur[7] = blur_kernel[1].w; blur[8] = blur_kernel[2].x;
        
        for(int i = 0; i < 9; i++)
            frag_color += vec4(color_samples[i] * blur[i], 0.0f);
        frag_color.a = 1.0f;
    }
    else {
        frag_color = texture(sampler2D(scene_tex, scene_smp), uv);
    }
}
@end

@program postprocess postprocess_vs postprocess_fs

// ============================================================================
// TEXT SHADER
// ============================================================================
@vs text_vs
layout(binding=0) uniform text_vs_params {
    mat4 projection;
};

in vec2 pos;
in vec2 tex_coords;
out vec2 uv;

void main() {
    gl_Position = projection * vec4(pos, 0.0, 1.0);
    uv = tex_coords;
}
@end

@fs text_fs
layout(binding=0) uniform texture2D text_atlas;
layout(binding=1) uniform sampler text_smp;
layout(binding=2) uniform text_fs_params {
    vec3 text_color;
};

in vec2 uv;
out vec4 frag_color;

void main() {
    // Sample the red channel (where the font data is) and use it as alpha
    float alpha = texture(sampler2D(text_atlas, text_smp), uv).r;
    frag_color = vec4(text_color, alpha);
}
@end
@program text text_vs text_fs
