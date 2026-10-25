cmake_minimum_required(VERSION 3.5)
project(anydeck_audio_bridge)
add_library(entry SHARED AudioBridge.cpp)
target_link_libraries(entry PUBLIC libace_napi.z.so libnative_avscreen_capture.so libnative_media_core.so)
