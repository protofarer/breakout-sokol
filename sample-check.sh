#!/bin/bash

# Check all your audio files
for file in assets/*.{wav,ogg,mp3}; do
    echo -n "$file: "
    ffprobe -v error -select_streams a:0 -show_entries stream=sample_rate -of csv=p=0 "$file"
done

# Convert any that don't match to 44100 Hz
# ffmpeg -i assets/hit-nonsolid-old.ogg -ar 44100 -c:a libvorbis -q:a 4 assets/hit-nonsolid.ogg
