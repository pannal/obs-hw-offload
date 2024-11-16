#!/bin/bash

/etc/init.d/dbus start
avahi-daemon -D

echo "Executing command: '$@'"
exec "$@"