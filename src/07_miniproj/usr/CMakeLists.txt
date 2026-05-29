cmake_minimum_required(VERSION 3.12)
project(fan_control_usr C)

set(CMAKE_C_STANDARD 99)
set(CMAKE_C_STANDARD_REQUIRED ON)

add_executable(client client_main.c)

set(DAEMON_SOURCES
    daemon.c
    daemon_io.c
    daemon_ipc.c
    daemon_key.c
    daemon_led.c
    daemon_main.c
    gpio.c)

add_executable(daemon ${DAEMON_SOURCES})

target_compile_definitions(daemon PRIVATE _GNU_SOURCE)
target_compile_options(daemon PRIVATE -Wall -Wextra -Wpedantic)
target_compile_options(client PRIVATE -Wall -Wextra -Wpedantic)
