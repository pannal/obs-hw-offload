# obs-hw-offload
### Headless gstreamer-based NDI®-to-RTMP with VAAPI HW transcoding

## Introduction
Ever wondered why you have an Intel CPU with QuickSync capabilities in your network, or a server with an Arc GPU, but you're still using your gaming
machine's resources to transcode your video when streaming?

This solves that. The best example is using OBS with DistroAV to send a mostly lossless video/audio stream to the GStreamer
NDI input, transcoding it using VAAPI and sending it to your RTMP target (custom RTMP, Twitch etc.).

### Note
This still uses `vaapih264enc` which is "deprecated" since GStreamer 1.22, but it's much more stable than `vah264lpenc` (or `vah264enc`, untested) right now. This might change in the future.

## Requirements
* VAAPI-compatible hardware/driver on host OS
  * `clinfo |grep "Device Name"` should return something
* host networking (for the moment; due to avahi-daemon)
* Something sending NDI streams, such as OBS DistroAV


## Building
`docker build . -t obs-hw-offload`


## Discovering NDI sources
`docker run --network=host obs-hw-offload gst-device-monitor-1.0 -f Source/Network:application/x-ndi`


# Examples
### Note:
* Replace `NDI_SOURCE_NAME` with the NDI source name from [Discovering NDI sources](#discovering-ndi-sources)
* Alternatively, use for example `url-address="192.168.0.10:5961"` instead of `ndi-name=""` to skip auto discovery
* Replace `rtmp://your_server/streamkey` with your rtmp target

#### VBR h264 resize to 1080p, high quality, 12mbit
```docker run --network=host --rm --name=obs-hw-offload --device /dev/dri/renderD128:/dev/dri/renderD128 obs-hw-offload gst-launch-1.0 ndisrc ndi-name="NDI_SOURCE_NAME" timeout=100000 connect-timeout=100000 ! ndisrcdemux name=demux demux.video ! videoconvert ! vaapipostproc width=1920 height=1080 ! vaapih264enc rate-control=cbr bitrate=12000 keyframe-period=30 quality-level=2 cabac=true init-qp=36 ! h264parse ! queue ! mux. demux.audio ! audioconvert ! audioresample ! avenc_aac ! queue ! mux. flvmux name=mux streamable=true ! rtmpsink location="rtmp://your_server/streamkey live=1"```

#### CBR h264 original resolution, default quality, 24mbit
```docker run --network=host --rm --name=obs-hw-offload --device /dev/dri/renderD128:/dev/dri/renderD128 obs-hw-offload gst-launch-1.0 ndisrc ndi-name="NDI_SOURCE_NAME" timeout=100000 connect-timeout=100000 ! ndisrcdemux name=demux demux.video ! videoconvert ! vaapih264enc rate-control=cbr bitrate=24000 keyframe-period=30 ! h264parse ! queue ! mux. demux.audio ! audioconvert ! audioresample ! avenc_aac ! queue ! mux. flvmux name=mux streamable=true ! rtmpsink location="rtmp://your_server/streamkey live=1"```

# License

[NDI® is a registered trademark of Vizrt NDI AB](https://ndi.video/)

# Links
[ndi.video](https://ndi.video/)