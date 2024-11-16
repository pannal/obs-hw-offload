# pull the c-bindings
FROM rust AS bindings
RUN cargo install cargo-c


# build the gstreamer ndi plugin
FROM rust AS builder
COPY --from=bindings /usr/local/cargo/bin /usr/local/cargo/bin

ENV CARGO_REGISTRIES_CRATES_IO_PROTOCOL="sparse"

RUN apt-get update && apt-get -y install \
    git \
    build-essential \
    libgstreamer1.0-dev \
    libgstreamer-plugins-base1.0-dev

RUN cd /opt && \
    git clone --depth 1 https://gitlab.freedesktop.org/gstreamer/gst-plugins-rs.git && \
    cd gst-plugins-rs && \
    cargo cbuild -p gst-plugin-ndi --release


# run
FROM debian:12 AS runner
COPY --from=builder /opt/gst-plugins-rs/target /opt/gst-plugins-rs/target

WORKDIR /app
COPY . /app

ARG DEBIAN_FRONTEND="noninteractive"
SHELL ["/bin/bash", "-c"]
ENV NVIDIA_DRIVER_CAPABILITIES="compute,video,utility"

# fixme: probably not everything necessary
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