#ifndef KEY_H
#define KEY_H

#include <stdbool.h>

#include "gpio.h"

#define K1 "0"
#define K2 "2"
#define K3 "3"

typedef struct {
    gpio_t io;
} daemon_key_t;

int daemon_key_create(const char* name, daemon_key_t* out_key);
bool daemon_key_read(daemon_key_t* key);
int daemon_key_get_fd(daemon_key_t* key);
void daemon_key_delete(daemon_key_t* key);

#endif
