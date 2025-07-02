package game

import "core:log"
import "core:math/linalg"
import sg "sokol/gfx"

Sprite_Renderer :: struct {
    pip: sg.Pipeline,
    bind: sg.Bindings,
}

sprite_renderer_init :: proc(sr: ^Sprite_Renderer, rm: ^Resource_Manager) {
    log.info("Initializing sprite renderer...")

    // Create the quad geometry
    Vertex :: struct {
        x, y: f32,
        u, v: f32,
    }

    vertices := [?]Vertex {
        {0, 1, 0, 1},  // bottom-left
        {1, 0, 1, 0},  // top-right
        {0, 0, 0, 0},  // top-left

        {0, 1, 0, 1},  // bottom-left
        {1, 1, 1, 1},  // bottom-right
        {1, 0, 1, 0},  // top-right
    }

    // Create vertex buffer
    sr.bind.vertex_buffers[0] = sg.make_buffer({
        data = { ptr = &vertices, size = size_of(vertices) },
        label = "sprite-vertices",
    })
    if sg.query_buffer_state(sr.bind.vertex_buffers[0]) != .VALID {
        log.error("Failed to create vertex buffer")
        return
    }
    log.info("Created sprite vertex buffer")

    // Set up default bindings
    if tex, ok_white_tex := resman_get_texture(rm^, "white"); ok_white_tex {
        sr.bind.images[IMG_tex] = tex
    }

    sr.bind.samplers[SMP_smp] = sg.make_sampler({
        label = "sprite-sampler",
    })
    if sg.query_sampler_state(sr.bind.samplers[SMP_smp]) != .VALID {
        log.error("Failed to create sampler")
        return
    }
    log.info("Created sprite sampler")

    // Create shader
    shader := sg.make_shader(sprite_shader_desc(sg.query_backend()))
    if sg.query_shader_state(shader) != .VALID {
        log.error("Failed to create shader")
        return
    }
    log.info("Created sprite shader")

    // Create the rendering pipeline
    sr.pip = sg.make_pipeline({
        shader = shader,
		layout = {
			attrs = {
				ATTR_sprite_pos = { format = .FLOAT2 },
				ATTR_sprite_texcoord0 = { format = .FLOAT2 },
			},
		},
        colors = {
            0 = {
                blend = {
                    enabled = true,
                    src_factor_rgb = .SRC_ALPHA,
                    dst_factor_rgb = .ONE_MINUS_SRC_ALPHA,
                    src_factor_alpha = .ONE,
                    dst_factor_alpha = .ONE_MINUS_SRC_ALPHA,
                },
            },
        },
        label = "sprite-pipeline",
    })
    if sg.query_pipeline_state(g.sprite_renderer.pip) != .VALID {
        log.error("Failed to create pipeline")
        return
    }
    log.info("Created sprite pipeline")

    log.info("Done initializing sprite renderer")
}

sprite_renderer_cleanup :: proc(sr: Sprite_Renderer) {
	sg.destroy_buffer(sr.bind.vertex_buffers[0])
	sg.destroy_pipeline(sr.pip)
}

// rotation in degrees
compute_sprite_mvp :: proc(position: Vec2 = {0,0}, size: Vec2 = {10,10}, rotation: f32 = 0) -> Mat4f32 {
	proj := compute_projection()
    model := linalg.matrix4_scale(Vec3{size.x, size.y, 1})
    model = linalg.matrix4_translate(Vec3{-0.5 * size.x, -0.5 * size.y, 0}) * model
    model = linalg.matrix4_rotate(linalg.to_radians(rotation), Vec3{0,0,1}) * model
    model = linalg.matrix4_translate(Vec3{0.5 * size.x, 0.5 * size.y, 0}) * model
    model = linalg.matrix4_translate(Vec3{position.x, position.y, 0}) * model
	return proj * model
}

draw_sprite :: proc(sr: ^Sprite_Renderer, rm: Resource_Manager, position: Vec2, size: Vec2 = {10,10}, rotation: f32 = 0, texture_name: string = "", color: Vec3 = {1,1,1}) {
    // Compute transformation matrix and combine with projection
    mvp := compute_sprite_mvp(position, size, rotation)

    // Prepare shader uniforms
	sprite_vs_params := Sprite_Vs_Params {
		mvp = mvp,
	}
	sprite_fs_params := Sprite_Fs_Params {
		sprite_color = color,
	}

    // Bind texture
    if tex, exists := resman_get_texture(rm, texture_name); exists {
        sr.bind.images[IMG_tex] = tex
    } else {
        sr.bind.images[IMG_tex], _ = resman_get_texture(rm, "white")
    }

    // Issue draw commands
    sg.apply_bindings(sr.bind)
	sg.apply_uniforms(UB_sprite_vs_params, { ptr = &sprite_vs_params, size = size_of(sprite_vs_params) })
	sg.apply_uniforms(UB_sprite_fs_params, { ptr = &sprite_fs_params, size = size_of(sprite_fs_params) })
    sg.draw(0, 6, 1)
}
