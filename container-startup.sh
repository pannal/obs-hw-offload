#!/bin/bash

if [ "$USE_AUTODISCOVERY" == "true" ]
then
  /etc/init.d/dbus start
  avahi-daemon -D
fi

echo "Executing command: '$@'"
exec "$@"