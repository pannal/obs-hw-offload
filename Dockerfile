# build the gstreamer ndi plugin
FROM ubuntu:24.10 AS builder

ENV CARGO_REGISTRIES_CRATES_IO_PROTOCOL="sparse"

RUN apt-get update && apt-get -y install \
    rustc \
    cargo \
    curl \
    build-essential \
    libgstreamer1.0-dev \
    libgstreamer-plugins-base1.0-dev

# ENV GST_PLUGINS_COMMIT=main to use the latest commit
ENV GST_PLUGINS_COMMIT=d5425c52251f3fc0c21a6d994f9e1e6b46670daf

RUN cd /opt && \
    curl -O https://gitlab.freedesktop.org/gstreamer/gst-plugins-rs/-/archive/$GST_PLUGINS_COMMIT/gst-plugins-rs-$GST_PLUGINS_COMMIT.tar.bz2 && \
    mkdir gst-plugins-rs-dev && \
    tar -xjvf gst-plugins-rs-$GST_PLUGINS_COMMIT.tar.bz2 --strip-components=1 -C gst-plugins-rs-dev/ gst-plugins-rs-$GST_PLUGINS_COMMIT && \
    cd gst-plugins-rs-dev && \
    cargo build -p gst-plugin-ndi --release


# run
FROM ubuntu:24.10 AS runner
COPY --from=builder /opt/gst-plugins-rs-dev/target/release/*.so /opt/gst-plugins-rs/

WORKDIR /app
COPY . /app

ARG DEBIAN_FRONTEND="noninteractive"
SHELL ["/bin/bash", "-c"]
ENV NVIDIA_DRIVER_CAPABILITIES="compute,video,utility"
ENV GST_PLUGIN_PATH="/opt/gst-plugins-rs"

RUN apt-get update && apt-get -y install \
   sudo \
   curl \
   avahi-daemon \
   gstreamer1.0-plugins-base \
   gstreamer1.0-plugins-good \
   gstreamer1.0-plugins-bad \
   gstreamer1.0-plugins-ugly \
   gstreamer1.0-vaapi \
   gstreamer1.0-plugins-base-apps \
   gstreamer1.0-libav

# LibNDI
# alternatively, get the release .deb from https://github.com/DistroAV/DistroAV/releases
RUN curl -O --output-dir /tmp https://raw.githubusercontent.com/DistroAV/DistroAV/6.0.0/CI/libndi-get.sh
RUN bash /tmp/libndi-get.sh install

RUN rm -rf /var/lib/apt/lists/*
RUN chmod +x /app/container-startup.sh

ENTRYPOINT ["/app/container-startup.sh"]