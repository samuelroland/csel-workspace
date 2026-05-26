#define _GNU_SOURCE
#include <pthread.h>
#include <sched.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

// https://www.reddit.com/r/C_Programming/comments/6zxnr1/how_to_find_the_number_of_cores_in_c/
long available_cpu_cores() { return sysconf(_SC_NPROCESSORS_ONLN); }

void* do_heavy_work(void* arg) {
    printf("Heavy thread started !\n");
    volatile size_t counter = 0;
    while (1) {
        counter ^= (counter << 13);
        counter ^= (counter >> 7);
        counter ^= (counter << 17);
    }
}

void do_heavy_work_on_all_cores(long cores) {
    pthread_t* threads = malloc(sizeof(pthread_t) * cores);
    for (int i = 0; i < cores; i++) {
        pthread_create(&threads[i], NULL, do_heavy_work, NULL);
    }
    for (int i = 0; i < cores; i++) {
        pthread_join(threads[i], NULL);
    }
}
int main(void) {
    long cores = available_cpu_cores();
    printf("Detected %ld available CPU cores\n", cores);

    int pid = fork();
    if (pid < 0) {
        perror("fork failed");
        return EXIT_FAILURE;
    }
    if (pid == 0)  // child code
    {
        printf("Starting heavy work as child\n");
        do_heavy_work_on_all_cores(cores);
    } else {  // parent code
        printf("Starting heavy work as parent\n");
        do_heavy_work_on_all_cores(cores);
    }
}
