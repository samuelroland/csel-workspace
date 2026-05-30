#ifndef DAEMON_LED_H
#define DAEMON_LED_H

#include <stdbool.h>

#include "gpio.h"

typedef struct {
    gpio_t io;
} daemon_led_t;

int daemon_led_create(const char* name, daemon_led_t* out_led);
void daemon_led_set(daemon_led_t* led, bool state);
void daemon_led_toggle(daemon_led_t* led);
void daemon_led_delete(daemon_led_t* led);

#endif
