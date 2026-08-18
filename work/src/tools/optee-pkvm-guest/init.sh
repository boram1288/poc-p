#!/bin/sh

set -u

mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev || true

echo "PVM_LINUX_BOOT_OK"

attempt=0
while [ "${attempt}" -lt 100 ]; do
	[ -e /dev/teepriv0 ] && break
	sleep 0.05
	attempt=$((attempt + 1))
done

if [ ! -e /dev/teepriv0 ]; then
	echo "PVM_OPTEE_DEVICE_FAILED"
	poweroff -f
fi

chmod 0600 /dev/tee0 /dev/teepriv0
/usr/sbin/tee-supplicant -d /dev/teepriv0
if [ "$?" -ne 0 ]; then
	echo "PVM_TEE_SUPPLICANT_FAILED"
	poweroff -f
fi

echo "PVM_OPTEE_PROBE_OK"
/usr/bin/optee_example_aes
aes_rc=$?
if [ "${aes_rc}" -eq 0 ]; then
	echo "PVM_TA_AES_4K_OK: bytes=4096 encrypt=ok decrypt=ok compare=ok"
else
	echo "PVM_TA_AES_FAILED: rc=${aes_rc}"
fi

poweroff -f
