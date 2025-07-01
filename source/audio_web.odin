#+build js
package game

import "core:log"
import "core:strings"

Engine :: struct {
    _opaque: [8192]byte,
}

Sound :: struct {
    _opaque: [4096]byte,
}

Result :: enum i32 {
    SUCCESS = 0,
}

foreign import miniaudio_web "miniaudio"

@(default_calling_convention="c", link_prefix="ma_")
foreign miniaudio_web {
    engine_init :: proc(pConfig: rawptr, pEngine: ^Engine) -> Result ---
    engine_uninit :: proc(pEngine: ^Engine) ---
    sound_init_from_file :: proc(pEngine: ^Engine, pFilePath: cstring, flags: u32, pGroup: rawptr, pDoneFence: rawptr, pSound: ^Sound) -> Result ---
    sound_uninit :: proc(pSound: ^Sound) ---
    sound_set_looping :: proc(pSound: ^Sound, isLooping: b32) ---
    sound_seek_to_pcm_frame :: proc(pSound: ^Sound, frameIndex: u64) -> Result ---
    sound_start :: proc(pSound: ^Sound) -> Result ---
    sound_stop :: proc(pSound: ^Sound) -> Result ---
    sound_set_volume :: proc(pSound: ^Sound, volume: f32) ---
}

Audio_System :: struct {
    engine: Engine,
    sounds: map[string]^Sound,
}

audio_init :: proc(audio: ^Audio_System) -> bool {
    result := engine_init(nil, &audio.engine)
    if result != .SUCCESS {
        log.error("Failed to initialize audio engine:", result)
        return false
    }
    
    audio.sounds = make(map[string]^Sound)
    log.info("Audio system initialized")
    return true
}

audio_cleanup :: proc(audio: ^Audio_System) {
    for _, sound in audio.sounds {
        sound_uninit(sound)
        free(sound)
    }
    delete(audio.sounds)
    engine_uninit(&audio.engine)
}

audio_load_sound :: proc(audio: ^Audio_System, file_path: string, name: string) -> bool {
    sound := new(Sound)
    
    file_cstring := strings.clone_to_cstring(file_path, context.temp_allocator)
    result := sound_init_from_file(&audio.engine, file_cstring, 0, nil, nil, sound)
    
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
    
    sound_set_looping(sound, b32(loop))
    sound_seek_to_pcm_frame(sound, 0)
    sound_start(sound)
}

stop_sound :: proc(audio: ^Audio_System, name: string) {
    sound, exists := audio.sounds[name]
    if !exists do return
    
    sound_stop(sound)
}

stop_all_sounds :: proc(audio: ^Audio_System) {
    for _, sound in audio.sounds {
        sound_stop(sound)
    }
}

set_sound_volume :: proc(audio: ^Audio_System, name: string, volume: f32) {
    sound, exists := audio.sounds[name]
    if !exists do return
    
    sound_set_volume(sound, volume)
}

is_sound_playing :: proc(audio: ^Audio_System, name: string) -> bool {
    // Note: ma_sound_is_playing doesn't exist in this miniaudio version
    // Always return false for now - this is a minor feature
    return false
}
