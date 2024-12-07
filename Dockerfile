ARG VERSION=0.1.5

# can be "stock" for ffmpeg from the package manager; "small" to build ffmpeg with VAAPI and NDI support;
# "big" for a more complete ffmpeg build
ARG FF_BUILD=small
ARG FF_BUILDOPTS="--disable-debug --disable-doc"

# the ffmpeg commit to use (the default one has been tested)
ARG FF_COMMIT=018ec4fe5f259253aad8736f9be29b3421a0d3e7

# the gstreamer-plugins-rs commit to use (the default one has been tested)
ARG GST_PLUGINS_COMMIT=39a8db51de014b3f6690c734346c9199101d7ce1

# non-VAAPI intel-specific API to use (OneVPL: gen12+, MSDK: gen8 ~ gen12(Rocket Lake))
ARG INTEL_FF_LIB=OneVPL

# how many threads to use when compiling if not set, $(nproc) is used
ARG COMPILE_CORES


# build the gstreamer ndi plugin
FROM ubuntu:24.10 AS gstpluginbuilder
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
    CARGO_TARGET_DIR=$HOME/lib cargo build -j${COMPILE_CORES:-$(nproc)} -p gst-plugin-ndi --release


# prepare ffmpeg builds
FROM ubuntu:24.10 AS ffbuildbase
ARG FF_COMMIT
ARG TARGETARCH
RUN apt-get update && apt-get -y install git curl

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
    mv `find /tmp -name ndidisk* -type d  | sed 1q` /tmp/ndidisk && \
    cp -r /tmp/ndidisk/ndisdk/include $HOME/ffmpeg_build && \
    cp -r /tmp/ndidisk/ndisdk/lib/$([ "${TARGETARCH}" = "arm64" ] && echo "aarch64-rpi4-linux-gnueabi" || echo "x86_64-linux-gnu") $HOME/ffmpeg_build/lib


# build ffmpeg-small
FROM ubuntu:24.10 AS ffbuilder-small
COPY --from=ffbuildbase /root/ffmpeg_sources /root/ffmpeg_sources
COPY --from=ffbuildbase /root/ffmpeg_build /root/ffmpeg_build

# pull global args
ARG FF_BUILDOPTS
ARG COMPILE_CORES
ARG FF_COMMIT
ARG VERSION
ARG INTEL_FF_LIB
ARG TARGETARCH

RUN apt-get update && apt-get -y install --no-install-recommends software-properties-common && \
    add-apt-repository -y ppa:kobuk-team/intel-graphics && \
    apt-get -y install \
    autoconf \
    automake \
    build-essential \
    cmake \
    git \
    libass-dev \
    libavahi-client3 \
    libavahi-common3 \
    libdrm-dev \
    libfreetype6-dev \
    libgnutls28-dev \
    $(if [ "${TARGETARCH}" != "arm64" ]; then \
        if [ "${INTEL_FF_LIB}" = "MSDK" ]; then echo "libmfx-dev"; else echo "libvpl-dev"; fi; \
    fi) \
    libmp3lame-dev \
    libtool \
    libssl-dev \
    libva-dev \
    libva-glx2 \
    libvorbis-dev \
    libzstd-dev \
    meson \
    nasm \
    ninja-build \
    pkg-config \
    texinfo \
    yasm \
    zlib1g-dev

# build SRT
RUN cd ~/ffmpeg_sources && \
    git clone --depth 1 https://github.com/Haivision/srt.git && \
    mkdir srt/build && \
    cd srt/build && \
    PATH="$HOME/bin:$PATH" PKG_CONFIG_PATH="$HOME/ffmpeg_build/lib/pkgconfig" \
      cmake -DCMAKE_INSTALL_PREFIX="$HOME/ffmpeg_build" -DEXECUTABLE_OUTPUT_PATH="$HOME/bin" \
        -DENABLE_C_DEPS=ON -DENABLE_SHARED=OFF -DENABLE_STATIC=ON .. && \
    make -j${COMPILE_CORES:-$(nproc)} && \
    make install

# build FDK-AAC
RUN cd ~/ffmpeg_sources && \
    git -C fdk-aac pull 2> /dev/null || git clone --depth 1 https://github.com/mstorsjo/fdk-aac && \
    cd fdk-aac && \
    autoreconf -fiv && \
    ./configure --prefix="$HOME/ffmpeg_build" --disable-shared && \
    make -j${COMPILE_CORES:-$(nproc)} && \
    make install

# --enable-vaapi is redundant if the correct dependencies are detected
RUN mkdir $HOME/bin &&  \
    cd ~/ffmpeg_sources/FFmpeg && \
    PATH="$HOME/bin:$PATH" PKG_CONFIG_PATH="$HOME/ffmpeg_build/lib/pkgconfig" ./configure \
      --prefix="$HOME/ffmpeg_build" \
      --pkg-config-flags="--static" \
      --extra-cflags="-I$HOME/ffmpeg_build/include -march=native" \
      --extra-ldflags="-L$HOME/ffmpeg_build/lib" \
      --extra-libs="-lpthread -lm" \
      --extra-version="`echo ${FF_COMMIT} | cut -c 1-7`-oho-${VERSION}" \
      --ld="g++" \
      --bindir="$HOME/bin" \
      ${FF_BUILDOPTS} \
      $(if [ "$TARGETARCH" != "arm64" ]; then \
          if [ "${INTEL_FF_LIB}" = "MSDK" ]; then echo "--enable-libmfx"; else echo "--enable-libvpl"; fi; \
      fi) \
      --enable-libfdk-aac \
      --enable-libndi_newtek \
      --enable-libsrt \
      --enable-vaapi \
      --enable-gpl \
      --enable-version3 \
      --enable-nonfree && \
    PATH="$HOME/bin:$PATH" make -j${COMPILE_CORES:-$(nproc)} && \
    make install


# build ffmpeg-big
FROM ubuntu:24.10 AS ffbuilder-big
COPY --from=ffbuildbase /root/ffmpeg_sources /root/ffmpeg_sources
COPY --from=ffbuildbase /root/ffmpeg_build /root/ffmpeg_build

# set to empty to not build ffplay
ARG FF_FFPLAY_PKG_ADD="libsdl2-dev"

# pull global args
ARG FF_BUILDOPTS
ARG FF_COMMIT
ARG VERSION
ARG COMPILE_CORES
# see https://arnon.dk/matching-sm-architectures-arch-and-gencode-for-various-nvidia-cards/
ARG CUDA_NVCCFLAGS="-gencode arch=compute_75,code=sm_75 -O2"
ARG INTEL_FF_LIB
ARG TARGETARCH

RUN apt-get update && apt-get -y install --no-install-recommends software-properties-common && \
    add-apt-repository -y ppa:kobuk-team/intel-graphics && \
    apt-get -y install \
    autoconf \
    automake \
    build-essential \
    cmake \
    curl \
    git \
    git-core \
    gnutls-bin \
    libass-dev \
    libavahi-client3 \
    libavahi-common3 \
    libdrm-dev \
    libfreetype6-dev \
    libgnutls28-dev \
    $(if [ "${TARGETARCH}" != "arm64" ]; then \
        if [ "${INTEL_FF_LIB}" = "MSDK" ]; then echo "libmfx1 libmfx-dev"; else echo "libvpl2 libvpl-dev"; fi; \
    fi) \
    libmp3lame-dev \
    libnuma-dev \
    libopenjp2-7 \
    libopenjp2-7-dev \
    libopenjpip7 \
    libsmbclient-dev \
    libspeex-dev \
    libspeex1 \
    libspeexdsp-dev \
    libspeexdsp1 \
    libspeex-ocaml \
    libspeex-ocaml-dev \
    libssh-dev \
    libssl-dev \
    libtheora-dev \
    libtheora0 \
    libtheora-ocaml \
    libtheora-ocaml-dev \
    libtool \
    libunistring-dev \
    libva-dev \
    libva-glx2 \
    libvorbis-dev \
    libwebp-dev \
    libwebp7 \
    libwebpdecoder3 \
    libwebpdemux2 \
    libwebpmux3 \
    libzstd-dev \
    meson \
    nasm \
    nvidia-cuda-toolkit \
    ninja-build \
    openssl \
    pkg-config \
    texinfo \
    sudo \
    wget \
    yasm \
    zlib1g-dev ${FF_FFPLAY_PKG_ADD}

# get AMF headers
RUN cd ~/ffmpeg_sources && \
    wget -O amf.tar.gz https://github.com/GPUOpen-LibrariesAndSDKs/AMF/releases/download/v1.4.35/AMF-headers-v1.4.35.tar.gz && \
    tar xvf amf.tar.gz && \
    mkdir $HOME/ffmpeg_build/include/AMF && \
    cp -R amf-headers-v1.4.35/AMF/* $HOME/ffmpeg_build/include/AMF/

# build SRT
RUN cd ~/ffmpeg_sources && \
    git clone --depth 1 https://github.com/Haivision/srt.git && \
    mkdir srt/build && \
    cd srt/build && \
    PATH="$HOME/bin:$PATH" PKG_CONFIG_PATH="$HOME/ffmpeg_build/lib/pkgconfig" \
      cmake -DCMAKE_INSTALL_PREFIX="$HOME/ffmpeg_build" -DEXECUTABLE_OUTPUT_PATH="$HOME/bin" \
        -DENABLE_C_DEPS=ON -DENABLE_SHARED=OFF -DENABLE_STATIC=ON .. && \
    make -j${COMPILE_CORES:-$(nproc)} && \
    make install

# build cuda/nvcc/cuvid/nvenc
RUN cd ~/ffmpeg_sources && \
    wget -O nv.tar.gz https://github.com/FFmpeg/nv-codec-headers/releases/download/n12.2.72.0/nv-codec-headers-12.2.72.0.tar.gz && \
    tar xvf nv.tar.gz && \
    cd nv-codec-headers-12.2.72.0 && \
    make -j${COMPILE_CORES:-$(nproc)} PREFIX="$HOME/ffmpeg_build" BINDIR="$HOME/bin" && \
    make install PREFIX="$HOME/ffmpeg_build" BINDIR="$HOME/bin"

# build libx264
RUN cd ~/ffmpeg_sources && \
    git -C x264 pull 2> /dev/null || git clone --depth 1 https://code.videolan.org/videolan/x264.git && \
    cd x264 && \
    PATH="$HOME/bin:$PATH" PKG_CONFIG_PATH="$HOME/ffmpeg_build/lib/pkgconfig" ./configure --prefix="$HOME/ffmpeg_build" --bindir="$HOME/bin" --enable-static --enable-pic && \
    PATH="$HOME/bin:$PATH" make -j${COMPILE_CORES:-$(nproc)} && \
    make install

# build libx265
RUN cd ~/ffmpeg_sources && \
    wget -O x265.tar.bz2 https://bitbucket.org/multicoreware/x265_git/get/master.tar.bz2 && \
    tar xjvf x265.tar.bz2 && \
    cd multicoreware*/build/linux && \
    PATH="$HOME/bin:$PATH" cmake -G "Unix Makefiles" -DCMAKE_INSTALL_PREFIX="$HOME/ffmpeg_build" \
      -DEXECUTABLE_OUTPUT_PATH="$HOME/bin" -DENABLE_SHARED=off ../../source && \
    PATH="$HOME/bin:$PATH" make -j${COMPILE_CORES:-$(nproc)} && \
    make install

# build libvpx
RUN cd ~/ffmpeg_sources && \
    git -C libvpx pull 2> /dev/null || git clone --depth 1 https://chromium.googlesource.com/webm/libvpx.git && \
    cd libvpx && \
    PATH="$HOME/bin:$PATH" ./configure --prefix="$HOME/ffmpeg_build" --disable-examples --disable-unit-tests --enable-vp9-highbitdepth --as=yasm && \
    PATH="$HOME/bin:$PATH" make -j${COMPILE_CORES:-$(nproc)} && \
    make install

# build FDK-AAC
RUN cd ~/ffmpeg_sources && \
    git -C fdk-aac pull 2> /dev/null || git clone --depth 1 https://github.com/mstorsjo/fdk-aac && \
    cd fdk-aac && \
    autoreconf -fiv && \
    ./configure --prefix="$HOME/ffmpeg_build" --disable-shared && \
    make -j${COMPILE_CORES:-$(nproc)} && \
    make install

# build libopus
RUN cd ~/ffmpeg_sources && \
    git -C opus pull 2> /dev/null || git clone --depth 1 https://github.com/xiph/opus.git && \
    cd opus && \
    ./autogen.sh && \
    ./configure --prefix="$HOME/ffmpeg_build" --disable-shared && \
    make -j${COMPILE_CORES:-$(nproc)} && \
    make install

# build AOM
RUN cd ~/ffmpeg_sources && \
    git -C aom pull 2> /dev/null || git clone --depth 1 https://aomedia.googlesource.com/aom && \
    mkdir -p aom_build && \
    cd aom_build && \
    PATH="$HOME/bin:$PATH" PKG_CONFIG_PATH="$HOME/ffmpeg_build/lib/pkgconfig" cmake -G "Unix Makefiles" \
      -DCMAKE_INSTALL_PREFIX="$HOME/ffmpeg_build" -DEXECUTABLE_OUTPUT_PATH="$HOME/bin" \
      -DENABLE_TESTS=OFF -DENABLE_NASM=on ../aom && \
    PATH="$HOME/bin:$PATH" make -j${COMPILE_CORES:-$(nproc)} && \
    make install

# build libsvtav1
RUN cd ~/ffmpeg_sources && \
    git -C SVT-AV1 pull 2> /dev/null || git clone https://gitlab.com/AOMediaCodec/SVT-AV1.git && \
    mkdir -p SVT-AV1/build && \
    cd SVT-AV1/build && \
    PATH="$HOME/bin:$PATH" PKG_CONFIG_PATH="$HOME/ffmpeg_build/lib/pkgconfig" \
      cmake -G "Unix Makefiles" -DCMAKE_INSTALL_PREFIX="$HOME/ffmpeg_build" -DCMAKE_BUILD_TYPE=Release \
      -DEXECUTABLE_OUTPUT_PATH="$HOME/bin" -DBUILD_DEC=OFF -DBUILD_SHARED_LIBS=OFF .. && \
    PATH="$HOME/bin:$PATH" make -j${COMPILE_CORES:-$(nproc)} && \
    make install

# build Dav1d
RUN cd ~/ffmpeg_sources && \
    git -C dav1d pull 2> /dev/null || git clone --depth 1 https://code.videolan.org/videolan/dav1d.git && \
    mkdir -p dav1d/build && \
    cd dav1d/build && \
    meson setup -Denable_tools=false -Denable_tests=false --default-library=static .. --prefix "$HOME/ffmpeg_build" --libdir="$HOME/ffmpeg_build/lib" && \
    ninja -j${COMPILE_CORES:-$(nproc)} && \
    ninja install

# build libvmaf
RUN cd ~/ffmpeg_sources && \
    wget https://github.com/Netflix/vmaf/archive/v3.0.0.tar.gz && \
    tar xvf v3.0.0.tar.gz && \
    mkdir -p vmaf-3.0.0/libvmaf/build &&\
    cd vmaf-3.0.0/libvmaf/build && \
    meson setup -Denable_tests=false -Denable_docs=false --buildtype=release --default-library=static .. --prefix "$HOME/ffmpeg_build" --bindir="$HOME/bin" --libdir="$HOME/ffmpeg_build/lib" && \
    ninja -j${COMPILE_CORES:-$(nproc)} && \
    ninja install

# --enable-vaapi is redundant if the correct dependencies are detected
# the order of the cuda toolkit is important here, as it provides its own g++ wrapper and we don't want to use that when
# compiling ffmpeg, but we need the path for nvcc; we could otherwise also just set --ld="g++14"
RUN cd ~/ffmpeg_sources/FFmpeg && \
    PATH="$HOME/bin:$PATH:/usr/lib/nvidia-cuda-toolkit/bin" PKG_CONFIG_PATH="$HOME/ffmpeg_build/lib/pkgconfig" ./configure \
      --prefix="$HOME/ffmpeg_build" \
      --pkg-config-flags="--static" \
      --extra-cflags="-I$HOME/ffmpeg_build/include -march=native" \
      --extra-ldflags="-L$HOME/ffmpeg_build/lib" \
      --extra-libs="-lpthread -lm" \
      --extra-version="$(echo ${FF_COMMIT} | cut -c 1-7)-oho-${VERSION}" \
      --ld="g++" \
      --bindir="$HOME/bin" \
      ${FF_BUILDOPTS} \
      --enable-amf \
      --enable-cuda-nvcc \
      --enable-cuda-llvm \
      --enable-cuvid \
      --enable-gpl \
      --enable-gnutls \
      --nvccflags="${CUDA_NVCCFLAGS}" \
      --enable-libaom \
      --enable-libass \
      --enable-libdav1d \
      --enable-libfdk-aac \
      --enable-libfreetype \
      $(if [ "$TARGETARCH" != "arm64" ]; then \
          if [ "${INTEL_FF_LIB}" = "MSDK" ]; then echo "--enable-libmfx"; else echo "--enable-libvpl"; fi; \
      fi) \
      --enable-libmp3lame \
      --enable-libopenjpeg \
      --enable-libopus \
      --enable-libsmbclient \
      --enable-libsrt \
      --enable-libssh \
      --enable-libsvtav1 \
      --enable-libtheora \
      --enable-libvmaf \
      --enable-libvorbis \
      --enable-libvpx \
      --enable-libwebp \
      --enable-libx264 \
      --enable-libx265 \
      --enable-libndi_newtek \
      --enable-nvenc \
      --enable-vaapi \
      --enable-vdpau \
      --enable-version3 \
      --enable-nonfree && \
    PATH="$HOME/bin:$PATH" make -j${COMPILE_CORES:-$(nproc)} && \
    make install


# dummy image for ff stock
FROM ubuntu:24.10 AS ffbuilder-stock
RUN mkdir /root/bin


FROM ffbuilder-${FF_BUILD} as ff


# run
FROM ubuntu:24.10 AS runner
COPY --from=gstpluginbuilder /root/lib/release/*.so /opt/gst-plugins-rs/
COPY --from=ff /root/bin /usr/local/bin

WORKDIR /app
COPY . /app

ARG DEBIAN_FRONTEND="noninteractive"
ENV NVIDIA_VISIBLE_DEVICES="all"
ENV NVIDIA_DRIVER_CAPABILITIES="compute,video,utility"
ENV GST_PLUGIN_PATH="/opt/gst-plugins-rs"
ENV USE_AUTODISCOVERY=false
ARG FF_BUILD
ARG WITH_CUDA
ARG TARGETARCH

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
    gstreamer1.0-libav \
    $([ "${FF_BUILD}" = "stock" ] && echo "ffmpeg") \
    $([ "${WITH_CUDA}" = "true" ] && echo "nvidia-cuda-toolkit") \
    $([ "${FF_BUILD}" = "big" ] && echo "libsmbclient-dev")

# LibNDI
# alternatively, get the release .deb from https://github.com/DistroAV/DistroAV/releases
RUN curl -O --output-dir /tmp https://raw.githubusercontent.com/DistroAV/DistroAV/6.0.0/CI/libndi-get.sh && \
    bash /tmp/libndi-get.sh install && \
    if [ "$TARGETARCH" = "arm64" ]; then \
        cp -P $LIBNDI_TMP/ndisdk/lib/aarch64-rpi4-linux-gnueabi/* /usr/local/lib/; \
    fi

RUN rm -rf /var/lib/apt/lists/*

# prepare entrypoint and possible execute targets
RUN chmod +x /app/container-startup.sh && chmod +x /app/stream.sh && ln -s /app/stream.sh /usr/local/bin/stream

ENTRYPOINT ["/app/container-startup.sh"]