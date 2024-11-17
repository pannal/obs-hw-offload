FROM alpine:3.20

WORKDIR /app
COPY . /app

ENV NVIDIA_DRIVER_CAPABILITIES="compute,video,utility"

RUN apk add --no-cache \
    gstreamer \
    gstreamer-tools \
    gst-plugins-base \
    gst-plugins-good \
    gst-plugins-bad \
    gst-plugins-ugly \
    gst-vaapi \
    gst-libav \
    intel-media-driver \
    jack \
    gcompat \
    sudo \
    dbus \
    avahi \
    bash \
    curl

RUN apk add --no-cache -X http://dl-cdn.alpinelinux.org/alpine/edge/community gst-plugins-rs-ndi

# LibNDI
SHELL ["/bin/bash", "-c"]
RUN curl -O --output-dir /tmp https://raw.githubusercontent.com/DistroAV/DistroAV/6.0.0/CI/libndi-get.sh
RUN chmod +x /tmp/libndi-get.sh

# dumb workaround, ldconfig fails without a path in apline
RUN sed -i 's/ldconfig/ldconfig \/usr\/local\/lib/g' /tmp/libndi-get.sh

RUN /tmp/libndi-get.sh install
RUN rm /tmp/libndi-get.sh

RUN chmod +x /app/container-startup.sh
ENTRYPOINT ["/app/container-startup.sh"]