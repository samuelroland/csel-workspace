#include <stdio.h>
#include <string.h>
#include <sys/epoll.h>
#include <sys/timerfd.h>
#include <time.h>
#include <unistd.h>

#include "daemon.h"
#include "daemon_key.h"
#include "daemon_timer.h"

typedef int (*key_op_cb_t)(daemon_t* daemon, int*);
static void read_key_event(daemon_t* daemon, void* user_data);
static void timer_done_cb(daemon_t* daemon, void* user_data);
static int create_timer_event(daemon_t* daemon);

int daemon_io_init(daemon_t* daemon)
{
    daemon_io_t* daemon_io = &daemon->io;
    memset(daemon_io, 0, sizeof(*daemon_io));

    /* led */
    int err = daemon_led_create(LED_POWER, &daemon_io->led_power);
    if (err) {
        perror("daemon_led_create");
        return err;
    }
    daemon_led_set(&daemon_io->led_power, false);

    /* timerfd in order to blink the led when S1 or S2 are pressed */
    err = timerfd_create(CLOCK_REALTIME, 0);
    if (err < 0) {
        perror("timerfd_create");
        goto timer_fd_err;
    }
    daemon_io->timer_fd = err;

    /* keys */
    struct {
        const char* name;
        daemon_key_t* key;
    } keys[] = {{.name = K1, .key = &daemon_io->key_speed_up},
                {.name = K2, .key = &daemon_io->key_slow_down},
                {.name = K3, .key = &daemon_io->key_mode}};

    const size_t key_count = sizeof(keys) / sizeof(keys[0]);

    size_t i;
    for (i = 0; i < key_count; ++i) {
        int err = daemon_key_create(keys[i].name, keys[i].key);
        if (err) {
            perror("daemon_key_create");
            goto key_create_err;
        }
        /* dummy read so it doesn' trigger on start*/
        (void)daemon_key_read(keys[i].key);
        daemon_event_ctx_t ev_ctx = {.events = EPOLLERR,
                                     .fd     = daemon_key_get_fd(keys[i].key),
                                     .cb     = read_key_event,
                                     .event_data = keys[i].key};

        err = daemon_add_event(daemon, ev_ctx);
        if (err) {
            goto add_event_err;
        }
    }

    return 0;

add_event_err:
    for (size_t j = 0; j < i; ++j) {
        daemon_remove_event(daemon, daemon_key_get_fd(keys[i].key));
    }
    daemon_key_delete(keys[i].key);
key_create_err:
    for (size_t j = 0; j < i; ++j) {
        daemon_key_delete(keys[j].key);
    }
    close(daemon->io.timer_fd);
timer_fd_err:
    daemon_led_delete(&daemon_io->led_power);
    return err;
}
int daemon_io_deinit(daemon_io_t* daemon_io)
{
    daemon_key_delete(&daemon_io->key_speed_up);
    daemon_key_delete(&daemon_io->key_slow_down);
    daemon_key_delete(&daemon_io->key_mode);
    return 0;
}

static void read_key_event(daemon_t* daemon, void* user_data)
{
    printf("Key pressed event\n");
    daemon_key_t* key = (daemon_key_t*)user_data;
    /* always read the key to reset epoll event */
    daemon_key_read(key);
    if (key == &daemon->io.key_speed_up) {
        daemon->io.led_blink_count  = LED_BLINK_COUNT_ON_INCREASE;
        daemon->io.led_blink_period = LED_BLINK_PERIOD_ON_INCREASE;
        daemon_led_set(&daemon->io.led_power, true);
        daemon_increase_frequency(daemon, NULL);
        create_timer_event(daemon);
        daemon_timer_rearm(daemon->io.timer_fd, daemon->io.led_blink_period);
    } else if (key == &daemon->io.key_slow_down) {
        daemon->io.led_blink_count  = LED_BLINK_COUNT_ON_DECREASE;
        daemon->io.led_blink_period = LED_BLINK_PERIOD_ON_DECREASE;
        daemon_led_set(&daemon->io.led_power, true);
        daemon_decrease_frequency(daemon, NULL);
        create_timer_event(daemon);
        daemon_timer_rearm(daemon->io.timer_fd, daemon->io.led_blink_period);
    } else {
        daemon_toggle_mode(daemon, NULL);
    }
}

static void timer_done_cb(daemon_t* daemon, void* user_data)
{
    (void)user_data;
    if (daemon->io.led_blink_count == 0) {
        daemon_remove_event(daemon, daemon->io.timer_fd);
        daemon_led_set(&daemon->io.led_power, false);
        return;
    }
    daemon_led_toggle(&daemon->io.led_power);
    daemon->io.led_blink_count--;
    daemon_timer_rearm(daemon->io.timer_fd, daemon->io.led_blink_period);
}

static int create_timer_event(daemon_t* daemon)
{
    return daemon_timer_create_event(
        daemon, daemon->io.timer_fd, timer_done_cb);
}
