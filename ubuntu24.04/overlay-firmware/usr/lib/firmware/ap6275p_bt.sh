#!/bin/bash
killall -q -9 brcm_patchram_plus1 || true

echo 0 | tee /sys/class/rfkill/rfkill0/state >/dev/null
echo 0 > /proc/bluetooth/sleep/btwrite
sleep 0.5

echo 1 | tee /sys/class/rfkill/rfkill0/state >/dev/null
echo 1 > /proc/bluetooth/sleep/btwrite
sleep 0.5

/usr/lib/firmware/brcm_patchram_plus1 \
    --enable_hci \
    --no2bytes \
    --use_baudrate_for_download \
    --tosleep 200000 \
    --baudrate 1500000 \
    --patchram /usr/lib/firmware/BCM4362A2.hcd \
    /dev/ttyS8
