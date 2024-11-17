#!/bin/bash

mkdir -p /var/run/dbus
dbus-daemon --system

avahi-daemon -D

echo "Executing command: '$@'"
exec "$@"