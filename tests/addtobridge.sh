#!/usr/bin/env bash
# Bring the QEMU TAP device up and add it to the bridge
ip link set "$1" master vmbridge
ip link set "$1" up
