# can be "stock" for ffmpeg from the package manager; "small" to build ffmpeg with VAAPI and NDI support;
# "full" for a complete ffmpeg build
ARG FF_BUILD=small

# the ffmpeg commit to use (the default one has been tested)
ARG FF_COMMIT=78c4d6c136e10222a0b0ddff639c836f295a9029
ARG FF_BUILDOPTS=--disable-debug

# the ffmpeg commit to use (the default one has been tested)
ARG GST_PLUGINS_COMMIT=d5425c52251f3fc0c21a6d994f9e1e6b46670daf

# how many threads to use when compiling if not set, `nproc` is used
ARG COMPILE_CORES


# build the gstreamer ndi plugin
FROM ubuntu:24.10 AS builder
ENV CARGO_REGISTRIES_CRATES_IO_PROTOCOL="sparse"
ARG GST_PLUGINS_COMMIT

RUN apt-get update && apt-get -y install \
    rustc \
    cargo \
    curl \
    build-essential \
    libgstreamer1.0-dev \
    libgstreamer-plugins-base1.0-dev

RUN cd /opt && \
    curl -O https://gitlab.freedesktop.org/gstreamer/gst-plugins-rs/-/archive/${GST_PLUGINS_COMMIT}/gst-plugins-rs-${GST_PLUGINS_COMMIT}.tar.bz2 && \
    mkdir gst-plugins-rs-dev && \
    tar -xjvf gst-plugins-rs-${GST_PLUGINS_COMMIT}.tar.bz2 --strip-components=1 -C gst-plugins-rs-dev/ gst-plugins-rs-${GST_PLUGINS_COMMIT} && \
    cd gst-plugins-rs-dev && \
    cargo build -j${COMPILE_CORES:-`nproc`} -p gst-plugin-ndi --release


# prepare ffmpeg builds
FROM ubuntu:24.10 AS ffbuildbase
ARG FF_COMMIT
RUN apt-get update && apt-get -y install git curl && \
    apt-get -y install --no-install-recommends dpkg-dev

RUN mkdir -p ~/ffmpeg_sources &&  \
    cd ~/ffmpeg_sources && \
    git clone -b dev/7.0 --single-branch https://gitlab.fem-net.de/broadcast/ffmpeg-patches.git && \
    curl -LJO https://github.com/FFmpeg/FFmpeg/archive/${FF_COMMIT}.tar.gz && \
    mkdir FFmpeg && \
    tar -xvf FFmpeg-${FF_COMMIT}.tar.gz --strip-components=1 -C FFmpeg/ && \
    cd FFmpeg && \
    patch -p1 < ../ffmpeg-patches/decklink-use-device-numbers.patch && \
    patch -p1 < ../ffmpeg-patches/ndi-support.patch


# https://downloads.ndi.tv/SDK/NDI_SDK_Linux/Install_NDI_SDK_v6_Linux.tar.gz
RUN curl -O --output-dir /tmp https://raw.githubusercontent.com/DistroAV/DistroAV/6.0.0/CI/libndi-get.sh && \
    bash /tmp/libndi-get.sh nocleanup && \
    mkdir $HOME/ffmpeg_build && \
    cp -r `find /tmp -name ndidisk* -type d  | sed 1q`/ndisdk/include $HOME/ffmpeg_build && \
    cp -r `find /tmp -name ndidisk* -type d  | sed 1q`/ndisdk/lib/$(dpkg-architecture -q DEB_HOST_MULTIARCH) $HOME/ffmpeg_build/lib


# build ffmpeg-small
FROM ubuntu:24.10 AS ffbuilder-small
COPY --from=ffbuildbase /root/ffmpeg_sources /root/ffmpeg_sources
COPY --from=ffbuildbase /root/ffmpeg_build /root/ffmpeg_build
ARG FF_BUILDOPTS
ARG COMPILE_CORES

RUN apt-get update && apt-get -y install software-properties-common && \
    add-apt-repository -y ppa:kobuk-team/intel-graphics && \
    apt-get -y install \
    autoconf \
    automake \
    build-essential \
    cmake \
    libass-dev \
    libavahi-client3 \
    libavahi-common3 \
    libdrm-dev \
    libfreetype6-dev \
    libgnutls28-dev \
    libmp3lame-dev \
    libtool \
    libva-dev \
    libva-glx2 \
    libvorbis-dev \
    meson \
    nasm \
    ninja-build \
    pkg-config \
    texinfo \
    yasm \
    zlib1g-dev

# --enable-vaapi is redundant if the correct dependencies are detected
RUN mkdir ~/bin &&  \
    cd ~/ffmpeg_sources/FFmpeg && \
    PATH="$HOME/bin:$PATH" PKG_CONFIG_PATH="$HOME/ffmpeg_build/lib/pkgconfig" ./configure \
      --prefix="$HOME/ffmpeg_build" \
      --pkg-config-flags="--static" \
      --extra-cflags="-I$HOME/ffmpeg_build/include" \
      --extra-ldflags="-L$HOME/ffmpeg_build/lib" \
      --extra-libs="-lpthread -lm" \
      --ld="g++" \
      --bindir="$HOME/bin" \
      ${FF_BUILDOPTS} \
      --enable-libndi_newtek \
      --enable-vaapi \
      --enable-nonfree && \
    PATH="$HOME/bin:$PATH" make -j${COMPILE_CORES:-`nproc`} && \
    make install


# build ffmpeg-full
FROM ubuntu:24.10 AS ffbuilder-full
COPY --from=ffbuildbase /root/ffmpeg_sources /root/ffmpeg_sources
COPY --from=ffbuildbase /root/ffmpeg_build /root/ffmpeg_build
ARG FF_BUILDOPTS
ARG COMPILE_CORES

RUN apt-get update && apt-get -y install software-properties-common && \
    add-apt-repository -y ppa:kobuk-team/intel-graphics && \
    apt-get -y install \
    autoconf \
    automake \
    build-essential \
    cmake \
    curl \
    git \
    git-core \
    libass-dev \
    libavahi-client3 \
    libavahi-common3 \
    libdrm-dev \
    libfreetype6-dev \
    libgnutls28-dev \
    libmp3lame-dev \
    libtool \
    libva-dev \
    libva-glx2 \
    libvorbis-dev \
    meson \
    nasm \
    ninja-build \
    pkg-config \
    texinfo \
    wget \
    yasm \
    zlib1g-dev

# --enable-vaapi is redundant if the correct dependencies are detected
RUN cd ~/ffmpeg_sources/FFmpeg && \
    PATH="$HOME/bin:$PATH" PKG_CONFIG_PATH="$HOME/ffmpeg_build/lib/pkgconfig" ./configure \
      --prefix="$HOME/ffmpeg_build" \
      --pkg-config-flags="--static" \
      --extra-cflags="-I$HOME/ffmpeg_build/include" \
      --extra-ldflags="-L$HOME/ffmpeg_build/lib" \
      --extra-libs="-lpthread -lm" \
      --ld="g++" \
      --bindir="$HOME/bin" \
      ${FF_BUILDOPTS} \
      --enable-libndi_newtek \
      --enable-vaapi \
      --enable-nonfree && \
    PATH="$HOME/bin:$PATH" make -j${COMPILE_CORES:-`nproc`} && \
    make install


# dummy image for ff stock
FROM ubuntu:24.10 AS ffbuilder-stock
RUN mkdir /root/bin


FROM ffbuilder-${FF_BUILD} as ff


# run
FROM ubuntu:24.10 AS runner
COPY --from=builder /opt/gst-plugins-rs-dev/target/release/*.so /opt/gst-plugins-rs/
COPY --from=ff /root/bin /usr/local/bin

WORKDIR /app
COPY . /app

ARG DEBIAN_FRONTEND="noninteractive"
SHELL ["/bin/bash", "-c"]
ENV NVIDIA_DRIVER_CAPABILITIES="compute,video,utility"
ENV GST_PLUGIN_PATH="/opt/gst-plugins-rs"
ENV USE_AUTODISCOVERY=false
ARG FF_BUILD
ENV FF_BUILD=$FF_BUILD

RUN apt-get update && apt-get -y install software-properties-common && \
    add-apt-repository -y ppa:kobuk-team/intel-graphics

RUN apt-get -y install \
    sudo \
    curl \
    avahi-daemon \
    libze-intel-gpu1  \
    libze1  \
    intel-ocloc  \
    intel-opencl-icd  \
    clinfo \
    intel-media-va-driver-non-free  \
    libmfx1  \
    libmfx-gen1.2  \
    libvpl2  \
    libvpl-tools  \
    libva-glx2  \
    va-driver-all  \
    vainfo \
    gstreamer1.0-plugins-base \
    gstreamer1.0-plugins-good \
    gstreamer1.0-plugins-bad \
    gstreamer1.0-plugins-ugly \
    gstreamer1.0-vaapi \
    gstreamer1.0-plugins-base-apps \
    gstreamer1.0-libav && \
    if [ "${FF_BUILD}" = "stock" ]; then apt-get -y install ffmpeg; fi

# LibNDI
# alternatively, get the release .deb from https://github.com/DistroAV/DistroAV/releases
RUN curl -O --output-dir /tmp https://raw.githubusercontent.com/DistroAV/DistroAV/6.0.0/CI/libndi-get.sh && \
   bash /tmp/libndi-get.sh install

RUN rm -rf /var/lib/apt/lists/*
RUN chmod +x /app/container-startup.sh

ENTRYPOINT ["/app/container-startup.sh"]