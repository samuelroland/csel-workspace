cmake_minimum_required(VERSION 3.12)
project(ssd1306 C)

set(CMAKE_C_STANDARD 99)
set(CMAKE_C_STANDARD_REQUIRED ON)

add_library(ssd1306 ssd1306.c)
target_include_directories(ssd1306 PUBLIC ${CMAKE_CURRENT_LIST_DIR})
