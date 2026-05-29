
#include "daemon_key.h"

#include "gpio.h"
int daemon_key_create(const char* name, daemon_key_t* out_key)
{
    out_key->io.dir  = GPIO_INPUT;
    out_key->io.name = name;

    return gpio_init(&out_key->io);
}

bool daemon_key_read(daemon_key_t* key)
{
    return gpio_read(&key->io) == GPIO_HIGH;
}

int daemon_key_get_fd(daemon_key_t* key) { return key->io.fd; }

void daemon_key_delete(daemon_key_t* key) { gpio_deinit(&key->io); }
