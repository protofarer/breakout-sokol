// Implementations of `read_entire_file` and `write_entire_file` using the libc
// stuff emscripten exposes. You can read the files that get bundled by
// `--preload-file assets` in `build_web` script.

#+build wasm32, wasm64p32

package web_support

import "base:runtime"
import "core:log"
import "core:c"
import "core:strings"

// Use emscripten's file system API directly
@(default_calling_convention = "c")
foreign {
	emscripten_get_preloaded_file_data :: proc(filename: cstring, size: ^c.int) -> rawptr ---
	emscripten_get_preloaded_file_data_free :: proc(data: rawptr) ---
}

// Similar to raylib's LoadFileData
read_entire_file :: proc(name: string, allocator := context.allocator, loc := #caller_location) -> (data: []byte, success: bool) {
	if name == "" {
		log.error("No file name provided")
		return
	}

	cname := strings.clone_to_cstring(name, context.temp_allocator)
	size: c.int
	file_data := emscripten_get_preloaded_file_data(cname, &size)
	
	if file_data == nil || size <= 0 {
		log.errorf("Failed to load preloaded file %v", name)
		return
	}
	
	defer emscripten_get_preloaded_file_data_free(file_data)

	data_err: runtime.Allocator_Error
	data, data_err = make([]byte, int(size), allocator, loc)

	if data_err != nil {
		log.errorf("Error allocating memory: %v", data_err)
		return
	}

	// Copy from the emscripten memory to our slice
	src_slice := ([^]u8)(file_data)[:int(size)]
	copy(data, src_slice)

	log.debugf("Successfully loaded %v", name)
	return data, true
}

// Similar to raylib's SaveFileData.
//
// Note: For web builds, file writing is not supported with preloaded files.
// This is a stub implementation that logs a warning.
write_entire_file :: proc(name: string, data: []byte, truncate := true) -> (success: bool) {
	if name == "" {
		log.error("No file name provided")
		return
	}

	log.warnf("File writing not supported in web builds: %v", name)
	return false
}