cmake_minimum_required(VERSION 3.14)
project(saia_turbovec_plugin LANGUAGES CXX)

add_library(saia_turbovec_plugin INTERFACE)

# Install rule to copy the DLL to the build output
set(turbovec_dll "${CMAKE_CURRENT_SOURCE_DIR}/turbovec.dll")
if (EXISTS "${turbovec_dll}")
    # Copy DLL to output directory
    add_custom_command(
        TARGET saia_turbovec_plugin POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
        "${turbovec_dll}"
        $<TARGET_FILE_DIR:flutter_wrapper_app>
    )
endif()
