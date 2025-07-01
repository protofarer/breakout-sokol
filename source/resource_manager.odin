package game 

import "core:log"
import "core:strings"
import stbi "vendor:stb/image"
import sg "sokol/gfx"
import ma "vendor:miniaudio"

Resource_Manager :: struct {
    textures: map[string]sg.Image,
    sounds: map[string]^ma.sound,
}

resman_init :: proc(rm: ^Resource_Manager) {
    rm.textures = make(map[string]sg.Image)
    rm.sounds = make(map[string]^ma.sound)
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
                    0 = { ptr = pixels, size = uint(width * height * 4) }, // always 4 bytes per pixel
                },
            },
        },
        label = strings.clone_to_cstring(name),
    })
    if sg.query_image_state(img) != .VALID {
        log.error("Failed to create image for:", name)
        return {}
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

resman_load_sound :: proc(rm: ^Resource_Manager, file: string, name: string) -> ^ma.sound {
    sound := new(ma.sound)

    file_cstring := strings.clone_to_cstring(file)
    result := ma.sound_init_from_file(&g.audio_engine, file_cstring, nil, nil, nil, sound)
    delete(file_cstring)

    if result != ma.result.SUCCESS {
        log.error("Failef to load sound:", file)
        free(sound)
        return nil
    } 

    log.info("Load sound, file:", file, "name:", name)
    g.resman.sounds[name] = sound
    return g.resman.sounds[name]
}

resman_get_sound :: proc(rm: Resource_Manager, name: string) -> (^ma.sound, bool) {
    sound, exists := rm.sounds[name]
    if !exists do log.error("Failed to get sound:", name)
    return sound, exists
}

resman_cleanup :: proc(rm: ^Resource_Manager) {
    delete(g.resman.textures)
    for key, &val in g.resman.sounds {
        ma.sound_uninit(val)
    }
}
