ssh root@192.168.53.14 <<EOF
cd /workspace/src/02_modules/exercice07
rmmod mymodule
insmod mymodule.ko
while true; do dmesg -c; done
EOF

