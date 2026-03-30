ssh root@192.168.53.14 <<EOF
cd /workspace/src/02_modules/exercice08
rmmod mymodule
insmod mymodule.ko
EOF

