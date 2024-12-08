#!/bin/bash

if [ "$USE_AUTODISCOVERY" == "true" ]
then
  /etc/init.d/dbus start
  avahi-daemon -D
fi

echo "Downloading newest stream.sh version (image version: ${VERSION})"
# always download the latest version of stream.sh, regardless of the image version
curl -o /app/scripts/stream.sh -sLJO "https://raw.githubusercontent.com/pannal/obs-hw-offload/refs/heads/master/scripts/stream.sh" >/dev/null 2>&1

echo "Executing command: '$@'"
exec "$@"
