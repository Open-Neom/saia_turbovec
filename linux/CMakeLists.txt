cmake_minimum_required(VERSION 3.10)
project(saia_turbovec_plugin LANGUAGES CXX)

add_library(saia_turbovec_plugin INTERFACE)

# Copy the vendored SO to the output directory of the parent app
set(turbovec_so "${CMAKE_CURRENT_SOURCE_DIR}/libturbovec.so")
if (EXISTS "${turbovec_so}")
    add_custom_command(
        TARGET saia_turbovec_plugin POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
        "${turbovec_so}"
        $<TARGET_FILE_DIR:flutter>
    )
endif()
