# obs-hw-offload
### Headless gstreamer-based NDI® OBS offloading with VAAPI HW transcoding

## Introduction
Ever wondered why you have an Intel CPU with QuickSync capabilities in your network, or a server with an Arc GPU, but you're still using your gaming
machine's resources to transcode your video when streaming?

Are you trying to find a capture card to fit your needs, don't want to compromise on HDMI passthrough, or simply want to use DisplayPort?

You've got an older Laptop with an Intel CPU with an iGPU that's just lying around, not utilized?

This can help. 

The best example would be using OBS with DistroAV to send a virtually lossless video/audio stream to the GStreamer
NDI input, transcoding it using VAAPI and sending it to your RTMP target (custom RTMP, Twitch etc.).

E.g.: Distributed, headless OBS encoding/transcoding/streaming.

### Note
For now this project is just a container built with the right environment to do what it claims. It's in proof-of-concept stage. At a certain point this is likely to become software, at least to simplify the command line.

This still uses `vaapih264/5enc` which is "deprecated" since GStreamer 1.22, but it's much more performant than the low-power/non-shader-based`vah264/5lpenc` (`vah264/5enc` would be preferred but isn't always available) right now. This might change in the future.

## Requirements
* VAAPI-compatible hardware/driver on host OS
  * `clinfo |grep "Device Name"` should return something
* Something sending NDI streams, such as OBS DistroAV
* Optional: host networking (only when auto discovery is used)


### Bandwidth
With DistroAV, which still uses NDI SpeedHQ, the following network bandwidth can be expected:
* 1080p60: ~130 Mbit/s
* 2160p60: ~250 Mbit/s

Ref: https://ndi.video/tech/formats/


## Status/Testing (help needed)
- [x] Intel Arc A380
  - Ubuntu 24.04 LTS host machine, OBS Studio 30.2.3, Windows 10 64, DistroAV 6.0.0 (SDK 6.0.1.0)
    - [x] h264 vaapih264enc, RTMP
    - [x] h265 vaapih265enc, RTMP
- [x] Intel N100 iGPU (Alder Lake, Intel® UHD Graphics)
  - Debian 12 host machine on Proxmox (lxc, 6.2.16-4-pve), OBS Studio 30.2.3, MacOS 15.1, DistroAV 6.0.0 (SDK 6.0.1.0)
    - [x] h264 vaapih264enc, RTMP
    - [x] h265 vaapih264enc, RTMP
- [ ] AMD GPU (likely to just work)
- [ ] NVIDIA GPU (might just work)
- [ ] AMD iGPU




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
```docker run -it --rm --name=obs-hw-offload --device /dev/dri/renderD128:/dev/dri/renderD128 obs-hw-offload gst-launch-1.0 ndisrc SOURCE timeout=100000 connect-timeout=100000 ! ndisrcdemux name=demux demux.video ! videoconvert ! vaapipostproc width=1920 height=1080 ! vaapih264enc rate-control=cbr bitrate=12000 keyframe-period=30 quality-level=2 cabac=true init-qp=36 ! h264parse ! queue ! mux. demux.audio ! audioconvert ! audioresample ! avenc_aac ! queue ! mux. flvmux name=mux streamable=true ! rtmpsink location="rtmp://your_server/streamkey live=1"```

#### CBR h264 original resolution, default quality, 24mbit
```docker run -it --rm --name=obs-hw-offload --device /dev/dri/renderD128:/dev/dri/renderD128 obs-hw-offload gst-launch-1.0 ndisrc SOURCE timeout=100000 connect-timeout=100000 ! ndisrcdemux name=demux demux.video ! videoconvert ! vaapih264enc rate-control=cbr bitrate=24000 keyframe-period=30 ! h264parse ! queue ! mux. demux.audio ! audioconvert ! audioresample ! avenc_aac ! queue ! mux. flvmux name=mux streamable=true ! rtmpsink location="rtmp://your_server/streamkey live=1"```

#### The above with host networking and auto discovery
```docker run --network-mode host --env USE_AUTODISCOVERY=true -it --rm --name=obs-hw-offload --device /dev/dri/renderD128:/dev/dri/renderD128 obs-hw-offload gst-launch-1.0 ndisrc SOURCE timeout=100000 connect-timeout=100000 ! ndisrcdemux name=demux demux.video ! videoconvert ! vaapih264enc rate-control=cbr bitrate=24000 keyframe-period=30 ! h264parse ! queue ! mux. demux.audio ! audioconvert ! audioresample ! avenc_aac ! queue ! mux. flvmux name=mux streamable=true ! rtmpsink location="rtmp://your_server/streamkey live=1"```

#### Use FFMPEG for RTMP output (it supports Enhanced RTMP and thus HEVC/AV1)
```docker run -it --rm --name=obs-hw-offload --device /dev/dri/renderD128:/dev/dri/renderD128 obs-hw-offload /bin/bash -c "mkfifo /tmp/gst_output_pipe && gst-launch-1.0 ndisrc SOURCE timeout=100000 connect-timeout=100000 ! ndisrcdemux name=demux demux.video ! videoconvert ! vaapipostproc width=1920 height=1080 ! vaapih264enc rate-control=cbr bitrate=24000 keyframe-period=30  !  h264parse ! queue ! mux. demux.audio ! audioconvert ! audioresample ! avenc_aac ! queue ! mux. matroskamux name=mux ! filesink location=/tmp/gst_output_pipe | ffmpeg -fflags nobuffer -i /tmp/gst_output_pipe -c:v copy -c:a copy -f flv rtmp://your_server/streamkey"```

#### Use FFMPEG for RTMP output, exiting properly when GStreamer exits (no input in time)
```docker run -it --rm --name=obs-hw-offload --device /dev/dri/renderD128:/dev/dri/renderD128 obs-hw-offload /bin/bash -c "mkfifo /tmp/gst_output_pipe && (gst-launch-1.0 ndisrc SOURCE timeout=1000 connect-timeout=100000 ! ndisrcdemux name=demux demux.video ! videoconvert ! vaapih265enc rate-control=vbr bitrate=12000 keyframe-period=30 ! h265parse ! queue ! mux. demux.audio ! audioconvert ! audioresample ! avenc_aac ! queue ! mux. matroskamux name=mux ! filesink location=/tmp/gst_output_pipe || rm /tmp/gst_output_pipe) & ffmpeg -fflags nobuffer -i /tmp/gst_output_pipe -c:v copy -c:a copy -f flv rtmp://your_server/streamkey; rm /tmp/gst_output_pipe"```

#### VBR HEVC resize to 1080p, high quality, 12mbit
```docker run -it --rm --name=obs-hw-offload --device /dev/dri/renderD128:/dev/dri/renderD128 obs-hw-offload /bin/bash -c "mkfifo /tmp/gst_output_pipe && gst-launch-1.0 ndisrc SOURCE timeout=100000 connect-timeout=100000 ! ndisrcdemux name=demux demux.video ! videoconvert ! vaapipostproc width=1920 height=1080 ! vaapih265enc rate-control=vbr bitrate=12000 keyframe-period=30  !  h265parse ! queue ! mux. demux.audio ! audioconvert ! audioresample ! avenc_aac ! queue ! mux. matroskamux name=mux ! filesink location=/tmp/gst_output_pipe | ffmpeg -fflags nobuffer -i /tmp/gst_output_pipe -c:v copy -c:a copy -f flv rtmp://your_server/streamkey"```


### Additional snippets for adjusting the pipeline
#### Specific framerates (for media files), add after `! videoconvert`
###### 30 fps
`! videorate ! video/x-raw, framerate=30/1`
###### 23.976 fps
`! videorate ! video/x-raw, framerate=24000/1001`
###### ~29.976 fps
`! videorate ! video/x-raw, framerate=30000/1001`
###### =29.976 fps
`! videorate ! video/x-raw, framerate=29976/1000`

#### Pipeline buffering (should not be necessary in a stable local network)
Replace `queue` with for example `queue max-size-time=500000000 max-size-buffers=5 max-size-bytes=0` or `queue leaky=downstream`, `queue leaky=upstream`


#### Debugging
###### GStreamer
Prepend `gst-launch-1.0` with `GST_DEBUG=3 `

###### FFMPEG
Add parameter `-loglevel debug` after `ffmpeg` command


# Further documentation
[GStreamer VAAPI](https://gstreamer.freedesktop.org/documentation/vaapi/index.html?gi-language=c)

[GStreamer VA](https://gstreamer.freedesktop.org/documentation/va/index.html?gi-language=c)

[GStreamer Tutorials](https://gstreamer.freedesktop.org/documentation/tutorials/index.html?gi-language=c)

# License

[NDI® is a registered trademark of Vizrt NDI AB](https://ndi.video/)

# Links
[ndi.video](https://ndi.video/)