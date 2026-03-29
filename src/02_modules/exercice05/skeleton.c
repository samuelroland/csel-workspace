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

// The SID = chip security id, according to the datasheet at page 80
// This is the 1K zone used for this. "SID 0x01C1 4000---0x01C1 43FF 1K"
#define CHIPID_PAGE_START_ADDR 0x01c14000
// This is the base address of the thermal sensor given at page 277
#define THERMAL_SENSOR_START_ADDR 0x01c25000

struct resource* reserved_zones[3];
unsigned chipid[4];

static int __init skeleton_init(void)
{
    pr_info("Linux module loaded !\n");
    // Reserver region for chipid
    reserved_zones[0] = request_mem_region(
        CHIPID_PAGE_START_ADDR, 1024, "ChipID mapping via the 1K zone for SID");
    if (reserved_zones[0] != NULL) {
        void* chipid_mapped_addr_base = ioremap(CHIPID_PAGE_START_ADDR, 1024);
        if (chipid_mapped_addr_base != NULL) {
            pr_info("mapped CHIPID !");
            chipid[0] = readl(chipid_mapped_addr_base + 0x200);
            chipid[1] = readl(chipid_mapped_addr_base + 0x200 + 0x4);
            chipid[2] = readl(chipid_mapped_addr_base + 0x200 + 0x8);
            chipid[3] = readl(chipid_mapped_addr_base + 0x200 + 0xc);

            pr_info("CHIPID = %0x-%x-%x-%x\n",
                    chipid[0],
                    chipid[1],
                    chipid[2],
                    chipid[3]);
            // Les 4 registres de 32 bits du Chip - ID sont aux adresses
        }
    }
    reserved_zones[1] =
        request_mem_region(THERMAL_SENSOR_START_ADDR,
                           1024,
                           "Thermal sensor mapping via the 1K zone");

    if (reserved_zones[1] != NULL) {
        void* temperature_mapped_addr_base =
            ioremap(THERMAL_SENSOR_START_ADDR, 1024);
        if (temperature_mapped_addr_base != NULL) {
            unsigned temperature_register =
                readl(temperature_mapped_addr_base + 0x80);
            int real_temperature_celsius =
                -1191 * (temperature_register / 10) + 223000;

            pr_info(
                "temperature register = %u and real temperature Celsius %d\n",
                temperature_register,
                real_temperature_celsius);
        }
    } else {
        pr_info("Failed to reserve memory\n");
    }
    // 0x01c1'4200 à 0x01c1'420c Le registre de 32 bits du senseur de
    // température du CPU est à l’adresse 0x01c2'5080 Les 2 registres de 32
    // bits de la MAC adresse sont aux adresses 0x01c3'0050 et 0x01c3'0054
    return 0;
}

static void __exit skeleton_exit(void)
{
    pr_info("Linux module skeleton unloaded\n");

    release_mem_region(CHIPID_PAGE_START_ADDR, 1024);
}

module_init(skeleton_init);
module_exit(skeleton_exit);

MODULE_AUTHOR("Daniel Gachet <daniel.gachet@hefr.ch>");
MODULE_DESCRIPTION("Module skeleton");
MODULE_LICENSE("GPL");
