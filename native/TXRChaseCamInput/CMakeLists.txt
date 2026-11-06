set(TARGET TXRChaseCamInput)
project(${TARGET})

add_library(${TARGET} SHARED
    dllmain.cpp
    XInputReader.cpp
)
target_include_directories(${TARGET} PRIVATE .)
target_link_libraries(${TARGET} PUBLIC UE4SS)
target_link_libraries(${TARGET} PRIVATE xinput)
