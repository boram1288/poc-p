/* SPDX-License-Identifier: GPL-2.0-only */

	.text
	.balign 16
	.global _start
_start:
	/* x0 is the MMIO GPA/GVA selected by the KVM backend. */
	mov	x20, x0

	/* ARM_SMCCC_VENDOR_HYP_KVM_MMIO_GUARD_INFO_FUNC_ID = 0xc6000005 */
	movz	x0, #0x0005
	movk	x0, #0xc600, lsl #16
	hvc	#0
	mov	x9, #4096
	cmp	x0, x9
	b.ne	.Lfailed

	/* ARM_SMCCC_VENDOR_HYP_KVM_MMIO_GUARD_ENROLL_FUNC_ID = 0xc6000006 */
	movz	x0, #0x0006
	movk	x0, #0xc600, lsl #16
	mov	x1, #0
	hvc	#0
	cbnz	x0, .Lfailed

	/* ARM_SMCCC_VENDOR_HYP_KVM_MMIO_GUARD_MAP_FUNC_ID = 0xc6000007 */
	movz	x0, #0x0007
	movk	x0, #0xc600, lsl #16
	mov	x1, x20
	mov	x2, #3
	hvc	#0
	cbnz	x0, .Lfailed

	/* "PVMSTART" in little-endian memory order. */
	movz	x9, #0x5650
	movk	x9, #0x534d, lsl #16
	movk	x9, #0x4154, lsl #32
	movk	x9, #0x5452, lsl #48
	str	x9, [x20]

	/* "PVMDONE!" in little-endian memory order. */
	movz	x9, #0x5650
	movk	x9, #0x444d, lsl #16
	movk	x9, #0x4e4f, lsl #32
	movk	x9, #0x2145, lsl #48
	str	x9, [x20]

.Lhang:
	wfe
	b	.Lhang
.Lfailed:
	/* An invalid MMIO access is intentionally avoided before guard setup. */
	brk	#0
	b	.Lfailed
