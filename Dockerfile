## Base image with essential tools
FROM ubuntu:24.04 AS base

COPY scripts/image-cleanup /bin

ENV DEBIAN_FRONTEND=noninteractive

ENV NDK_HOME="/opt/android-ndk-r28b"
ENV ANDROID_NDK="${NDK_HOME}"

ENV HEXAGON_SDK_ROOT="/opt/hexagon/6.3.0.0"
ENV HEXAGON_TOOLS_ROOT="${HEXAGON_SDK_ROOT}/tools/HEXAGON_Tools/19.0.04"
ENV DEFAULT_HLOS_ARCH="64"
ENV DEFAULT_TOOLS_VARIANT="toolv19"
ENV DEFAULT_NO_QURT_INC="0"
ENV DEFAULT_DSP_ARCH="v73"

# Install basic tools & libs
RUN apt-get update && apt-get install -y -q --no-install-recommends \
        rsync wget curl less unzip zip xz-utils tree chrpath \
        openssh-client libatomic1 \
        git git-lfs diffstat ninja-build cmake \
        python3 python3-venv \
        libatomic1 \
    && /bin/image-cleanup

## ARM64 Android build image with intermediate stuff
FROM base AS arm64-android-build

# Add helper scripts
COPY scripts/fetch-and-untar /bin
COPY scripts/fetch-and-unzip /bin
COPY scripts/untar           /bin

# Force bash for everything
RUN ln -fs /bin/bash /bin/sh
ENV SHELL="/bin/bash"

# Install Android NDK
RUN /bin/fetch-and-unzip android-ndk https://dl.google.com/android/repository/android-ndk-r28b-linux.zip /opt

# Install Hexagon SDK
RUN /bin/fetch-and-untar hexagon-sdk https://github.com/snapdragon-toolchain/hexagon-sdk/releases/download/v6.3.0/hexagon-sdk-v6.3.0-amd64-lnx.tar.xz /opt/hexagon

# Install OpenCL headers
RUN /bin/fetch-and-untar opencl-headers https://github.com/KhronosGroup/OpenCL-Headers/archive/refs/tags/v2023.12.14.tar.gz /tmp/opencl \
    && cp -r /tmp/opencl/OpenCL-Headers-2023.12.14/CL /usr/local/include \
    && cp -r /tmp/opencl/OpenCL-Headers-2023.12.14/CL ${NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/include \
    && rm -rf /tmp/opencl

# Install OpenCL hpp
RUN /bin/fetch-and-untar opencl-clhpp https://github.com/KhronosGroup/OpenCL-CLHPP/archive/refs/tags/v2023.12.14.tar.gz /tmp/opencl \
    && cp /tmp/opencl/OpenCL-CLHPP-2023.12.14/include/CL/* /usr/local/include/CL \
    && cp /tmp/opencl/OpenCL-CLHPP-2023.12.14/include/CL/* ${NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/include/CL \
    && rm -rf /tmp/opencl

# Install OpenCL ICD
RUN /bin/fetch-and-untar opencl-icd-loader https://github.com/KhronosGroup/OpenCL-ICD-Loader/archive/refs/tags/v2023.12.14.tar.gz /tmp/opencl \
    && cd /tmp/opencl/OpenCL-ICD-Loader-2023.12.14 \
    && mkdir build_ndk && cd build_ndk \
    && cmake .. -G Ninja -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_TOOLCHAIN_FILE=${NDK_HOME}/build/cmake/android.toolchain.cmake \
    -DOPENCL_ICD_LOADER_HEADERS_DIR=${NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/include \
    -DANDROID_ABI=arm64-v8a \
    -DANDROID_PLATFORM=31 \
    -DANDROID_STL=c++_shared \
    && ninja \
    && cp libOpenCL.so ${NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/aarch64-linux-android \
    && rm -rf /tmp/opencl

# Final ARM64 Android image
FROM base AS arm64-android

# Add helper scripts
COPY --from=arm64-android-build /opt /opt
