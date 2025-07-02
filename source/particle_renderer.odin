package game

import "core:log"
import sg "sokol/gfx"

Particle_Renderer :: struct {
    bind: sg.Bindings,
    pip: sg.Pipeline,
    projection: matrix[4,4]f32,
}

Particle_Vertex :: struct {
    x, y: f32,
    u, v: f32,
}

particle_renderer_init :: proc(pr: ^Particle_Renderer, rm: Resource_Manager) {
    log.info("Initializing particle renderer...")

    pr.projection = compute_projection()

    // Create the quad geometry
    particle_quad := [?]Particle_Vertex{
        // pos  // tex
        {0, 1,  0, 1},
        {1, 0,  1, 0},
        {0, 0,  0, 0},

        {0, 1,  0, 1},
        {1, 1,  1, 1},
        {1, 0,  1, 0},
    }

    // Create vertex buffer
    pr.bind.vertex_buffers[0] = sg.make_buffer({
      data = { ptr = &particle_quad, size = size_of(particle_quad) },
      label = "particle-vertices",
    })
    if sg.query_buffer_state(pr.bind.vertex_buffers[0]) != .VALID {
      log.error("Failed to create particles vertex buffer")
      return
    }
    log.info("Created particle vertex buffer")

    // Set up default bindings
    if tex, ok_white_tex := resman_get_texture(rm, "white"); ok_white_tex {
        pr.bind.images[IMG_particle_tex] = tex
    }

    pr.bind.samplers[SMP_particle_smp] = sg.make_sampler({
      label = "particle-sampler",
    })
    if sg.query_sampler_state(g.particle_renderer.bind.samplers[SMP_particle_smp]) != .VALID {
      log.error("Failed to create particle sampler")
      return
    }
    log.info("Created particle sampler")

    // Create shader
    shader := sg.make_shader(particle_shader_desc(sg.query_backend()))
    if sg.query_shader_state(shader) != .VALID {
      log.error("Failed to create particle shader")
      return
    }
    log.info("Created particle shader")

    // Create the rendering pipeline
    pr.pip = sg.make_pipeline({
        shader = shader,
        layout = {
            attrs = {
                    ATTR_particle_pos = {format = .FLOAT2},
                    ATTR_particle_tex_coords = {format = .FLOAT2},
            },
        },
        colors = {
              0 = {
                  blend = {
                      enabled = true,
                      src_factor_rgb = .SRC_ALPHA,
                      dst_factor_rgb = .ONE,
                      src_factor_alpha = .SRC_ALPHA,
                      dst_factor_alpha = .ONE,
                  },
              },
        },
        label = "particle-pipeline",
    })
    if sg.query_pipeline_state(g.particle_renderer.pip) != .VALID {
      log.error("Failed to create particle pipeline")
      return
    }
    log.info("Created particle pipeline")

    log.info("Initialized particle renderer")
}

particle_renderer_cleanup :: proc(pr: Particle_Renderer) {
	sg.destroy_buffer(pr.bind.vertex_buffers[0])
	sg.destroy_pipeline(pr.pip)
}
