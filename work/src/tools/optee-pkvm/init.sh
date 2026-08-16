#!/bin/sh

/bin/mount -t devtmpfs devtmpfs /dev
exec /sbin/init
