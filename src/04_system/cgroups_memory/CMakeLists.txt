cmake_minimum_required(VERSION 3.28)
project(cgroups-poc)

include(../../nanopi.cmake)
add_executable(cgroups cgroups.c)
