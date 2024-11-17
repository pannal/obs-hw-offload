# pull the c-bindings
FROM rust AS bindings
RUN cargo install cargo-c


# build the gstreamer ndi plugin
FROM rust AS builder
COPY --from=bindings /usr/local/cargo/bin /usr/local/cargo/bin

ENV CARGO_REGISTRIES_CRATES_IO_PROTOCOL="sparse"

RUN apt-get update && apt-get -y install \
    build-essential \
    libgstreamer1.0-dev \
    libgstreamer-plugins-base1.0-dev

# GST_PLUGINS_COMMIT=main to use the latest commit
ENV GST_PLUGINS_COMMIT=d5425c52251f3fc0c21a6d994f9e1e6b46670daf

RUN cd /opt && \
    curl -O https://gitlab.freedesktop.org/gstreamer/gst-plugins-rs/-/archive/$GST_PLUGINS_COMMIT/gst-plugins-rs-$GST_PLUGINS_COMMIT.tar.bz2 && \
    mkdir gst-plugins-rs-dev && \
    tar -xjvf gst-plugins-rs-$GST_PLUGINS_COMMIT.tar.bz2 --strip-components=1 -C gst-plugins-rs-dev/ gst-plugins-rs-$GST_PLUGINS_COMMIT && \
    cd gst-plugins-rs-dev && \
    cargo cbuild -p gst-plugin-ndi --release


# run
FROM ubuntu:24.04 AS runner
COPY --from=builder /opt/gst-plugins-rs-dev/target /opt/gst-plugins-rs/target

WORKDIR /app
COPY . /app

ARG DEBIAN_FRONTEND="noninteractive"
SHELL ["/bin/bash", "-c"]
ENV NVIDIA_DRIVER_CAPABILITIES="compute,video,utility"

RUN apt-get update && apt-get -y install \
   pkg-config \
   sudo \
   curl \
   avahi-daemon \
   libgstreamer1.0-dev \
   libgstreamer-plugins-base1.0-dev \
   gstreamer1.0-plugins-base \
   gstreamer1.0-plugins-good \
   gstreamer1.0-plugins-bad \
   gstreamer1.0-plugins-ugly \
   gstreamer1.0-vaapi \
   gstreamer1.0-plugins-base-apps \
   gstreamer1.0-libav

RUN sudo install -m 755 /opt/gst-plugins-rs/target/*/release/*.so $(pkg-config --variable=pluginsdir gstreamer-1.0)/

# LibNDI
# alternatively, get the release .deb from https://github.com/DistroAV/DistroAV/releases
RUN curl -O --output-dir /tmp https://raw.githubusercontent.com/DistroAV/DistroAV/6.0.0/CI/libndi-get.sh && \
   bash /tmp/libndi-get.sh install

RUN rm -rf /var/lib/apt/lists/*
RUN chmod +x /app/container-startup.sh

ENTRYPOINT ["/app/container-startup.sh"]