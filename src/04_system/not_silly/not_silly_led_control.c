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
#include <stdbool.h>
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
#define LED "10"

#define K1 "10"
#define K2 "10"
#define K3 "10"

#define GPIO_LED GPIO LED
#define GPIO_K1 GPIO K1
#define GPIO_K2 GPIO K2
#define GPIO_K3 GPIO K3

typedef enum { GPIO_INPUT, GPIO_OUTPUT } gpio_dir_t;
typedef enum { GPIO_LOW, GPIO_HIGH } gpio_state_t;
typedef struct {
    int fd;
    gpio_dir_t dir;
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

static void gpio_init(gpio_t* gpio, gpio_dir_t dir)
{
    // unexport pin out of sysfs (reinitialization)
    int f = open(GPIO_UNEXPORT, O_WRONLY);

    write(f, LED, strlen(LED));
    close(f);

    // export pin to sysfs
    f = open(GPIO_EXPORT, O_WRONLY);
    write(f, LED, strlen(LED));
    close(f);

    // config pin
    const char* direction = gpio_dir_to_str(dir);

    f = open(GPIO_LED "/direction", O_WRONLY);
    write(f, direction, strlen(direction));
    close(f);

    // open gpio value attribute
    f = open(GPIO_LED "/value", O_RDWR);

    gpio->fd = f;
}

static void gpio_write(gpio_t* gpio, gpio_state_t state)
{
    assert(gpio);
    assert(gpio->dir == GPIO_OUTPUT);
    const char* state_write = gpio_state_to_str(state);

    (void)pwrite(gpio->fd, state_write, strlen(state_write), 0);
}

/*
 * status led - gpioa.10 --> gpio10
 * power led  - gpiol.10 --> gpio362
 */

int main(int argc, char* argv[])
{
    long duty   = 2;     // %
    long period = 1000;  // ms
    if (argc >= 2) period = atoi(argv[1]);
    period *= 1000000;  // in ns
    gpio_t led, k1, k2, k3;

    gpio_init(&led, GPIO_OUTPUT);
    gpio_init(&k1, GPIO_INPUT);
    gpio_init(&k2, GPIO_INPUT);
    gpio_init(&k3, GPIO_INPUT);

    fd_set k1_set;
    fd_set k2_set;
    fd_set k3_set;

    FD_ZERO(&k1_set);
    FD_ZERO(&k2_set);
    FD_ZERO(&k3_set);

    FD_SET(k1.fd, &k1_set);
    FD_SET(k2.fd, &k2_set);
    FD_SET(k3.fd, &k3_set);

    // compute duty period...
    long p1 = period / 100 * duty;
    long p2 = period - p1;

    gpio_write(&led, GPIO_HIGH);

    struct timespec t1;
    clock_gettime(CLOCK_MONOTONIC, &t1);
    bool led_state = true;
    while (1) {
        struct timespec t2;
        clock_gettime(CLOCK_MONOTONIC, &t2);

        long delta =
            (t2.tv_sec - t1.tv_sec) * 1000000000 + (t2.tv_nsec - t1.tv_nsec);

        int toggle = ((led_state == 0) && (delta >= p1)) |
                     ((led_state == 1) && (delta >= p2));
        if (toggle) {
            t1        = t2;
            led_state = !led_state;
            if (led_state) {
                gpio_write(&led, GPIO_LOW);
            } else {
                gpio_write(&led, GPIO_HIGH);
            }
        }
    }

    return 0;
}
