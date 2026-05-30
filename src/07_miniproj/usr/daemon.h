#ifndef DAEMON_H
#define DAEMON_H

#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>

#include "daemon_key.h"
#include "daemon_led.h"

struct daemon;

#define LED_BLINK_TIME (1000)
#define LED_BLINK_PERIOD_ON_INCREASE (100)
#define LED_BLINK_PERIOD_ON_DECREASE (200)

#define LED_BLINK_COUNT_ON_INCREASE \
    (LED_BLINK_TIME / LED_BLINK_PERIOD_ON_INCREASE)
#define LED_BLINK_COUNT_ON_DECREASE \
    (LED_BLINK_TIME / LED_BLINK_PERIOD_ON_DECREASE)

typedef struct {
    daemon_key_t key_speed_up;
    daemon_key_t key_slow_down;
    daemon_key_t key_mode;
    daemon_led_t led_power;
    int timer_fd;
    int32_t led_blink_count;
    uint32_t led_blink_period;
} daemon_io_t;

typedef struct {
    int server_fd;
} daemon_ipc_t;

typedef void (*daemon_event_cb)(struct daemon* daemon, void* event_data);

typedef struct {
    int events;
    int fd;
    daemon_event_cb cb;
    void* event_data;
} daemon_event_ctx_t;

typedef struct daemon {
    daemon_io_t io;
    daemon_ipc_t ipc;
    int epfd;
    int mode_fd;
    int freq_fd;
    daemon_event_ctx_t* events;
    size_t event_count;
    size_t event_capacity;
} daemon_t;

int daemon_init(daemon_t* daemon);
int daemon_run(daemon_t* daemon);
void daemon_deinit(daemon_t* daemon);

int daemon_ipc_init(daemon_t* daemon);
void daemon_ipc_deinit(daemon_ipc_t* ipc);

int daemon_io_init(daemon_t* daemon);
void daemon_io_deinit(daemon_io_t* daemon_io);

int daemon_increase_frequency(daemon_t* daemon, int* new_freq);
int daemon_decrease_frequency(daemon_t* daemon, int* new_freq);
int daemon_toggle_mode(daemon_t* daemon, int* new_mode);

int daemon_get_mode(daemon_t* daemon, int* mode);
int daemon_set_mode(daemon_t* daemon, int mode);
int daemon_set_frequency(daemon_t* daemon, int frequency);
int daemon_get_frequency(daemon_t* daemon, int* frequency);

int daemon_add_event(daemon_t* daemon, daemon_event_ctx_t ctx);
void daemon_remove_event(daemon_t* daemon, int fd);

#endif
