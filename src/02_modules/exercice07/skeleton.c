/* skeleton.c */
#include <linux/atomic.h>  /* needed for atomic variables */
#include <linux/delay.h>   /* needed for delay fonctions */
#include <linux/init.h>    /* needed for macros */
#include <linux/kernel.h>  /* needed for debugging */
#include <linux/kthread.h> /* needed for kernel thread management */
#include <linux/module.h>  /* needed by all modules */
#include <linux/wait.h>    /* needed for waitqueues handling */

DECLARE_WAIT_QUEUE_HEAD(queue);

atomic_t sleeptime;  // the thread 1 must sleep when this is true

int thread1(void*) {
    pr_info("Thread 1 started !\n");
    while (!kthread_should_stop()) {
        int status = wait_event_interruptible(
            queue, (0 == atomic_read(&sleeptime)) || kthread_should_stop());
        if (status < 0) {
            pr_info("Interrupted thread, stopping...\n");
            return -1;
        }
        pr_info("T1: Received tick from thread 2\n");
        atomic_set(&sleeptime, true);
    }

    pr_info("Stopping thread\n");
    return 0;
}

int thread2(void*) {
    pr_info("Thread 2 started !\n");
    while (!kthread_should_stop()) {
        ssleep(5);
        pr_info("T2: Waking up thread 1\n");
        atomic_set(&sleeptime,
                   false);  // so the thread 1 will go out of the waitqueue
        wake_up(&queue);
    }

    atomic_set(&sleeptime,
               false);  // so the thread 1 will go out of the waitqueue
    wake_up(&queue);    // last wakeup to make sure thread 1 can exit
    pr_info("Stopping thread 2\n");
    return 0;
}

struct task_struct* thread1_handle;
struct task_struct* thread2_handle;

static int __init skeleton_init(void) {
    pr_info("Linux module 07 skeleton loaded\n");

    atomic_set(&sleeptime, true);
    thread1_handle = kthread_run(thread1, NULL, "Simple kthread one");
    thread2_handle = kthread_run(thread2, NULL, "Simple kthread two");

    return 0;
}

static void __exit skeleton_exit(void) {
    pr_info("Stopping both threads");
    kthread_stop(thread1_handle);
    kthread_stop(thread2_handle);
    pr_info("Linux module skeleton unloaded\n");
}

module_init(skeleton_init);
module_exit(skeleton_exit);

MODULE_AUTHOR("Daniel Gachet <daniel.gachet@hefr.ch>");
MODULE_DESCRIPTION("Module skeleton");
MODULE_LICENSE("GPL");
