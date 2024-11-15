FROM ubuntu:24.04
WORKDIR /app
COPY . /app
ARG DEBIAN_FRONTEND="noninteractive"
SHELL ["/bin/bash", "-c"]

# base and gstreamer
# fixme: probably not everything necessary
RUN apt-get update && apt-get -y install wget gpg git software-properties-common sudo curl build-essential openssl libssl-dev avahi-daemon libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev \
    gstreamer1.0-plugins-base gstreamer1.0-plugins-good gstreamer1.0-plugins-bad gstreamer1.0-plugins-ugly gstreamer1.0-libav libgstrtspserver-1.0-dev libges-1.0-dev \
    libgstreamer-plugins-bad1.0-dev libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev gstreamer1.0-plugins-base libgstrtspserver-1.0-dev \
    gstreamer1.0-x gstreamer1.0-alsa gstreamer1.0-gl gstreamer1.0-gtk3 gstreamer1.0-plugins-base-apps

# rust/cargo/cargo-c
RUN curl https://sh.rustup.rs -sSf | sh -s -- -y --default-toolchain stable && $HOME/.cargo/bin/cargo install cargo-c

# gstreamer ndi plugin
# fixme: might need optimizations (no-clone-submodules?)
RUN git clone https://gitlab.freedesktop.org/gstreamer/gst-plugins-rs.git && cd gst-plugins-rs/ && $HOME/.cargo/bin/cargo cinstall -p gst-plugin-ndi --prefix=/usr


# LibNDI
RUN wget -q -O /tmp/libndi-get.sh https://raw.githubusercontent.com/DistroAV/DistroAV/424d789317617f144a97fab1f421f9c2818a1d08/CI/libndi-get.sh && bash /tmp/libndi-get.sh install

# add init.d script for avahi-daemon as its current version only supports systemd and we don't use it
COPY init/avahi-daemon /etc/init.d/avahi-daemon
RUN chmod +x /etc/init.d/avahi-daemon

RUN rm -rf /var/lib/apt/lists/*
RUN ["chmod", "+x", "/app/container_startup.sh"]
ENTRYPOINT ["/app/container_startup.sh"]
