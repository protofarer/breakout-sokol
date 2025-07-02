package game

import "core:log"
import sg "sokol/gfx"
import sapp "sokol/app"

Post_Processor :: struct {
    // Anti-aliasing via multisampled framebuffer
    msaa_attachments: sg.Attachments,
    msaa_color_img: sg.Image,
    msaa_depth_img: sg.Image,

    // Regular framebuffer with texture attachment
    resolve_color_img: sg.Image,

    // Postprocessing pipeline and bindings
    pip: sg.Pipeline,
    bind: sg.Bindings,

    shake: bool,
    confuse: bool,
    chaos: bool,

    shake_time: f32,

    width, height: i32,

    // Cached uniform params
    fs_params: Postprocess_Fs_Params,
}

Post_Processor_Vertex :: struct {
    x, y: f32,
    u, v: f32,
}

post_processor_init :: proc(pp: ^Post_Processor, width, height: i32) {
    log.info("Initializing post processor...")

    pp.width = width
    pp.height = height

    // ms color attach
    pp.msaa_color_img = sg.make_image({
        usage = {
            render_attachment = true,
        },
        width = width,
        height = height,
        pixel_format = .RGBA8,
        sample_count = MSAA_SAMPLE_COUNT, // 4x MSAA
        label = "msaa-color",
    })

    // resolve target (receive msaa resolved image)
    pp.resolve_color_img = sg.make_image({
        usage = {render_attachment = true},
        width = width,
        height = height,
        pixel_format = .RGBA8,
        sample_count = 1,
        label = "resolve-color",
    })

    pp.msaa_depth_img = sg.make_image({
        usage = {render_attachment = true},
        width = width,
        height = height,
        pixel_format = .DEPTH_STENCIL,
        sample_count = MSAA_SAMPLE_COUNT, // 4x MSAA
        label = "msaa-depth",

    })

    // attachments obj with msaa resolve
    pp.msaa_attachments = sg.make_attachments({
        colors = {
            0 = {
                image = pp.msaa_color_img
            },
        },
        resolves = {
            0 = {
                image = pp.resolve_color_img
            }, // triggers msaa resolve
        },
        depth_stencil = {image = pp.msaa_depth_img},
        label = "msaa-attachments",
    })

    // Create quad geometry
    vertices := [?]Post_Processor_Vertex{
        // pos      // tex
        {-1, -1,    0, 0},
        { 1, -1,    1, 0},
        {-1,  1,    0, 1},
        { 1,  1,    1, 1},
    }

    pp.bind.vertex_buffers[0] = sg.make_buffer({
        data = {ptr = &vertices, size = size_of(vertices)},
        label = "post-vertices",
    })

    pp.bind.images[IMG_scene_tex] = pp.resolve_color_img
    pp.bind.samplers[SMP_scene_smp] = sg.make_sampler({
        wrap_u = .REPEAT,
        wrap_v = .REPEAT,
        label = "post-sampler",
    })

    shader := sg.make_shader(postprocess_shader_desc(sg.query_backend()))

    pp.pip = sg.make_pipeline({
        shader = shader,
        layout = {
            attrs = {
                ATTR_postprocess_pos = {format = .FLOAT2},
                ATTR_postprocess_tex_coords = {format = .FLOAT2},
            },
        },
        primitive_type = .TRIANGLE_STRIP,
        label = "post-pipeline",
    })

    params: Postprocess_Fs_Params
    offset: f32 = 1.0 / 300.0
        params.offsets = {
        {-offset,  offset,  0, 0},  // top-left
        { 0.0,     offset,  0, 0},  // top-center
        { offset,  offset,  0, 0},  // top-right
        {-offset,  0,       0, 0},  // center-left
        { 0.0,     0,       0, 0},  // center-center
        { offset,  0,       0, 0},  // center-right
        {-offset, -offset,  0, 0},  // bottom-left
        { 0.0,    -offset,  0, 0},  // bottom-center
        { offset, -offset,  0, 0},  // bottom-right
    }
    // Edge detection kernel
    params.edge_kernel = {
        {-1, -1, -1, 0},
        {-1,  8, -1, 0},
        {-1, -1, -1, 0},
    }
    // Blur kernel (normalized)
    params.blur_kernel = {
        {1.0/16, 2.0/16, 1.0/16, 0},
        {2.0/16, 4.0/16, 2.0/16, 0},
        {1.0/16, 2.0/16, 1.0/16, 0},
    }
    pp.fs_params = params

    log.info("Initialized post processor")
}

post_processor_apply_uniforms :: proc(pp: ^Post_Processor, dt: f32) {
    vs_params := Postprocess_Vs_Params{
        time = f32(sapp.frame_count()) * dt,
        chaos = i32(pp.chaos),
        confuse = i32(pp.confuse),
        shake = i32(pp.shake),
    }
    sg.apply_uniforms(UB_postprocess_vs_params, {
        ptr = &vs_params,
        size = size_of(vs_params),
    })

    // frag shader unforms (with cached params)
    pp.fs_params.chaos = i32(pp.chaos)
    pp.fs_params.confuse = i32(pp.chaos)
    pp.fs_params.shake = i32(pp.shake)
    sg.apply_uniforms(UB_postprocess_fs_params, {
        ptr = &pp.fs_params,
        size = size_of(pp.fs_params),
    })
}

post_processor_update :: proc(pp: ^Post_Processor, dt: f32) {
    if pp.shake_time > 0 {
        pp.shake_time -= dt
        if pp.shake_time <= 0 {
            pp.shake = false
        }
    }
}

post_processor_cleanup :: proc(pp: Post_Processor) {
    sg.destroy_image(g.post_processor.msaa_color_img)
    sg.destroy_image(g.post_processor.msaa_depth_img)
    sg.destroy_image(g.post_processor.resolve_color_img)
    sg.destroy_attachments(g.post_processor.msaa_attachments)
    sg.destroy_buffer(g.post_processor.bind.vertex_buffers[0])
    sg.destroy_pipeline(g.post_processor.pip)
}
