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
* Something sending NDI streams, such as OBS DistroAV
* Optional: host networking (only when auto discovery is used)


## Installation
Either:
* Build it yourself or
* [Get it from DockerHub](https://hub.docker.com/repository/docker/pannal/obs-hw-offload/general)

## Building
`docker build . -t obs-hw-offload`


## Basic setup

### Direct connection (default):
* Use `SOURCE` as `url-address="ip:5961"` while replacing `ip` with the IP of your OBS source host


### With host-networking, autodiscovery:

###### Discovering NDI sources
`docker run --network=host obs-hw-offload gst-device-monitor-1.0 -f Source/Network:application/x-ndi`

* Use `SOURCE` as `ndi-name="SOURCE_NAME"` with the NDI source name from the previous step in the examples below (default source name is: `YOUR_PC_NAME (OBS)` for DistroAV)
* Run the examples below with `--network=host` and `--env USE_AUTODISCOVERY=true`



## Persistance

When we don't receive output from an NDI source for 100s, the container exits. To automatically listen for sources for another 100s, simply add `--restart unless-stopped` to the container run parameters.

## Available codecs/encoders
###### All
```docker run -it --rm --entrypoint gst-inspect-1.0 --device /dev/dri/renderD128:/dev/dri/renderD128 pannal/obs-hw-offload```

###### VA/VAAPI
```docker run -it --rm --entrypoint gst-inspect-1.0 --device /dev/dri/renderD128:/dev/dri/renderD128 pannal/obs-hw-offload |grep va```


# Examples
### Note:
* Replace `SOURCE` with the result of the [Basic setup step](#basic-setup)
* Replace `rtmp://your_server/streamkey` with your rtmp target
* Replace the image name `obs-hw-offload` with `pannal/obs-hw-offload` if you want to use the one prebuilt on DockerHub 

#### VBR h264 resize to 1080p, high quality, 12mbit
```docker run --rm --name=obs-hw-offload --device /dev/dri/renderD128:/dev/dri/renderD128 obs-hw-offload gst-launch-1.0 ndisrc SOURCE timeout=100000 connect-timeout=100000 ! ndisrcdemux name=demux demux.video ! videoconvert ! vaapipostproc width=1920 height=1080 ! vaapih264enc rate-control=cbr bitrate=12000 keyframe-period=30 quality-level=2 cabac=true init-qp=36 ! h264parse ! queue ! mux. demux.audio ! audioconvert ! audioresample ! avenc_aac ! queue ! mux. flvmux name=mux streamable=true ! rtmpsink location="rtmp://your_server/streamkey live=1"```

#### CBR h264 original resolution, default quality, 24mbit
```docker run --rm --name=obs-hw-offload --device /dev/dri/renderD128:/dev/dri/renderD128 obs-hw-offload gst-launch-1.0 ndisrc SOURCE timeout=100000 connect-timeout=100000 ! ndisrcdemux name=demux demux.video ! videoconvert ! vaapih264enc rate-control=cbr bitrate=24000 keyframe-period=30 ! h264parse ! queue ! mux. demux.audio ! audioconvert ! audioresample ! avenc_aac ! queue ! mux. flvmux name=mux streamable=true ! rtmpsink location="rtmp://your_server/streamkey live=1"```

#### The above with host networking and auto discovery
```docker run --network-mode host --env USE_AUTODISCOVERY=true --rm --name=obs-hw-offload --device /dev/dri/renderD128:/dev/dri/renderD128 obs-hw-offload gst-launch-1.0 ndisrc SOURCE timeout=100000 connect-timeout=100000 ! ndisrcdemux name=demux demux.video ! videoconvert ! vaapih264enc rate-control=cbr bitrate=24000 keyframe-period=30 ! h264parse ! queue ! mux. demux.audio ! audioconvert ! audioresample ! avenc_aac ! queue ! mux. flvmux name=mux streamable=true ! rtmpsink location="rtmp://your_server/streamkey live=1"```


# License

[NDI® is a registered trademark of Vizrt NDI AB](https://ndi.video/)

# Links
[ndi.video](https://ndi.video/)