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
#include <sys/select.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <time.h>
#include <unistd.h>

#define GPIO_EXPORT "/sys/class/gpio/export"
#define GPIO_UNEXPORT "/sys/class/gpio/unexport"
#define GPIO "/sys/class/gpio/gpio"

#define K1 "0"
#define K2 "2"
#define K3 "3"
#define LED "10"

#define MS_TO_NS(ms) (ms * 1000000)

#define NS_TO_US(ns) (ns / 1000)
#define NS_TO_MS(ns) (ns / 1000000)
#define NS_TO_S(ns) (ns / 1000000000)
#define DEFAULT_PERIOD_NS (MS_TO_NS(500))

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
            return "output";
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

static void gpio_init(gpio_t* gpio, const char* name, gpio_dir_t dir)
{
    // unexport pin out of sysfs (reinitialization)
    int f = open(GPIO_UNEXPORT, O_WRONLY);

    write(f, name, strlen(name));
    close(f);

    // export pin to sysfs
    f = open(GPIO_EXPORT, O_WRONLY);
    write(f, name, strlen(name));
    close(f);

    char path[128];

    // config pin
    const char* direction = gpio_dir_to_str(dir);
    snprintf(path, sizeof(path), "%s%s%s", GPIO, name, "/direction");

    f = open(path, O_WRONLY);
    write(f, direction, strlen(direction));
    close(f);

    snprintf(path, sizeof(path), "%s%s%s", GPIO, name, "/value");

    // open gpio value attribute
    f = open(path, O_RDWR);

    gpio->fd   = f;
    gpio->name = name;
    gpio->dir  = dir;
}

static void gpio_write(gpio_t* gpio, gpio_state_t state)
{
    assert(gpio);
    assert(gpio->dir == GPIO_OUTPUT);
    const char* state_write = gpio_state_to_str(state);

    ssize_t len = pwrite(gpio->fd, state_write, strlen(state_write), 0);
    if (len < 0) {
        fprintf(stderr,
                "failed to read state %s: '%s'\n",
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

/*
 * status led - gpioa.10 --> gpio10
 * power led  - gpiol.10 --> gpio362
 */

int main(int argc, char* argv[])
{
    uint64_t default_period_ns = DEFAULT_PERIOD_NS;
    if (argc >= 2) {
        default_period_ns = MS_TO_NS(atoi(argv[1]));
    }
    uint64_t period_ns = default_period_ns;

    gpio_t led, k1, k2, k3;
    gpio_t* gpios[] = {&led, &k1, &k2, &k3};

    gpio_init(&led, LED, GPIO_OUTPUT);
    gpio_init(&k1, K1, GPIO_INPUT);
    gpio_init(&k2, K2, GPIO_INPUT);
    gpio_init(&k3, K3, GPIO_INPUT);

    int max_fd = -1;

    for (size_t i = 0; i < sizeof(gpios) / sizeof(gpios[0]); ++i) {
        if (gpios[i]->fd > max_fd) {
            max_fd = gpios[i]->fd;
        }
    }

    fd_set k_set;

    FD_ZERO(&k_set);

    FD_SET(k1.fd, &k_set);
    FD_SET(k2.fd, &k_set);
    FD_SET(k3.fd, &k_set);

    gpio_write(&led, GPIO_HIGH);

    struct timespec t1;
    clock_gettime(CLOCK_MONOTONIC, &t1);

    while (1) {
        const uint64_t sec = NS_TO_S(period_ns);
        const uint64_t usec =
            NS_TO_US(period_ns) - (NS_TO_S(period_ns) * 1000000);

        struct timeval tv = {.tv_sec = sec, .tv_usec = usec};
        int ret           = select(max_fd + 1, NULL, NULL, &k_set, &tv);

        if (ret < 0) {
            perror("select");
            continue;
        }
        if (ret == 0) {
            printf("Timeout, toggling led\n");
            /* timeout meaning we need to toggle the led*/
            if (led.state == GPIO_HIGH) {
                gpio_write(&led, GPIO_LOW);
            } else {
                gpio_write(&led, GPIO_HIGH);
            }
            continue;
        }

        if (gpio_read(&k1) == GPIO_LOW && period_ns >= MS_TO_NS(100)) {
            period_ns -= MS_TO_NS(100);
            printf("Decreased period to %" PRIu64 "ms\n", NS_TO_MS(period_ns));
        }
        if (gpio_read(&k2) == GPIO_LOW) {
            period_ns = default_period_ns;
            printf("Resetting period to %" PRIu64 "ms\n", NS_TO_MS(period_ns));
        }
        if (gpio_read(&k3) == GPIO_LOW &&
            period_ns <= UINT64_MAX - MS_TO_NS(100)) {
            period_ns += MS_TO_NS(100);
            printf("Increased period to %" PRIu64 "ms\n", NS_TO_MS(period_ns));
        }
    }
    for (size_t i = 0; i < sizeof(gpios) / sizeof(gpios[0]); ++i) {
        gpio_deinit(gpios[i]);
    }

    return 0;
}
