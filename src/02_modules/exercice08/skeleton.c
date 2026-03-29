/* skeleton.c */
#include <linux/gpio.h>      /* needed for i/o handling */
#include <linux/init.h>      /* needed for macros */
#include <linux/interrupt.h> /* needed for interrupt handling */
#include <linux/kernel.h>    /* needed for debugging */
#include <linux/module.h>    /* needed by all modules */

static int __init skeleton_init(void)
{
    todo;
    return status;
}

static void __exit skeleton_exit(void)
{
    todo;
    todo;
}

module_init(skeleton_init);
module_exit(skeleton_exit);

MODULE_AUTHOR("Daniel Gachet <daniel.gachet@hefr.ch>");
MODULE_DESCRIPTION("Module skeleton");
MODULE_LICENSE("GPL");
