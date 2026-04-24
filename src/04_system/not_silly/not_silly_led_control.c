/**
 * Copyright 2018 University of Applied Sciences Western Switzerland / Fribourg
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * Project: HEIA-FR / HES-SO MSE - MA-CSEL1 Laboratory
 *
 * Abstract: System programming -  file system
 *
 * Purpose: NanoPi silly status led control system
 *
 * Autĥor:  Daniel Gachet
 * Date:    07.11.2018
 */
#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/epoll.h>
#include <sys/select.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <syslog.h>
#include <time.h>
#include <unistd.h>

#define GPIO_EXPORT "/sys/class/gpio/export"
#define GPIO_UNEXPORT "/sys/class/gpio/unexport"
#define GPIO "/sys/class/gpio/gpio"

#define K1 "0"
#define K2 "2"
#define K3 "3"
#define LED "10"

#define KEY_COUNT 3

#define DEFAULT_PERIOD_MS (500)
#define PERIOD_DELTA_MS (100)

typedef enum { GPIO_INPUT, GPIO_OUTPUT } gpio_dir_t;
typedef enum { GPIO_LOW, GPIO_HIGH } gpio_state_t;

typedef struct {
    const char* name;
    int fd;
    gpio_dir_t dir;
    gpio_state_t state;
} gpio_t;

static const char* gpio_dir_to_str(gpio_dir_t dir)
{
    switch (dir) {
        case GPIO_INPUT:
            return "in";
        case GPIO_OUTPUT:
            return "out";
    }
    assert(0);
}
static const char* gpio_state_to_str(gpio_state_t state)
{
    switch (state) {
        case GPIO_LOW:
            return "0";
        case GPIO_HIGH:
            return "1";
    }
    assert(0);
}
static gpio_state_t gpio_state_from_str(const char* str)
{
    switch (str[0]) {
        case '0':
            return GPIO_LOW;
        case '1':
            return GPIO_HIGH;
    }
    fprintf(stderr, "Invalid state %s\n", str);
    return GPIO_LOW;
}

static int echo(const char* path, const char* value)
{
    int f = open(path, O_WRONLY);
    if (f < 0) {
        fprintf(stderr, "failed to open '%s': '%s'\n", path, strerror(errno));
        return f;
    }
    ssize_t ret = write(f, value, strlen(value));
    close(f);
    if (ret < 0) {
        fprintf(stderr,
                "failed to write '%s' to %s': '%s'\n",
                value,
                path,
                strerror(errno));
        return ret;
    }
    return 0;
}
static int gpio_init(gpio_t* gpio)
{
    assert(gpio);
    assert(gpio->name);

    printf("Initializing gpio %s\n", gpio->name);

    char path[128];
    snprintf(path, sizeof(path), "%s%s", GPIO, gpio->name);
    int ret;
    if (access(path, F_OK) == 0) {
        ret = echo(GPIO_UNEXPORT, gpio->name);
        if (ret) {
            return ret;
        }
    }

    // export pin to sysfs
    ret = echo(GPIO_EXPORT, gpio->name);
    if (ret) {
        goto err;
    }

    // config pin
    const char* direction = gpio_dir_to_str(gpio->dir);
    snprintf(path, sizeof(path), "%s%s%s", GPIO, gpio->name, "/direction");
    ret = echo(path, direction);
    if (ret) {
        goto err;
    }

    if (gpio->dir == GPIO_INPUT) {
        snprintf(path, sizeof(path), "%s%s%s", GPIO, gpio->name, "/edge");
        ret = echo(path, "rising");
        if (ret) {
            goto err;
        }
    }

    snprintf(path, sizeof(path), "%s%s%s", GPIO, gpio->name, "/value");

    int f = open(path, O_RDWR);
    if (f < 0) {
        perror("open value");
        goto err;
    }

    // open gpio value attribute
    gpio->fd = f;
    return 0;

err: {
    int err = echo(GPIO_UNEXPORT, gpio->name);
    if (err < 0) {
        fprintf(stderr, "failed to unexport device after previous error");
    }
    return -1;
    f = open(GPIO_UNEXPORT, O_WRONLY);
    if (f < 0) {
        perror("open unexport");
        return f;
    }
    ret = write(f, gpio->name, strlen(gpio->name));
    close(f);
    if (ret) {
        perror("write unexport");
        return ret;
    }
    return -1;
}
}

static void gpio_write(gpio_t* gpio, gpio_state_t state)
{
    assert(gpio);
    assert(gpio->dir == GPIO_OUTPUT);
    const char* state_write = gpio_state_to_str(state);

    ssize_t len = pwrite(gpio->fd, state_write, strlen(state_write), 0);
    if (len < 0) {
        fprintf(stderr,
                "failed to write state %s: '%s'\n",
                gpio->name,
                strerror(errno));
        return;
    }
    gpio->state = state;
}

static gpio_state_t gpio_read(gpio_t* gpio)
{
    assert(gpio);
    assert(gpio->dir == GPIO_INPUT);
    char state[8];
    ssize_t len = pread(gpio->fd, state, sizeof(state) - 1, 0);
    if (len < 0) {
        fprintf(stderr,
                "failed to read state %s: '%s'\n",
                gpio->name,
                strerror(errno));
        return GPIO_LOW;
    }
    assert(len > 0);
    state[len]  = '\0';
    gpio->state = gpio_state_from_str(state);
    return gpio->state;
}

static void gpio_deinit(gpio_t* gpio)
{
    assert(gpio);

    int f = open(GPIO_UNEXPORT, O_WRONLY);
    write(f, gpio->name, strlen(gpio->name));
    close(f);
    close(gpio->fd);
}

static uint64_t period_ms;
static uint64_t default_period_ms = DEFAULT_PERIOD_MS;

struct key_ctx;

typedef void (*on_key_press_cb_t)(struct key_ctx* ctx);

typedef union {
    on_key_press_cb_t fn;
    void* ptr;
} key_press_t;

typedef struct key_ctx {
    on_key_press_cb_t key_press_cb;
    gpio_t btn;
} key_ctx_t;

static void on_k1_press(key_ctx_t* ctx)
{
    (void)gpio_read(&ctx->btn);
    if (period_ms <= PERIOD_DELTA_MS) {
        syslog(LOG_WARNING, "Minimum period reached (%" PRIu64 ")", period_ms);
        return;
    }
    period_ms -= PERIOD_DELTA_MS;
    syslog(LOG_INFO, "Decreased period to %" PRIu64 "ms\n", period_ms);
}
static void on_k2_press(key_ctx_t* ctx)
{
    (void)gpio_read(&ctx->btn);
    period_ms = default_period_ms;

    syslog(LOG_INFO, "Resetting period to %" PRIu64 "ms\n", period_ms);
}

static void on_k3_press(key_ctx_t* ctx)
{
    (void)gpio_read(&ctx->btn);
    if (period_ms > UINT64_MAX - PERIOD_DELTA_MS) {
        syslog(LOG_WARNING, "Maximum period reached (%" PRIu64 ")", period_ms);
        return;
    }
    period_ms += PERIOD_DELTA_MS;
    syslog(LOG_INFO, "Increased period to %" PRIu64 "ms\n", period_ms);
}

/*
 * status led - gpioa.10 --> gpio10
 * power led  - gpiol.10 --> gpio362
 */

int main(int argc, char* argv[])
{
    int ret = EXIT_SUCCESS;
    if (argc >= 2) {
        default_period_ms = atoi(argv[1]);
    }

    openlog("not_silly_led_control", LOG_PID | LOG_CONS, LOG_DAEMON);

    int epfd = epoll_create1(0);
    if (epfd < 0) {
        perror("epoll_create");
        return EXIT_FAILURE;
    }

    period_ms  = default_period_ms;
    gpio_t led = {.name = LED, .dir = GPIO_OUTPUT};
    int err    = gpio_init(&led);
    if (err) {
        ret = EXIT_FAILURE;
        goto cleanup;
    }

    key_ctx_t key_ctx[KEY_COUNT] = {
        [0] = {.btn          = {.name = K1, .dir = GPIO_INPUT},
               .key_press_cb = on_k1_press},
        [1] = {.btn          = {.name = K2, .dir = GPIO_INPUT},
               .key_press_cb = on_k2_press},
        [2] = {.btn          = {.name = K3, .dir = GPIO_INPUT},
               .key_press_cb = on_k3_press},
    };
    for (size_t i = 0; i < KEY_COUNT; ++i) {
        int err = gpio_init(&key_ctx[i].btn);
        if (err) {
            ret = EXIT_FAILURE;
            goto cleanup;
        }
    }

    struct epoll_event events[KEY_COUNT];

    const size_t event_cnt = sizeof(events) / sizeof(events[0]);

    for (size_t i = 0; i < KEY_COUNT; ++i) {
        struct epoll_event event = {.events = EPOLLERR,
                                    .data   = {.ptr = &key_ctx[i]}};

        int err = epoll_ctl(epfd, EPOLL_CTL_ADD, key_ctx[i].btn.fd, &event);
        if (err < 0) {
            perror("epoll_ctl");
            ret = EXIT_FAILURE;
            goto cleanup;
        }
    }

    gpio_write(&led, GPIO_HIGH);

    while (1) {
        struct epoll_event events[event_cnt];
        int ret = epoll_wait(epfd, events, event_cnt, period_ms);

        if (ret < 0) {
            perror("epoll_wait");
            continue;
        }
        if (ret == 0) {
            /* timeout meaning we need to toggle the led*/
            if (led.state == GPIO_HIGH) {
                syslog(LOG_DEBUG, "Led Off");
                gpio_write(&led, GPIO_LOW);
            } else {
                syslog(LOG_DEBUG, "Led On");
                gpio_write(&led, GPIO_HIGH);
            }
            continue;
        }

        for (size_t i = 0; i < (size_t)ret; ++i) {
            key_ctx_t* ctx = (key_ctx_t*)events[i].data.ptr;
            assert(ctx);
            ctx->key_press_cb(ctx);
        }
    }
cleanup:
    for (size_t i = 0; i < KEY_COUNT; ++i) {
        gpio_deinit(&key_ctx[i].btn);
    }
    gpio_deinit(&led);
    closelog();

    return ret;
}
