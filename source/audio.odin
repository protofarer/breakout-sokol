package game

import "core:log"
import ma "vendor:miniaudio"

audio_init :: proc(ae: ^ma.engine) {
    if audio_engine_init_result := ma.engine_init(nil, ae); 
        audio_engine_init_result != ma.result.SUCCESS {
        log.error("Failed to initialize audio engine")
    }
}

play_sound :: proc(rm: Resource_Manager, name: string, loop: b32 = false) {
    // if sound, exists := rm.sounds[name]; exists {
    if sound, exists := resman_get_sound(rm, name); exists {
        ma.sound_set_looping(sound, loop)
        ma.sound_seek_to_pcm_frame(sound, 0)
        ma.sound_start(sound)
    } else {
        log.error("Failed to play sound:", name)
    }
}
