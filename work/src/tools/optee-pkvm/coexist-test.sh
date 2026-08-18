#!/bin/sh

set -u

PKVM=${PKVM:-/usr/bin/pkvm}
AES=${AES:-/usr/bin/optee_example_aes}

kvm_fd_count()
{
	count=0
	for fd in /proc/"$1"/fd/*; do
		target=$(readlink "${fd}" 2>/dev/null || true)
		case "${target}" in
			/dev/kvm|anon_inode:*kvm*) count=$((count + 1)) ;;
		esac
	done
	echo "${count}"
}

echo "OPTEE_PKVM_COEX_BEGIN"
chmod 0600 /dev/tee0 /dev/teepriv0
/usr/sbin/tee-supplicant -d /dev/teepriv0
supplicant_rc=$?
if [ "${supplicant_rc}" -ne 0 ]; then
	echo "COEX_TEE_SUPPLICANT_FAILED: rc=${supplicant_rc}"
	exit 9
fi
echo "COEX_TEE_SUPPLICANT_OK"

"${PKVM}" >/tmp/pkvm-coexist.log 2>&1 &
pkvm_pid=$!

attempt=0
kvm_fds=0
while [ "${attempt}" -lt 10000 ]; do
	kvm_fds=$(kvm_fd_count "${pkvm_pid}")
	if [ "${kvm_fds}" -ge 3 ]; then
		# Stop only after KVM_CREATE_VM/KVM_CREATE_VCPU have completed.
		# Repeated STOP/CONT can interrupt those ioctls with EINTR.
		kill -STOP "${pkvm_pid}" 2>/dev/null || kvm_fds=0
		break
	fi
	kill -0 "${pkvm_pid}" 2>/dev/null || break
	attempt=$((attempt + 1))
done

if [ "${kvm_fds}" -lt 3 ]; then
	echo "COEX_KVM_ACTIVE_FAILED: pid=${pkvm_pid} kvm_fds=${kvm_fds}"
	wait "${pkvm_pid}"
	cat /tmp/pkvm-coexist.log
	exit 10
fi
echo "COEX_KVM_ACTIVE: pid=${pkvm_pid} kvm_fds=${kvm_fds}"

"${AES}" >/tmp/aes-during-pvm.log 2>&1 &
aes_pid=$!
kill -CONT "${pkvm_pid}"
wait "${aes_pid}"
aes_rc=$?
cat /tmp/aes-during-pvm.log
if [ "${aes_rc}" -ne 0 ] ||
   ! grep -q "Clear text and decoded text match" /tmp/aes-during-pvm.log; then
	echo "COEX_AES_DURING_PVM_FAILED: rc=${aes_rc}"
	kill "${pkvm_pid}" 2>/dev/null || true
	wait "${pkvm_pid}" 2>/dev/null || true
	exit 11
fi
echo "COEX_AES_DURING_PVM_OK"

wait "${pkvm_pid}"
pkvm_rc=$?
cat /tmp/pkvm-coexist.log
if [ "${pkvm_rc}" -ne 0 ] || ! grep -q "All ok!" /tmp/pkvm-coexist.log; then
	echo "COEX_PVM_FAILED: rc=${pkvm_rc}"
	exit 12
fi
echo "COEX_PVM_OK: rc=${pkvm_rc}"

"${AES}" >/tmp/aes-after-pvm.log 2>&1
aes_reopen_rc=$?
cat /tmp/aes-after-pvm.log
if [ "${aes_reopen_rc}" -ne 0 ] ||
   ! grep -q "Clear text and decoded text match" /tmp/aes-after-pvm.log; then
	echo "COEX_AES_REOPEN_FAILED: rc=${aes_reopen_rc}"
	exit 13
fi

echo "COEX_AES_REOPEN_OK"

/usr/bin/lkvm run --name optee-pvm --protected --protected-ffa \
	--cpus 1 --mem 512 --network mode=none --console serial \
	--kernel /opt/pvm/Image --initrd /opt/pvm/rootfs.cpio.gz \
	--params "earlycon rdinit=/init" >/tmp/optee-pvm-linux.log 2>&1
guest_rc=$?
cat /tmp/optee-pvm-linux.log
if [ "${guest_rc}" -ne 0 ] ||
   ! grep -q "PVM_LINUX_BOOT_OK" /tmp/optee-pvm-linux.log ||
   ! grep -q "PVM_OPTEE_PROBE_OK" /tmp/optee-pvm-linux.log ||
   ! grep -q "PVM_TA_AES_4K_OK: bytes=4096 encrypt=ok decrypt=ok compare=ok" \
	/tmp/optee-pvm-linux.log; then
	echo "COEX_PVM_LINUX_TA_FAILED: rc=${guest_rc}"
	exit 14
fi
echo "COEX_PVM_LINUX_TA_OK"

# Create two independent FF-A endpoints concurrently. Each guest opens its own
# TEEC session and completes the 4 KiB operation; neither receives a session
# handle from the other guest.
/usr/bin/lkvm run --name optee-pvm-a --protected --protected-ffa \
	--cpus 1 --mem 384 --network mode=none --console serial \
	--kernel /opt/pvm/Image --initrd /opt/pvm/rootfs.cpio.gz \
	--params "earlycon rdinit=/init" >/tmp/optee-pvm-a.log 2>&1 &
pvm_a_pid=$!
/usr/bin/lkvm run --name optee-pvm-b --protected --protected-ffa \
	--cpus 1 --mem 384 --network mode=none --console serial \
	--kernel /opt/pvm/Image --initrd /opt/pvm/rootfs.cpio.gz \
	--params "earlycon rdinit=/init" >/tmp/optee-pvm-b.log 2>&1 &
pvm_b_pid=$!
wait "${pvm_a_pid}"
pvm_a_rc=$?
wait "${pvm_b_pid}"
pvm_b_rc=$?
cat /tmp/optee-pvm-a.log
cat /tmp/optee-pvm-b.log
if [ "${pvm_a_rc}" -ne 0 ] || [ "${pvm_b_rc}" -ne 0 ] ||
   ! grep -q "PVM_TA_AES_4K_OK" /tmp/optee-pvm-a.log ||
   ! grep -q "PVM_TA_AES_4K_OK" /tmp/optee-pvm-b.log; then
	echo "COEX_TWO_PVM_ISOLATION_FAILED: a=${pvm_a_rc} b=${pvm_b_rc}"
	exit 15
fi
echo "COEX_TWO_PVM_ISOLATION_OK: independent_endpoints=2 independent_sessions=2"

grep '^Mlocked:' /proc/meminfo || true
echo "OPTEE_PKVM_COEX_ALL_OK"
