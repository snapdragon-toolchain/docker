## Base image with essential tools
FROM ubuntu:24.04 AS base

COPY scripts/image-cleanup /bin

ENV DEBIAN_FRONTEND=noninteractive

ENV ANDROID_NDK_ROOT="/opt/android-ndk-r28b"

ENV HEXAGON_SDK_ROOT="/opt/hexagon/6.4.0.2"
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
RUN /bin/fetch-and-untar hexagon-sdk https://github.com/snapdragon-toolchain/hexagon-sdk/releases/download/v6.4.0.2/hexagon-sdk-v6.4.0.2-amd64-lnx.tar.xz /opt/hexagon

# Install OpenCL SDK
ENV OPENCL_REL="2025.07.22"
ENV OPENCL_URL="https://github.com/KhronosGroup/OpenCL"
RUN    /bin/fetch-and-untar opencl-headers    ${OPENCL_URL}-Headers/archive/refs/tags/v${OPENCL_REL}.tar.gz    /tmp/opencl \
    && /bin/fetch-and-untar opencl-clhpp      ${OPENCL_URL}-CLHPP/archive/refs/tags/v${OPENCL_REL}.tar.gz      /tmp/opencl \
    && /bin/fetch-and-untar opencl-icd-loader ${OPENCL_URL}-ICD-Loader/archive/refs/tags/v${OPENCL_REL}.tar.gz /tmp/opencl \
    && cp -r /tmp/opencl/OpenCL-Headers-${OPENCL_REL}/CL ${ANDROID_NDK_ROOT}/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/include \
    && cp -r /tmp/opencl/OpenCL-CLHPP-${OPENCL_REL}/include/CL/* ${ANDROID_NDK_ROOT}/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/include/CL \
    && cd /tmp/opencl/OpenCL-ICD-Loader-${OPENCL_REL} \
    && cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_TOOLCHAIN_FILE=${ANDROID_NDK_ROOT}/build/cmake/android.toolchain.cmake \
    -DOPENCL_ICD_LOADER_HEADERS_DIR=${ANDROID_NDK_ROOT}/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/include \
    -DANDROID_ABI=arm64-v8a  \
    -DANDROID_PLATFORM=31    \
    -DANDROID_STL=c++_shared \
    && cmake --build build   \
    && cp build/libOpenCL.so ${ANDROID_NDK_ROOT}/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/aarch64-linux-android \
    && rm -rf /tmp/opencl

# Final ARM64 Android image
FROM base AS arm64-android

# Add helper scripts
COPY --from=arm64-android-build /opt /opt
