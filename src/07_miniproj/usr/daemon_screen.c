#include <ssd1306.h>
#include <stdio.h>
#include <string.h>
#include <sys/timerfd.h>
#include <unistd.h>

#include "daemon.h"
#include "daemon_timer.h"

static void update_screen_cb(daemon_t* daemon, void* user_data);

int daemon_screen_init(daemon_t* daemon)
{
    ssd1306_init();
    memset(&daemon->screen, 0, sizeof(daemon->screen));
    int err = timerfd_create(CLOCK_REALTIME, 0);
    if (err < 0) {
        perror("timerfd_create");
        return err;
    }
    daemon->screen.timer_fd = err;

    daemon_timer_create_event(
        daemon, daemon->screen.timer_fd, update_screen_cb);
    daemon_timer_rearm(daemon->screen.timer_fd, 33);

    /* invalid values so that we initialize the screen*/
    daemon->screen.last_frequency   = -1;
    daemon->screen.last_mode        = -1;
    daemon->screen.last_temperature = -1;

    ssd1306_clear_display();
    ssd1306_set_position(0, 0);
    ssd1306_puts("CSEL");
    ssd1306_set_position(0, 1);
    ssd1306_puts(" CPU Fan Control");
    ssd1306_set_position(0, 2);
    ssd1306_puts("--------------");
    ssd1306_set_position(0, 6);
    ssd1306_puts("Duty: 50%");
    return 0;
}

void daemon_screen_deinit(daemon_screen_t* screen)
{
    ssd1306_clear_display();
    if (screen->timer_fd > 0) {
        close(screen->timer_fd);
        screen->timer_fd = 0;
    }
}

static inline const char* mode_to_string(int mode)
{
    return mode ? "AUTO  " : "MANUAL";
}
static void update_screen_cb(daemon_t* daemon, void* user_data)
{
    (void)user_data;
    int freq;
    int temperature;
    int mode;

    int err = daemon_get_frequency(daemon, &freq);
    if (err) {
        return;
    }

    err = daemon_get_temperature(daemon, &temperature);
    if (err) {
        return;
    }

    err = daemon_get_mode(daemon, &mode);
    if (err) {
        return;
    }

    char buffer[64];

    if (mode != daemon->screen.last_mode) {
        ssd1306_set_position(0, 3);
        snprintf(buffer, sizeof(buffer), "Mode: %5s", mode_to_string(mode));
        ssd1306_puts(buffer);
        daemon->screen.last_mode = mode;
    }

    if (temperature != daemon->screen.last_temperature) {
        ssd1306_set_position(0, 4);
        snprintf(buffer, sizeof(buffer), "Temp: %d'C", temperature);
        ssd1306_puts(buffer);
        daemon->screen.last_temperature = temperature;
    }

    if (freq != daemon->screen.last_frequency) {
        ssd1306_set_position(0, 5);
        snprintf(buffer, sizeof(buffer), "Freq: %3dHz", freq);
        ssd1306_puts(buffer);
    }
}
