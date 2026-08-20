/* SPDX-License-Identifier: GPL-2.0-only */

	.text
	.balign 16
	.global _start
_start:
	/*
	 * x0: runner marker MMIO, x1: assigned edu MMIO (zero when absent),
	 * x2: pvIOMMU id, x3: virtual StreamID, x4: DMA buffer IPA/IOVA.
	 */
	mov	x20, x0
	mov	x21, x1
	mov	x22, x2
	mov	x23, x3
	mov	x24, x4
	mov	x19, #0

	/* ARM_SMCCC_VENDOR_HYP_KVM_MMIO_GUARD_INFO_FUNC_ID = 0xc6000005 */
	mov	x19, #16
	movz	x0, #0x0005
	movk	x0, #0xc600, lsl #16
	mov	x1, #0
	mov	x2, #0
	mov	x3, #0
	hvc	#0
	mov	x9, #4096
	cmp	x0, x9
	b.ne	.Lfailed

	/* ARM_SMCCC_VENDOR_HYP_KVM_MMIO_GUARD_ENROLL_FUNC_ID = 0xc6000006 */
	mov	x19, #17
	movz	x0, #0x0006
	movk	x0, #0xc600, lsl #16
	mov	x1, #0
	hvc	#0
	cbnz	x0, .Lfailed

	/* ARM_SMCCC_VENDOR_HYP_KVM_MMIO_GUARD_MAP_FUNC_ID = 0xc6000007 */
	mov	x19, #18
	movz	x0, #0x0007
	movk	x0, #0xc600, lsl #16
	mov	x1, x20
	mov	x2, #3
	mov	x3, #0
	mov	x4, #0
	mov	x5, #0
	mov	x6, #0
	hvc	#0
	cbnz	x0, .Lfailed

	/* AI role has no assigned device in the first assignment test. */
	cbz	x21, .Lstarted

	/* Request exclusive DMA ownership: DEV_REQ_DMA = 0xc600003d. */
	mov	x19, #1
	/* A route for the other pVM's virtual StreamID must not exist here. */
	movz	x0, #0x003d
	movk	x0, #0xc600, lsl #16
	mov	x1, x22
	eor	x2, x23, #8
	mov	x3, #0
	mov	x4, #0
	mov	x5, #0
	mov	x6, #0
	hvc	#0
	adds	x0, x0, #3
	cbnz	x0, .Lfailed

	movz	x0, #0x003d
	movk	x0, #0xc600, lsl #16
	mov	x1, x22
	mov	x2, x23
	mov	x3, #0
	mov	x4, #0
	mov	x5, #0
	mov	x6, #0
	hvc	#0
	cbnz	x0, .Lfailed

	/* Allocate a guest-owned pvIOMMU domain: PVIOMMU_OP(ALLOC_DOMAIN). */
	mov	x19, #2
	movz	x0, #0x003e
	movk	x0, #0xc600, lsl #16
	mov	x1, #2
	mov	x2, #0
	mov	x3, #0
	mov	x4, #0
	mov	x5, #0
	mov	x6, #0
	hvc	#0
	cbnz	x0, .Lfailed
	mov	x25, x1

	/* Attach the assigned StreamID to the new domain. */
	mov	x19, #3
	movz	x0, #0x003e
	movk	x0, #0xc600, lsl #16
	mov	x1, #0
	mov	x2, x22
	mov	x3, x23
	mov	x4, #0
	mov	x5, x25
	mov	x6, #0
	hvc	#0
	cbnz	x0, .Lfailed

	/* Materialize the allowed and denied CPU pages before DMA validation. */
	movz	x26, #0x7788
	movk	x26, #0x5566, lsl #16
	movk	x26, #0x3344, lsl #32
	movk	x26, #0x1122, lsl #48
	str	x26, [x24]
	add	x27, x24, #4096
	movz	x28, #0xbabe
	movk	x28, #0xcafe, lsl #16
	movk	x28, #0xbad0, lsl #32
	movk	x28, #0x0dd0, lsl #48
	str	x28, [x27]
	mov	x16, #0x200000
	add	x15, x16, #4096

	/* Map exactly one page for DMA with READ|WRITE permissions. */
	mov	x19, #4
	mov	x12, #16
.Lmap_dma_retry:
	movz	x0, #0x003e
	movk	x0, #0xc600, lsl #16
	mov	x1, #4
	mov	x2, x25
	mov	x3, x16
	mov	x4, x24
	mov	x5, #4096
	mov	x6, #3
	hvc	#0
	cbnz	x0, .Lfailed
	cbnz	x1, .Lmap_dma_done
	subs	x12, x12, #1
	b.ne	.Lmap_dma_retry
	b	.Lfailed
.Lmap_dma_done:
	mov	x9, #4096
	mov	x0, x1
	cmp	x0, x9
	b.ne	.Lfailed

	/* Authorize the first assigned-device MMIO page in the guest. */
	mov	x19, #5
	movz	x0, #0x0007
	movk	x0, #0xc600, lsl #16
	mov	x1, x21
	mov	x2, #3
	mov	x3, #0
	mov	x4, #0
	mov	x5, #0
	mov	x6, #0
	hvc	#0
	cbnz	x0, .Lfailed

	/* Minimal in-pVM driver probe: QEMU edu identification register. */
	mov	x19, #6
	ldr	w9, [x21]
	movz	w10, #0x00ed
	movk	w10, #0x0100, lsl #16
	mov	w0, w9
	cmp	w0, w10
	b.ne	.Lfailed

	/* Normal DMA: guest page -> edu private buffer. */
	mov	x19, #7
	str	x16, [x21, #0x80]
	mov	x9, #0x40000
	str	x9, [x21, #0x88]
	mov	x9, #8
	str	x9, [x21, #0x90]
	mov	x9, #1
	str	x9, [x21, #0x98]
	bl	.Lwait_dma

	/* Normal DMA: edu private buffer -> the same authorized page. */
	mov	x19, #8
	str	xzr, [x24]
	mov	x9, #0x40000
	str	x9, [x21, #0x80]
	str	x16, [x21, #0x88]
	mov	x9, #8
	str	x9, [x21, #0x90]
	mov	x9, #3
	str	x9, [x21, #0x98]
	bl	.Lwait_dma
	ldr	x9, [x24]
	cmp	x9, x26
	b.ne	.Lfailed

	/* Negative control: the adjacent page was never mapped in the IOMMU. */
	mov	x19, #9
	mov	x9, #0x40000
	str	x9, [x21, #0x80]
	str	x15, [x21, #0x88]
	mov	x9, #8
	str	x9, [x21, #0x90]
	mov	x9, #3
	str	x9, [x21, #0x98]
	bl	.Lwait_dma
	ldr	x9, [x27]
	cmp	x9, x28
	b.ne	.Lfailed

	/* Phase 08 peer sharing uses the physical edu SID as receiver identity. */
	movz	x14, #0x3038
	movk	x14, #0x4544, lsl #16
	movk	x14, #0x4152, lsl #32
	movk	x14, #0x5348, lsl #48	/* 0x5348415245443038 */
	mov	x9, #0x10
	cmp	x23, x9
	b.ne	.Laccept_shared_dma

	/* Camera owns the page and grants one read-only DMA page to SID 0x18. */
	mov	x19, #10
	str	x14, [x24]
	movz	x0, #0x0032
	movk	x0, #0xc600, lsl #16
	mov	x1, #0			/* KVM_PVM_DMA_SHARE_GRANT */
	mov	x2, x24
	mov	x3, #4096
	mov	x4, #0x18
	mov	x5, #0
	mov	x6, #0
	hvc	#0
	cbnz	x0, .Lfailed
	cmp	x1, #1
	b.ne	.Lfailed
	b	.Lstarted

.Laccept_shared_dma:
	/* A route not assigned to AI must not be accepted as the receiver. */
	mov	x19, #11
	mov	x17, #0x300000
	movz	x0, #0x0032
	movk	x0, #0xc600, lsl #16
	mov	x1, #1			/* KVM_PVM_DMA_SHARE_ACCEPT */
	mov	x2, #1
	mov	x3, x25
	mov	x4, x22
	mov	x5, #0x10
	mov	x6, x17
	hvc	#0
	adds	x0, x0, #3
	cbnz	x0, .Lfailed

	/* AI accepts token 1 into its own domain at a dedicated read-only IOVA. */
	mov	x19, #12
.Laccept_shared_dma_retry:
	movz	x0, #0x0032
	movk	x0, #0xc600, lsl #16
	mov	x1, #1			/* KVM_PVM_DMA_SHARE_ACCEPT */
	mov	x2, #1
	mov	x3, x25
	mov	x4, x22
	mov	x5, x23
	mov	x6, x17
	hvc	#0
	cbnz	x0, .Lfailed
	mov	x9, #4096
	cmp	x1, x9
	b.ne	.Laccept_shared_dma_retry

	/* Device reads Camera memory directly, then copies it into AI memory. */
	mov	x19, #13
	str	x17, [x21, #0x80]
	mov	x9, #0x50000
	str	x9, [x21, #0x88]
	mov	x9, #8
	str	x9, [x21, #0x90]
	mov	x9, #1
	str	x9, [x21, #0x98]
	bl	.Lwait_dma
	str	xzr, [x24]
	mov	x9, #0x50000
	str	x9, [x21, #0x80]
	str	x16, [x21, #0x88]
	mov	x9, #8
	str	x9, [x21, #0x90]
	mov	x9, #3
	str	x9, [x21, #0x98]
	bl	.Lwait_dma
	ldr	x9, [x24]
	cmp	x9, x14
	b.ne	.Lfailed

	/* Replace the edu private buffer so stale data cannot satisfy revoke. */
	movz	x13, #0xa55a
	movk	x13, #0xa55a, lsl #16
	movk	x13, #0xa55a, lsl #32
	movk	x13, #0xa55a, lsl #48
	str	x13, [x24]
	str	x16, [x21, #0x80]
	mov	x9, #0x50000
	str	x9, [x21, #0x88]
	mov	x9, #8
	str	x9, [x21, #0x90]
	mov	x9, #1
	str	x9, [x21, #0x98]
	bl	.Lwait_dma

.Lstarted:
	/* "PVMSTART" in little-endian memory order. */
	movz	x9, #0x5650
	movk	x9, #0x534d, lsl #16
	movk	x9, #0x4154, lsl #32
	movk	x9, #0x5452, lsl #48
	str	x9, [x20]

	/* No assigned device (x21 zero): nothing to verify post-revoke. */
	cbz	x21, .Lcompleted

	/* Camera teardown revokes the grant before the controller resumes AI. */
	mov	x9, #0x18
	cmp	x23, x9
	b.ne	.Lcompleted
	mov	x19, #14
	movz	x0, #0x0032
	movk	x0, #0xc600, lsl #16
	mov	x1, #2			/* KVM_PVM_DMA_SHARE_QUERY */
	mov	x2, #1
	mov	x3, #0
	mov	x4, #0
	mov	x5, #0
	mov	x6, #0
	hvc	#0
	adds	x0, x0, #3		/* SMCCC_RET_INVALID_PARAMETER */
	cbnz	x0, .Lfailed

	/* Actual post-revoke DMA must not reproduce the Camera marker. */
	mov	x19, #15
	str	x17, [x21, #0x80]
	mov	x9, #0x50000
	str	x9, [x21, #0x88]
	mov	x9, #8
	str	x9, [x21, #0x90]
	mov	x9, #1
	str	x9, [x21, #0x98]
	bl	.Lwait_dma
	str	xzr, [x24]
	mov	x9, #0x50000
	str	x9, [x21, #0x80]
	str	x16, [x21, #0x88]
	mov	x9, #8
	str	x9, [x21, #0x90]
	mov	x9, #3
	str	x9, [x21, #0x98]
	bl	.Lwait_dma
	ldr	x9, [x24]
	cmp	x9, x14
	b.eq	.Lfailed

.Lcompleted:
	/* "PVMDONE!" in little-endian memory order. */
	movz	x9, #0x5650
	movk	x9, #0x444d, lsl #16
	movk	x9, #0x4e4f, lsl #32
	movk	x9, #0x2145, lsl #48
	str	x9, [x20]

.Lhang:
	wfe
	b	.Lhang

.Lwait_dma:
	movz	x11, #0xffff
	movk	x11, #0x00ff, lsl #16
.Lwait_dma_loop:
	ldr	x9, [x21, #0x98]
	tbz	x9, #0, .Lwait_dma_done
	subs	x11, x11, #1
	b.ne	.Lwait_dma_loop
	b	.Lfailed
.Lwait_dma_done:
	ret
.Lfailed:
	/* Report (step << 32) | SMCCC result to the runner. */
	lsl	x19, x19, #32
	mov	w0, w0
	orr	x19, x19, x0
	str	x19, [x20]
	b	.Lfailed
