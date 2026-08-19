/* SPDX-License-Identifier: GPL-2.0-only */

	.text
	.balign 16
	.global _start
_start:
	/* x0: marker MMIO, x1: role (0 Camera, 1 AI), x2: target endpoint ID,
	 * x3: the page-aligned lease IPA.
	 */
	mov	x20, x0
	mov	x21, x1
	mov	x22, x2
	mov	x23, x3
	mov	x28, x4
	mov	x19, #0
	mov	x29, #0
	adr	x9, .Lvectors
	msr	vbar_el1, x9
	msr	daifclr, #2
	isb

	/* Make the runner marker page available as guarded MMIO. */
	mov	x19, #1
	movz	x0, #0x0005
	movk	x0, #0xc600, lsl #16
	mov	x1, #0
	mov	x2, #0
	mov	x3, #0
	mov	x4, #0
	mov	x5, #0
	mov	x6, #0
	hvc	#0
	mov	x9, #4096
	cmp	x0, x9
	b.ne	.Lfailed

	mov	x19, #2
	movz	x0, #0x0006
	movk	x0, #0xc600, lsl #16
	mov	x1, #0
	hvc	#0
	cbnz	x0, .Lfailed

	mov	x19, #3
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

	/* pKVM endpoint identity is assigned by the VM manager start order. */
	mov	x19, #13
	movz	x0, #0x0032
	movk	x0, #0xc600, lsl #16
	mov	x1, #9			/* ID_GET */
	mov	x2, #0
	mov	x3, #0
	mov	x4, #0
	mov	x5, #0
	mov	x6, #0
	hvc	#0
	cbnz	x0, .Lfailed
	mov	x9, #2
	sub	x9, x9, x21		/* AI=1, Camera=2 */
	cmp	x1, x9
	b.ne	.Lfailed

	cbnz	x21, .Lai

	/* Camera materializes and exports one guest-owned page to the AI pVM. */
	mov	x19, #4
	movz	x25, #0x3039
	movk	x25, #0x5241, lsl #16
	movk	x25, #0x4d45, lsl #32
	movk	x25, #0x4341, lsl #48	/* "CAMERA09" */
	str	x25, [x23]
	movz	x0, #0x0032
	movk	x0, #0xc600, lsl #16
	mov	x1, #3			/* EXPORT */
	mov	x2, x23
	mov	x3, x22
	mov	x4, #4096
	mov	x5, #0
	mov	x6, #0
	hvc	#0
	cbnz	x0, .Lfailed
	mov	x24, x1
	cbz	x24, .Lfailed

	/* The owner is not the selected receiver and cannot consume the event. */
	mov	x19, #5
	movz	x0, #0x0032
	movk	x0, #0xc600, lsl #16
	mov	x1, #8			/* EVENT_POLL */
	mov	x2, #0
	mov	x3, #0
	mov	x4, #0
	mov	x5, #0
	mov	x6, #0
	hvc	#0
	adds	x0, x0, #3
	cbnz	x0, .Lfailed

	bl	.Lstarted
	cmp	x28, #1
	b.ne	.Lcamera_not_owner_fault

	/* Negative mode: wait for AI import, then prove owner access faults. */
	mov	x19, #14
	movz	x27, #0xffff
	movk	x27, #0x00ff, lsl #16
.Lcamera_wait_import:
	movz	x0, #0x0032
	movk	x0, #0xc600, lsl #16
	mov	x1, #7			/* LEASE_QUERY */
	mov	x2, x24
	mov	x3, #0
	mov	x4, #0
	mov	x5, #0
	mov	x6, #0
	hvc	#0
	cbnz	x0, .Lfailed
	cbnz	x1, .Lcamera_owner_access
	subs	x27, x27, #1
	b.ne	.Lcamera_wait_import
	b	.Lfailed
.Lcamera_owner_access:
	ldr	x9, [x23]		/* Must terminate KVM_RUN with an access fault. */
	b	.Lfailed

.Lcamera_not_owner_fault:
	cmp	x28, #3
	b.ne	.Lcamera_normal_wait

	/* Timeout mode: receiver never imports, so owner explicitly revokes. */
	mov	x19, #15
	movz	x27, #0xffff
	movk	x27, #0x000f, lsl #16
.Lcamera_timeout:
	subs	x27, x27, #1
	b.ne	.Lcamera_timeout
	movz	x0, #0x0032
	movk	x0, #0xc600, lsl #16
	mov	x1, #6			/* REVOKE */
	mov	x2, x24
	mov	x3, #0
	mov	x4, #0
	mov	x5, #0
	mov	x6, #0
	hvc	#0
	cbnz	x0, .Lfailed
	ldr	x9, [x23]
	cmp	x9, x25
	b.ne	.Lfailed
	movz	x9, #0x4954
	movk	x9, #0x454d, lsl #16
	movk	x9, #0x554f, lsl #32
	movk	x9, #0x2154, lsl #48	/* "TIMEOUT!" */
	str	x9, [x20]
	b	.Lcompleted

	/* Wait entirely through EL2 until AI returns the lease. */
.Lcamera_normal_wait:
	mov	x19, #6
	movz	x27, #0xffff
	movk	x27, #0x00ff, lsl #16
.Lcamera_wait_return:
	movz	x0, #0x0032
	movk	x0, #0xc600, lsl #16
	mov	x1, #7			/* LEASE_QUERY */
	mov	x2, x24
	mov	x3, #0
	mov	x4, #0
	mov	x5, #0
	mov	x6, #0
	hvc	#0
	cbnz	x0, .Lcamera_returned
	subs	x27, x27, #1
	b.ne	.Lcamera_wait_return
	b	.Lfailed
.Lcamera_returned:
	adds	x0, x0, #3
	cbnz	x0, .Lfailed

	/* Ownership and the original IPA are restored after RETURN. */
	mov	x19, #7
	movz	x26, #0x3039
	movk	x26, #0x4952, lsl #16
	movk	x26, #0x5345, lsl #32
	movk	x26, #0x525f, lsl #48	/* "R_ESIR09" opaque AI marker */
	ldr	x9, [x23]
	cmp	x9, x26
	b.ne	.Lfailed
	movz	x9, #0x4143
	movk	x9, #0x524d, lsl #16
	movk	x9, #0x4145, lsl #32
	movk	x9, #0x4f5f, lsl #48	/* Camera read evidence */
	str	x9, [x20]
	b	.Lcompleted

.Lai:
	/* AI becomes runnable before Camera exports; no Host wakeup is needed. */
	bl	.Lstarted
	cmp	x28, #3
	b.eq	.Lhang			/* Timeout mode intentionally ignores the event. */
	mov	x19, #8
	movz	x27, #0xffff
	movk	x27, #0x00ff, lsl #16
.Lai_poll:
	movz	x0, #0x0032
	movk	x0, #0xc600, lsl #16
	mov	x1, #8			/* EVENT_POLL */
	mov	x2, #0
	mov	x3, #0
	mov	x4, #0
	mov	x5, #0
	mov	x6, #0
	hvc	#0
	cbz	x0, .Lai_event
	adds	x0, x0, #3
	b.ne	.Lfailed
	subs	x27, x27, #1
	b.ne	.Lai_poll
	b	.Lfailed
.Lai_event:
	cmp	x29, #1
	b.ne	.Lfailed
	mov	x29, #0
	mov	x24, x1
	cbz	x24, .Lfailed

	/* Import the same physical backing at an AI-local IPA. */
	mov	x19, #9
	movz	x0, #0x0032
	movk	x0, #0xc600, lsl #16
	mov	x1, #4			/* IMPORT */
	mov	x2, x24
	mov	x3, x23
	mov	x4, #0
	mov	x5, #0
	mov	x6, #0
	hvc	#0
	cbnz	x0, .Lfailed
	mov	x9, #4096
	cmp	x1, x9
	b.ne	.Lfailed

	/* Read Camera marker and write the AI result into the same page. */
	mov	x19, #10
	movz	x25, #0x3039
	movk	x25, #0x5241, lsl #16
	movk	x25, #0x4d45, lsl #32
	movk	x25, #0x4341, lsl #48
	ldr	x9, [x23]
	cmp	x9, x25
	b.ne	.Lfailed
	movz	x26, #0x3039
	movk	x26, #0x4952, lsl #16
	movk	x26, #0x5345, lsl #32
	movk	x26, #0x525f, lsl #48
	str	x26, [x23]
	movz	x9, #0x4941
	movk	x9, #0x525f, lsl #16
	movk	x9, #0x5f57, lsl #32
	movk	x9, #0x4b4f, lsl #48	/* AI read/write evidence */
	str	x9, [x20]
	cbnz	x28, .Lhang		/* Keep the lease for owner-fault teardown. */

	/* Return ownership, then prove that the consumed token is stale. */
	mov	x19, #11
	movz	x0, #0x0032
	movk	x0, #0xc600, lsl #16
	mov	x1, #5			/* RETURN */
	mov	x2, x24
	mov	x3, #0
	mov	x4, #0
	mov	x5, #0
	mov	x6, #0
	hvc	#0
	cbnz	x0, .Lfailed

	mov	x19, #12
	movz	x0, #0x0032
	movk	x0, #0xc600, lsl #16
	mov	x1, #4			/* stale IMPORT */
	mov	x2, x24
	mov	x3, x23
	mov	x4, #0
	mov	x5, #0
	mov	x6, #0
	hvc	#0
	adds	x0, x0, #3
	cbnz	x0, .Lfailed
	b	.Lcompleted

.Lstarted:
	movz	x9, #0x5650
	movk	x9, #0x534d, lsl #16
	movk	x9, #0x4154, lsl #32
	movk	x9, #0x5452, lsl #48	/* PVMSTART */
	str	x9, [x20]
	ret

.Lcompleted:
	movz	x9, #0x5650
	movk	x9, #0x444d, lsl #16
	movk	x9, #0x4e4f, lsl #32
	movk	x9, #0x2145, lsl #48	/* PVMDONE! */
	str	x9, [x20]
.Lhang:
	wfe
	b	.Lhang

.Lfailed:
	lsl	x19, x19, #32
	mov	w0, w0
	orr	x19, x19, x0
	str	x19, [x20]
	b	.Lfailed

	.balign 2048
	.macro vector target
	b	\target
	.space 124
	.endm
.Lvectors:
	.rept 4
	vector	.Lexception
	vector	.Lirq
	vector	.Lhang
	vector	.Lhang
	.endr

.Lexception:
	/* Only the owner-fault mode expects a synchronous data abort. */
	cbz	x28, .Lhang
	cbnz	x21, .Lhang
	movz	x9, #0x574f
	movk	x9, #0x524e, lsl #16
	movk	x9, #0x425f, lsl #32
	movk	x9, #0x4b4c, lsl #48	/* "OWNER_BLK" */
	str	x9, [x20]
	b	.Lhang

.Lirq:
	cbz	x21, .Lhang
	mov	x29, #1
	eret
