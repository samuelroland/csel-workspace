/* skeleton.c */
#include <linux/cdev.h> /* needed for char device driver */
#include <linux/fs.h>   /* needed for device drivers */
#include <linux/gfp.h>
#include <linux/init.h>        /* needed for macros */
#include <linux/kernel.h>      /* needed for debugging */
#include <linux/module.h>      /* needed by all modules */
#include <linux/moduleparam.h> /* needed for module parameters */
#include <linux/slab.h>        /* needed to copy data to/from user */
#include <linux/types.h>
#include <linux/uaccess.h> /* needed to copy data to/from user */

#define BUFFER_SZ 10000

static uint instances = 1;
module_param(instances, uint, 0);

struct buffer {
    char data[BUFFER_SZ];
};

static struct buffer* buffers;

static dev_t skeleton_dev;
static struct cdev* skeleton_cdev;

static int skeleton_open(struct inode* i, struct file* f)
{
    pr_info("skeleton : open operation... major:%d, minor:%d\n",
            imajor(i),
            iminor(i));

    if ((f->f_flags & (O_APPEND)) != 0) {
        pr_info("skeleton : opened for appending...\n");
    }

    if ((f->f_mode & (FMODE_READ | FMODE_WRITE)) != 0) {
        pr_info("skeleton : opened for reading & writing...\n");
    } else if ((f->f_mode & FMODE_READ) != 0) {
        pr_info("skeleton : opened for reading...\n");
    } else if ((f->f_mode & FMODE_WRITE) != 0) {
        pr_info("skeleton : opened for writing...\n");
    }
    f->private_data = (void*)(uintptr_t)iminor(i);

    return 0;
}

static int skeleton_release(struct inode* i, struct file* f)
{
    pr_info("skeleton: release operation...\n");

    return 0;
}

static ssize_t skeleton_read(struct file* f,
                             char __user* buf,
                             size_t count,
                             loff_t* off)
{
    char* buffer          = NULL;
    char* ptr             = NULL;
    ssize_t remaining     = 0;
    size_t instance_index = (size_t)(uintptr_t)f->private_data;
    if (instance_index >= instances) {
        pr_err("invalid instance index. expected 0..%u", instances - 1);
        return 0;
    }
    buffer = buffers[instance_index].data;

    pr_info("skeleton read: at%ld\n", (unsigned long)(*off));
    // compute remaining bytes to copy, update count and pointers
    remaining = BUFFER_SZ - (ssize_t)(*off);
    if (remaining <= 0) {
        return 0;
    }
    ptr = buffer + *off;
    if (count > remaining) count = remaining;
    *off += count;

    // copy required number of bytes
    if (copy_to_user(buf, ptr, count) != 0) count = -EFAULT;

    pr_info("skeleton: read operation... read=%ld\n", count);

    return count;
}

static ssize_t skeleton_write(struct file* f,
                              const char __user* buf,
                              size_t count,
                              loff_t* off)
{
    // compute remaining space in buffer and update pointers
    ssize_t remaining     = BUFFER_SZ - (ssize_t)(*off);
    char* buffer          = NULL;
    size_t instance_index = (size_t)(uintptr_t)f->private_data;
    if (instance_index >= instances) {
        pr_err("invalid instance index. expected 0..%u", instances - 1);
        return 0;
    }
    buffer = buffers[instance_index].data;

    pr_info("skeleton write: at%ld\n", (unsigned long)(*off));

    // check if still remaining space to store additional bytes
    if (count >= remaining) count = -EIO;

    // store additional bytes into internal buffer
    if (count > 0) {
        char* ptr = buffer + *off;
        *off += count;
        ptr[count] = 0;  // make sure string is null terminated
        if (copy_from_user(ptr, buf, count)) count = -EFAULT;
    }

    pr_info("skeleton: write operation... written=%ld\n", count);

    return count;
}

loff_t skeleton_llseek(struct file* f, loff_t offset, int whence)
{
    size_t instance_index = (size_t)(uintptr_t)f->private_data;
    loff_t new_offset     = 0;

    if (instance_index >= instances) {
        pr_err("invalid instance index. expected 0..%u", instances - 1);
        return -EINVAL;
    }

    switch (whence) {
        case SEEK_SET:
            new_offset = offset;
            break;
        case SEEK_CUR:
            new_offset = f->f_pos + offset;
            break;
        case SEEK_END:
            new_offset = BUFFER_SZ + offset;
            break;
        default:
            return -EINVAL;
    }

    if (new_offset < 0 || new_offset >= BUFFER_SZ) {
        return -EINVAL;
    }
    f->f_pos = new_offset;
    return new_offset;
}

static struct file_operations skeleton_fops = {
    .owner   = THIS_MODULE,
    .open    = skeleton_open,
    .read    = skeleton_read,
    .write   = skeleton_write,
    .llseek  = skeleton_llseek,
    .release = skeleton_release,
};

static int __init skeleton_init(void)
{
    int err = 0;
    uint i  = 0;
    uint j  = 0;
    if (instances == 0) {
        pr_err("instances must be > 0");
        return -EINVAL;
    }

    err = alloc_chrdev_region(&skeleton_dev, 0, instances, "mymodule");
    if (err) {
        pr_err("alloc_chrdev_region failed %d", err);
        goto err;
    }

    skeleton_cdev = kcalloc(instances, sizeof(*skeleton_cdev), GFP_KERNEL);
    if (!skeleton_cdev) {
        pr_err("No memory for cdevs");
        err = -ENOMEM;
        goto err;
    }

    buffers = kcalloc(instances, sizeof(*buffers), GFP_KERNEL);
    if (!buffers) {
        pr_err("No memory for buffers");
        err = -ENOMEM;
        goto err;
    }

    for (i = 0; i < instances; ++i) {
        cdev_init(skeleton_cdev + i, &skeleton_fops);
        skeleton_cdev[i].owner = THIS_MODULE;
        err = cdev_add(skeleton_cdev + i, MKDEV(MAJOR(skeleton_dev), i), 1);
        if (err) {
            pr_err("cdev_add failed %d", err);
            goto err;
        }
    }
    pr_info("Linux module skeleton loaded. Instance count is %d\n", instances);
    return 0;
err:

    for (j = 0; j < i; ++j) {
        cdev_del(skeleton_cdev + j);
    }
    kfree(buffers);
    kfree(skeleton_cdev);
    unregister_chrdev_region(skeleton_dev, instances);
    return err;
}

static void __exit skeleton_exit(void)
{
    uint i;
    for (i = 0; i < instances; ++i) {
        cdev_del(skeleton_cdev + i);
    }
    kfree(skeleton_cdev);
    kfree(buffers);
    unregister_chrdev_region(skeleton_dev, instances);

    pr_info("Linux module skeleton unloaded\n");
}

module_init(skeleton_init);
module_exit(skeleton_exit);

MODULE_AUTHOR("Daniel Gachet <daniel.gachet@hefr.ch>");
MODULE_DESCRIPTION("Module skeleton");
MODULE_LICENSE("GPL");
