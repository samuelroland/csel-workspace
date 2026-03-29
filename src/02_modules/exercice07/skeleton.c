/* skeleton.c */
#include <linux/delay.h>   /* needed for delay fonctions */
#include <linux/init.h>    /* needed for macros */
#include <linux/kernel.h>  /* needed for debugging */
#include <linux/kthread.h> /* needed for kernel thread management */
#include <linux/module.h>  /* needed by all modules */
#include <linux/wait.h>    /* needed for waitqueues handling */

int threadfn(void*) {
    pr_info("Thread started !");
    while (!kthread_should_stop()) {
        ssleep(5);
    }

    pr_info("Stopping thread");
}

static int __init skeleton_init(void) {
    pr_info("Linux module 07 skeleton loaded\n");

    kthread_run(threadfn, NULL, "Simple kthread");

    return 0;
}

static void __exit skeleton_exit(void) {
    pr_info("Linux module skeleton unloaded\n");
}

module_init(skeleton_init);
module_exit(skeleton_exit);

MODULE_AUTHOR("Daniel Gachet <daniel.gachet@hefr.ch>");
MODULE_DESCRIPTION("Module skeleton");
MODULE_LICENSE("GPL");
