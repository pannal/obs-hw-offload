# obs-hw-offload
### GStreamer-based NDI-to-RTMP with VAAPI HW transcoding

## Introduction
Ever wondered why you have an Intel CPU with QuickSync capabilities in your network, or a server with an Arc GPU, but you're still using your gaming
machine's resources to transcode your video when streaming?

This solves that. The best example is using OBS with DistroAV to send a mostly lossless video/audio stream to the GStreamer
NDI input, transcoding it using VAAPI and sending it to your RTMP target (custom RTMP, Twitch etc.).

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
## Note:
* Replace `NDI_SOURCE_NAME` with the NDI source name from [Discovering NDI sources](#discovering-ndi-sources)
* Replace `rtmp://your_server/streamkey` with your rtmp target

### VBR h264 resize to 1080p, high quality, 12mbit, using an Intel Arc A380
```docker run --network=host --device /dev/dri/renderD128:/dev/dri/renderD128 obs-hw-offload gst-launch-1.0 ndisrc ndi-name="NDI_SOURCE_NAME" timeout=100000 connect-timeout=100000 ! ndisrcdemux name=demux demux.video ! videoconvert ! vaapipostproc width=1920 height=1080 ! vaapih264enc rate-control=cbr bitrate=12000 keyframe-period=30 quality-level=2 cabac=true init-qp=36 ! h264parse ! queue ! mux. demux.audio ! audioconvert ! audioresample ! avenc_aac ! queue ! mux. flvmux name=mux streamable=true ! rtmpsink location="rtmp://your_server/streamkey live=1"```

### CBR h264 original resolution, default quality, using an Intel Arc A380
```docker run --network=host --device /dev/dri/renderD128:/dev/dri/renderD128 obs-hw-offload gst-launch-1.0 ndisrc ndi-name="NDI_SOURCE_NAME" timeout=100000 connect-timeout=100000 ! ndisrcdemux name=demux demux.video ! videoconvert ! vaapih264enc rate-control=cbr bitrate=24000 keyframe-period=30 ! h264parse ! queue ! mux. demux.audio ! audioconvert ! audioresample ! avenc_aac ! queue ! mux. flvmux name=mux streamable=true ! rtmpsink location="rtmp://your_server/streamkey live=1"```
