package game

import "core:log"
import sg "sokol/gfx"
import stbtt "vendor:stb/truetype"

ATLAS_SIZE :: 512
MAX_TEXT_LENGTH :: 256
N_VERTICES_PER_CHAR :: 6
N_FLOATS_PER_VERTEX :: 4

Text_Renderer :: struct {
    atlas_texture: sg.Image,
    characters: map[rune]Character,
    pip: sg.Pipeline,
    bind: sg.Bindings,
    vertex_buffer: sg.Buffer,

    font_size: f32,
    line_height: f32,
    batch: Text_Batch,
}

Character :: struct {
    width, height: i32,
    offset_x, offset_y: f32,
    advance: f32,
    u0,v0,u1,v1: f32,
}

Text_Vertex :: struct {
    x, y: f32,
    u, v: f32,
}

Text_Batch :: struct {
    vertices: [dynamic]Text_Vertex,
    draw_commands: [dynamic]Text_Draw_Command,
}

Text_Draw_Command :: struct {
    start_vertex: i32,
    num_vertices: i32,
    color: Vec3,
}

text_renderer_init :: proc(tr: ^Text_Renderer, font_path: string, font_size: f32) {
    log.info("Initializing text renderer with font:", font_path, "size:", font_size, "...")

    tr.font_size = font_size

    font_data, ok := read_entire_file(font_path)
    if !ok {
        log.error("Failed to load font file:", font_path)
        return
    }
    defer delete(font_data)

    font_info: stbtt.fontinfo
    if !stbtt.InitFont(&font_info, raw_data(font_data), 0) {
        log.error("Failed to init font")
        return
    }

    create_font_atlas(tr, &font_info, font_size)

    tr.vertex_buffer = sg.make_buffer({
        size = MAX_TEXT_LENGTH * N_VERTICES_PER_CHAR * size_of(Text_Vertex),
        usage = { stream_update = true },
        label = "text-vertices",
    })

    tr.bind.vertex_buffers[0] = tr.vertex_buffer
    tr.bind.images[IMG_text_atlas] = tr.atlas_texture
    tr.bind.samplers[SMP_text_smp] = sg.make_sampler({
        min_filter = .LINEAR,
        mag_filter = .LINEAR,
        label = "text-sampler",
    })

    shader := sg.make_shader(text_shader_desc(sg.query_backend()))

    tr.pip = sg.make_pipeline({
        shader = shader,
        layout = {
            attrs = {
                ATTR_text_pos = { format = .FLOAT2 },
                ATTR_text_tex_coords = { format = .FLOAT2 },
            },
        },
        colors = {
            0 = {
                blend = {
                    enabled = true,
                    src_factor_rgb = .SRC_ALPHA,
                    dst_factor_rgb = .ONE_MINUS_SRC_ALPHA,
                },
            },
        },
        label = "text-pipeline",
    })

    tr.batch.vertices = make([dynamic]Text_Vertex, 0, MAX_TEXT_LENGTH * N_VERTICES_PER_CHAR)
    tr.batch.draw_commands = make([dynamic]Text_Draw_Command, 0, 32)

    log.info("Initialized text renderer")
}

text_renderer_flush :: proc(tr: ^Text_Renderer) {
    if len(tr.batch.vertices) == 0 do return

    // Single buffer update for all text
    sg.update_buffer(tr.vertex_buffer, {
        ptr = raw_data(tr.batch.vertices),
        size = uint(len(tr.batch.vertices) * size_of(Text_Vertex)),
    })

    sg.apply_pipeline(tr.pip)
    sg.apply_bindings(tr.bind)

    vs_params := Text_Vs_Params{
        projection = compute_projection(),
    }
    sg.apply_uniforms(UB_text_vs_params, { ptr = &vs_params, size = size_of(vs_params) })

    for cmd in tr.batch.draw_commands {
        fs_params := Text_Fs_Params{
            text_color = cmd.color,
        }
        sg.apply_uniforms(UB_text_fs_params, { ptr = &fs_params, size = size_of(fs_params) })
        sg.draw(cmd.start_vertex, cmd.num_vertices, 1)
    }

    clear(&tr.batch.vertices)
    clear(&tr.batch.draw_commands)
}

create_font_atlas :: proc(tr: ^Text_Renderer, font_info: ^stbtt.fontinfo, size: f32) {
    scale := stbtt.ScaleForPixelHeight(font_info, size)

    // get font vertical metrics
    ascent, descent, line_gap: i32
    stbtt.GetFontVMetrics(font_info, &ascent, &descent, &line_gap)
    tr.line_height = f32(ascent - descent + line_gap) * scale

    atlas_bitmap := make([]u8, ATLAS_SIZE * ATLAS_SIZE)
    defer delete(atlas_bitmap)

    curr_x: i32 = 1
    curr_y: i32 = 1
    row_height: i32 = 0

    // Render ea ascii char (32-127)
    for c: rune = 32; c < 128; c += 1 {
        // get char bitmap
        char_width, char_height, xoff, yoff: i32
        char_bitmap := stbtt.GetCodepointBitmap(
            font_info,
            scale, scale,
            c,
            &char_width, &char_height,
            &xoff, &yoff,
        )

        if char_bitmap == nil {
            // handle space and other invisibles
            advance, _x : i32
            stbtt.GetCodepointHMetrics(font_info, c, &advance, &_x)

            tr.characters[c] = Character {
                width = 0,
                height = 0,
                advance = f32(advance) * scale,
            }
            continue
        }
        defer stbtt.FreeBitmap(char_bitmap, nil)

        // move to next row if needed
        if curr_x + char_width + 1 > ATLAS_SIZE {
            curr_x = 1
            curr_y += row_height + 1
            row_height = 0
        }

        // copy character to atlas
        for y in 0..<char_height {
            for x in 0..<char_width {
                src_idx := y * char_width + x
                dst_idx := (curr_y + y) * ATLAS_SIZE + curr_x + x
                atlas_bitmap[dst_idx] = char_bitmap[src_idx]
            }
        }

        advance, _x: i32
        stbtt.GetCodepointHMetrics(font_info, c, &advance, &_x)

        tr.characters[c] = Character {
            width = char_width,
            height = char_height,
            offset_x = f32(xoff),
            offset_y = f32(yoff),
            advance = f32(advance) * scale,
            u0 = f32(curr_x) / f32(ATLAS_SIZE),
            v0 = f32(curr_y) / f32(ATLAS_SIZE),
            u1 = f32(curr_x + char_width) / f32(ATLAS_SIZE),
            v1 = f32(curr_y + char_height) / f32(ATLAS_SIZE),
        }

        curr_x += char_width + 1
        row_height = max(row_height, char_height)
    }

    // Create texture from atlas
    tr.atlas_texture = sg.make_image({
        width = ATLAS_SIZE,
        height = ATLAS_SIZE,
        pixel_format = .R8,
        data = {
            subimage = {
                0 = {
                    0 = { ptr = raw_data(atlas_bitmap), size = uint(ATLAS_SIZE * ATLAS_SIZE) },
                },
            },
        },
        label = "font-atlas",
    })
}

text_draw :: proc(tr: ^Text_Renderer, text: string, x, y: f32, color: Vec3 = {1, 1, 1}) {
    if len(text) == 0 {
        return
    }

    start_vertex := i32(len(tr.batch.vertices))
    initial_vertices := len(tr.batch.vertices)

    pen_x := x
    pen_y := y

    for c in text {
        if c < 32 || c >= 128 do continue // skip non-ascii

        char := &tr.characters[c]

        if char.width > 0 && char.height > 0 {
            x0 := pen_x + char.offset_x
            y0 := pen_y + char.offset_y
            x1 := x0 + f32(char.width)
            y1 := y0 + f32(char.height)
            // top-left
            append(&tr.batch.vertices, Text_Vertex{
                x0, y0, char.u0, char.v0
            })
            // top-right
            append(&tr.batch.vertices, Text_Vertex{
                x1, y0, char.u1, char.v0
            })
            // bottom-left
            append(&tr.batch.vertices, Text_Vertex{
                x0, y1, char.u0, char.v1
            })
            // top-right
            append(&tr.batch.vertices, Text_Vertex{
                x1, y0, char.u1, char.v0
            })
            // bottom-right
            append(&tr.batch.vertices, Text_Vertex{
                x1, y1, char.u1, char.v1
            })
            // bottom-left
            append(&tr.batch.vertices, Text_Vertex{
                x0, y1, char.u0, char.v1
            })
        }
        pen_x += char.advance
    }

    if len(tr.batch.vertices) > initial_vertices {
        append(&tr.batch.draw_commands, Text_Draw_Command {
            start_vertex = start_vertex,
            num_vertices = i32((len(tr.batch.vertices) - initial_vertices)),
            color = color,
        })
    }
}

text_draw_centered :: proc(tr: ^Text_Renderer, text: string, x, y: f32, color: Vec3 = {1, 1, 1}) {
    width := text_measure(tr, text)
    text_draw(tr, text, x - width / 2, y, color)
}

text_measure :: proc(tr: ^Text_Renderer, text: string) -> f32 {
    width: f32 = 0
    for c in text {
        if c < 32 || c >= 128 do continue 
        width += tr.characters[c].advance
    }
    return width
}

text_renderer_cleanup :: proc(tr: ^Text_Renderer) {
    sg.destroy_image(tr.atlas_texture)
    sg.destroy_buffer(tr.vertex_buffer)
    sg.destroy_pipeline(tr.pip)
    sg.destroy_sampler(tr.bind.samplers[SMP_text_smp])

    delete(tr.batch.vertices)
    delete(tr.batch.draw_commands)
}
