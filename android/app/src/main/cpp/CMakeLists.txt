cmake_minimum_required(VERSION 3.22.1)
project(fetchr_mpv C)

add_library(fetchr_mpv SHARED mpv_guard.c)
target_link_libraries(fetchr_mpv dl)
# Loads on 16 KB page-size devices too.
target_link_options(fetchr_mpv PRIVATE "-Wl,-z,max-page-size=16384")
