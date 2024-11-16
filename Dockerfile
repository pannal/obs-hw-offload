# pull the c bindings
FROM rust AS bindings
RUN cargo install cargo-c

# build the gstreamer plugin
FROM rust AS builder

WORKDIR /app
COPY . /app

ARG DEBIAN_FRONTEND="noninteractive"
SHELL ["/bin/bash", "-c"]
ENV NVIDIA_DRIVER_CAPABILITIES="compute,video,utility"
ENV CARGO_REGISTRIES_CRATES_IO_PROTOCOL="sparse"

COPY --from=bindings /usr/local/cargo/bin /usr/local/cargo/bin

# base and gstreamer
# fixme: probably not everything necessary
RUN apt-get update && apt-get -y install \
    unzip \
    software-properties-common \
    build-essential \
    libssl-dev \
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

# gstreamer ndi plugin
# fixme: might need optimizations (no-clone-submodules?)
#RUN git clone https://gitlab.freedesktop.org/gstreamer/gst-plugins-rs.git && cd gst-plugins-rs/ && $HOME/.cargo/bin/cargo cbuild -p gst-plugin-ndi --prefix=/usr  \
#    && $HOME/.cargo/bin/cargo cinstall -p gst-plugin-ndi --prefix=/usr && $HOME/.cargo/bin/cargo clean && cd .. && rm -rf gst-plugins-rs/
RUN curl -O https://gitlab.freedesktop.org/gstreamer/gst-plugins-rs/-/archive/main/gst-plugins-rs-main.zip && \
    unzip gst-plugins-rs-main.zip && \
    cd gst-plugins-rs-main && \
    cargo cbuild -p gst-plugin-ndi --prefix=/usr && \
    cargo cinstall -p gst-plugin-ndi --prefix=/usr
    # && \
    # cargo clean && \
    # cd .. && \
    # rm -rf gst-plugins-rs-main

# LibNDI
RUN curl -O --output-dir /tmp https://raw.githubusercontent.com/DistroAV/DistroAV/6.0.0/CI/libndi-get.sh && \
    bash /tmp/libndi-get.sh install

# add init.d script for avahi-daemon as its current version only supports systemd and we don't use it
COPY init/avahi-daemon /etc/init.d/avahi-daemon
RUN chmod +x /etc/init.d/avahi-daemon

# RUN rm -rf /var/lib/apt/lists/* && rm -rf ~/.cargo/registry
RUN chmod +x /app/container-startup.sh
ENTRYPOINT ["/app/container-startup.sh"]