#+build !js
package game

import "core:log"
import "core:strings"
import ma "vendor:miniaudio"

Audio_System :: struct {
    engine: ma.engine,
    sounds: map[string]^ma.sound,
}

audio_init :: proc(audio: ^Audio_System) -> bool {
    result := ma.engine_init(nil, &audio.engine)
    if result != .SUCCESS {
        log.error("Failed to initialize audio engine:", result)
        return false
    }
    
    audio.sounds = make(map[string]^ma.sound)
    log.info("Audio system initialized")
    return true
}

audio_cleanup :: proc(audio: ^Audio_System) {
    for name, sound in audio.sounds {
        ma.sound_uninit(sound)
        free(sound)
    }
    delete(audio.sounds)
    ma.engine_uninit(&audio.engine)
}

audio_load_sound :: proc(audio: ^Audio_System, file_path: string, name: string) -> bool {
    sound := new(ma.sound)
    
    file_cstring := strings.clone_to_cstring(file_path, context.temp_allocator)
    result := ma.sound_init_from_file(&audio.engine, file_cstring, nil, nil, nil, sound)
    
    if result != .SUCCESS {
        log.error("Failed to load sound:", file_path, "error:", result)
        free(sound)
        return false
    }
    
    audio.sounds[name] = sound
    log.info("Loaded sound:", name, "from:", file_path)
    return true
}

play_sound :: proc(audio: ^Audio_System, name: string, loop: bool = false) {
    sound, exists := audio.sounds[name]
    if !exists {
        log.error("Sound not found:", name)
        return
    }
    
    ma.sound_set_looping(sound, b32(loop))
    ma.sound_seek_to_pcm_frame(sound, 0)
    ma.sound_start(sound)
}

stop_sound :: proc(audio: ^Audio_System, name: string) {
    sound, exists := audio.sounds[name]
    if !exists do return
    
    ma.sound_stop(sound)
}

stop_all_sounds :: proc(audio: ^Audio_System) {
    for _, sound in audio.sounds {
        ma.sound_stop(sound)
    }
}

set_sound_volume :: proc(audio: ^Audio_System, name: string, volume: f32) {
    sound, exists := audio.sounds[name]
    if !exists do return
    
    ma.sound_set_volume(sound, volume)
}

is_sound_playing :: proc(audio: ^Audio_System, name: string) -> bool {
    sound, exists := audio.sounds[name]
    if !exists do return false
    
    return bool(ma.sound_is_playing(sound))
}
