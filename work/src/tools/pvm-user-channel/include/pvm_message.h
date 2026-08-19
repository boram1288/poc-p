/* SPDX-License-Identifier: MIT */
#ifndef PVM_MESSAGE_H
#define PVM_MESSAGE_H

#include <stdint.h>

int pvm_message_open(void);
int pvm_message_send(int fd, uint32_t peer_endpoint, const void *data,
		     uint32_t length, uint64_t *sequence);
int pvm_message_receive(int fd, uint32_t expected_sender, void *data,
			uint32_t capacity, uint32_t *length,
			uint64_t *sequence, uint32_t timeout_ms);
int pvm_message_depth(int fd, uint32_t *count, uint32_t *capacity);

#endif
