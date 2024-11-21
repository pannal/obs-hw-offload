#!/bin/bash

if [ "$USE_AUTODISCOVERY" == "true" ]
then
  /etc/init.d/dbus start
  avahi-daemon -D
fi

mkfifo /tmp/gst_output_pipe

echo "Executing command: '$@'"
exec "$@"