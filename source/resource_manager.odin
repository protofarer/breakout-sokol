package game 

import "core:log"
import "core:strings"
import stbi "vendor:stb/image"
import sg "sokol/gfx"

Resource_Manager :: struct {
    textures: map[string]sg.Image,
}

resman_init :: proc(rm: ^Resource_Manager) {
    log.info("Initializing resource manager...")
    rm.textures = make(map[string]sg.Image)
    log.info("Initialized resource manager")
}

resman_load_texture :: proc(rm: ^Resource_Manager, path: string, name: string) -> sg.Image {
    pixels, width, height, _ := read_image_from_file(path)
    if pixels == nil {
        log.error("Failed to load texture:", path)
        return {}
    }
    defer stbi.image_free(pixels)

    img := sg.make_image({
        width = i32(width),
        height = i32(height),
        pixel_format = .RGBA8,
        data = {
            subimage = {
                0 = {
                    0 = {ptr = pixels, size = uint(width * height * 4)}, // always 4 bytes per pixel
                },
            },
        },
        label = strings.clone_to_cstring(name),
    })
    if sg.query_image_state(img) != .VALID {
        log.error("Failed to create image for:", name, ". Falling back to placeholder texture")
        if tex_white, exists := resman_get_texture(rm^, "white"); exists {
            return tex_white
        } else {
            return {}
        }
    }

    resman_set_texture(rm, name, img)

    log.info("Loaded texture:", name, "size:", width ,"x", height)

    return img
}

resman_set_texture :: proc(rm: ^Resource_Manager, name: string, texture: sg.Image) {
    rm.textures[name] = texture
}

resman_get_texture :: proc(rm: Resource_Manager, name: string) -> (sg.Image, bool) {
    tex, exists := rm.textures[name]
    if !exists do log.error("Failed to get texture:", name)
    return tex, exists
}

resman_cleanup :: proc(rm: ^Resource_Manager) {
    delete(g.resman.textures)
}
