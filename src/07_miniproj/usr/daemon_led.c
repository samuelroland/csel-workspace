
#include "daemon_led.h"

int daemon_led_create(const char* name, daemon_led_t* out_led)
{
    out_led->io.dir  = GPIO_OUTPUT;
    out_led->io.name = name;
    return gpio_init(&out_led->io);
}
void daemon_led_set(daemon_led_t* led, bool state)
{
    const gpio_state_t io_state = state ? GPIO_HIGH : GPIO_LOW;
    gpio_write(&led->io, io_state);
}
void daemon_led_toggle(daemon_led_t* led)
{
    gpio_write(&led->io, !led->io.state);
}

void daemon_led_delete(daemon_led_t* led) { gpio_deinit(&led->io); }
