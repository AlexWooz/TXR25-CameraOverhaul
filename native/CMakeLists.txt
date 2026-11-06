cmake_minimum_required(VERSION 3.22)
project(TXRChaseCamNative)

# RE-UE4SS is a checkout of UE4SS at the exact commit of the installed build (d4aebbf0);
# a C++ mod must be built against the same version it runs with. It is git-ignored.
add_subdirectory(RE-UE4SS)
add_subdirectory(TXRChaseCamInput)
