ssh root@192.168.53.14 <<EOF
cd /workspace/src/02_modules/exercice05
insmod mymodule.ko
echo stopping
rmmod mymodule
dmesg -c # read + clean ring buffer
EOF
