FROM ubuntu:24.04
WORKDIR /app
COPY . /app
ARG DEBIAN_FRONTEND="noninteractive"
SHELL ["/bin/bash", "-c"]
ENV NVIDIA_DRIVER_CAPABILITIES="compute,video,utility"

# base and gstreamer
# fixme: probably not everything necessary
RUN apt-get update && apt-get -y install wget unzip software-properties-common build-essential libssl-dev sudo curl avahi-daemon libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev \
    gstreamer1.0-plugins-base gstreamer1.0-plugins-good gstreamer1.0-plugins-bad gstreamer1.0-plugins-ugly gstreamer1.0-vaapi gstreamer1.0-plugins-base-apps gstreamer1.0-libav

# rust/cargo/cargo-c
RUN curl https://sh.rustup.rs -sSf | sh -s -- -y && $HOME/.cargo/bin/cargo install cargo-c

# gstreamer ndi plugin
# fixme: might need optimizations (no-clone-submodules?)
RUN wget https://gitlab.freedesktop.org/gstreamer/gst-plugins-rs/-/archive/main/gst-plugins-rs-main.zip && unzip gst-plugins-rs-main.zip  && cd gst-plugins-rs-main  \
    && $HOME/.cargo/bin/cargo cbuild -p gst-plugin-ndi --prefix=/usr && $HOME/.cargo/bin/cargo cinstall -p gst-plugin-ndi --prefix=/usr && $HOME/.cargo/bin/cargo clean && cd .. && rm -rf gst-plugins-rs-main/


# LibNDI
RUN wget -q -O /tmp/libndi-get.sh https://raw.githubusercontent.com/DistroAV/DistroAV/424d789317617f144a97fab1f421f9c2818a1d08/CI/libndi-get.sh && bash /tmp/libndi-get.sh install

# add init.d script for avahi-daemon as its current version only supports systemd and we don't use it
COPY init/avahi-daemon /etc/init.d/avahi-daemon
RUN chmod +x /etc/init.d/avahi-daemon

RUN rm -rf /var/lib/apt/lists/* && rm -rf ~/.cargo/registry
RUN chmod +x /app/container-startup.sh
ENTRYPOINT ["/app/container-startup.sh"]
