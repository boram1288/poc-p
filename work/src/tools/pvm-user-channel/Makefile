# SPDX-License-Identifier: MIT

CC ?= cc
CFLAGS ?= -O2 -g -Wall -Wextra -Werror -std=gnu11

all: libpvm_user_channel.a libpvm_message.a vsock_smoke

pvm_user_channel.o: pvm_user_channel.c include/pvm_user_channel.h
	$(CC) $(CFLAGS) -I. -c $< -o $@

libpvm_user_channel.a: pvm_user_channel.o
	ar rcs $@ $<

pvm_message.o: pvm_message.c include/pvm_message.h include/pvm_message_uapi.h
	$(CC) $(CFLAGS) -I. -c $< -o $@

libpvm_message.a: pvm_message.o
	ar rcs $@ $<

vsock_smoke: vsock_smoke.c pvm_user_channel.o include/pvm_user_channel.h
	$(CC) $(CFLAGS) -I. vsock_smoke.c pvm_user_channel.o -o $@

test: pvm_user_channel.o tests/protocol_test.c
	$(CC) $(CFLAGS) -I. tests/protocol_test.c pvm_user_channel.o -o tests/protocol_test
	./tests/protocol_test

clean:
	rm -f pvm_user_channel.o pvm_message.o libpvm_user_channel.a libpvm_message.a vsock_smoke tests/protocol_test

.PHONY: all test clean
