/* skeleton.c */
#include <linux/init.h>        /* needed for macros */
#include <linux/io.h>          /* needed for mmio handling */
#include <linux/ioport.h>      /* needed for memory region handling */
#include <linux/kernel.h>      /* needed for debugging */
#include <linux/list.h>        /* needed for linked list processing */
#include <linux/module.h>      /* needed by all modules */
#include <linux/moduleparam.h> /* needed for module parameters */
#include <linux/slab.h>        /* needed for dynamic memory allocation */
#include <linux/string.h>      /* needed for string handling */

static struct resource* res[3] = {
    [0] = 0,
};

static int __init skeleton_init(void)
{
    unsigned char* regs[3] = {
        [0] = 0,
    };
    unsigned int chipid[4] = {
        [0] = 0,
    };
    long temp            = 0;
    unsigned int addr[2] = {
        [0] = 0,
    };

    pr_info("Linux module 05 skeleton loaded\n");

    res[0] = request_mem_region(0x01c14000, 0x1000, "allwiner h5 sid");
    // res[1] = request_mem_region (0x01C25000, 0x1000, "allwiner h5 ths");
    // res[2] = request_mem_region (0x01C30000, 0x1000, "allwiner h5 emac");
    if ((res[0] == 0))  // || (res[1] == 0) ||(res[2] == 0))
        pr_info(
            "Error while reserving memory region... [0]=%d, [1]=%d, [2]=%d\n",
            res[0] == 0,
            res[1] == 0,
            res[2] == 0);

    regs[0] = ioremap(0x01c14000, 0x1000);
    regs[1] = ioremap(0x01C25000, 0x1000);
    regs[2] = ioremap(0x01C30000, 0x1000);

    if ((regs[0] == 0) || (regs[1] == 0) || (regs[2] == 0)) {
        pr_info("Error while trying to map processor register...\n");
        return -EFAULT;
    }
    chipid[0] = ioread32(regs[0] + 0x200);
    chipid[1] = ioread32(regs[0] + 0x204);
    chipid[2] = ioread32(regs[0] + 0x208);
    chipid[3] = ioread32(regs[0] + 0x20c);

    pr_info("chipid=%08x'%08x'%08x'%08x\n",
            chipid[0],
            chipid[1],
            chipid[2],
            chipid[3]);

    temp = -1191 * (int)ioread32(regs[1] + 0x80) / 10 + 223000;
    pr_info("temperature=%ld (%d)\n", temp, ioread32(regs[1] + 0x80));

    addr[0] = ioread32(regs[2] + 0x50);
    addr[1] = ioread32(regs[2] + 0x54);
    pr_info("mac-addr=%02x:%02x:%02x:%02x:%02x:%02x\n",
            (addr[1] >> 0) & 0xff,
            (addr[1] >> 8) & 0xff,
            (addr[1] >> 16) & 0xff,
            (addr[1] >> 24) & 0xff,
            (addr[0] >> 0) & 0xff,
            (addr[0] >> 8) & 0xff);

    iounmap(regs[0]);
    iounmap(regs[1]);
    iounmap(regs[2]);

    return 0;
}

static void __exit skeleton_exit(void)
{
    pr_info("Linux module skeleton unloaded\n");
    if (res[0] != 0) release_mem_region(0x01c14000, 0x1000);
    // release_mem_region (0x01C25000, 0x1000);
    // release_mem_region (0x01C30000, 0x1000);
}

module_init(skeleton_init);
module_exit(skeleton_exit);

MODULE_AUTHOR("Daniel Gachet <daniel.gachet@hefr.ch>");
MODULE_DESCRIPTION("Module skeleton");
MODULE_LICENSE("GPL");
