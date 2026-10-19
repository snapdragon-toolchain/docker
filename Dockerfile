### Base layer (Debian Trixie)

FROM debian:trixie AS base

ENV DEBIAN_FRONTEND=noninteractive

ARG ANDROID_NDK_VERSION="r29"
ARG HEXAGON_SDK_VERSION="6.7.0.0"
ARG OPENCL_REL="2025.07.22"
ARG LLVM_VERSION="21"
ENV ANDROID_NDK_VERSION=${ANDROID_NDK_VERSION}
ENV HEXAGON_SDK_VERSION=${HEXAGON_SDK_VERSION}
ENV OPENCL_REL=${OPENCL_REL}
ENV LLVM_VERSION=${LLVM_VERSION}

ENV ANDROID_NDK_ROOT="/opt/android-ndk-${ANDROID_NDK_VERSION}"
ENV HEXAGON_SDK_ROOT="/opt/hexagon/${HEXAGON_SDK_VERSION}"
ENV HEXAGON_TOOLS_ROOT="${HEXAGON_SDK_ROOT}/tools/HEXAGON_Tools/21.0.04"
ENV OPENCL_URL="https://github.com/KhronosGroup/OpenCL"

ENV DEFAULT_HLOS_ARCH="64"
ENV DEFAULT_TOOLS_VARIANT="toolv19"
ENV DEFAULT_NO_QURT_INC="0"
ENV DEFAULT_DSP_ARCH="v73"

# Add helper scripts
COPY scripts/fetch-and-untar /bin
COPY scripts/fetch-and-unzip /bin
COPY scripts/untar           /bin
COPY scripts/image-cleanup   /bin

# Force bash for everything
RUN ln -fs /bin/bash /bin/sh
ENV SHELL="/bin/bash"

# Install basic tools & libs
RUN apt-get update && apt-get install -y -q --no-install-recommends \
        lsb-release rsync wget curl less unzip zip xz-utils tree chrpath \
        openssh-client gpg libatomic1 \
        git git-lfs diffstat ninja-build cmake \
        python3 python3-venv \
        vim android-tools-adb \
    && /bin/image-cleanup

# Install clang/llvm tools & libs
RUN cd /tmp && wget https://apt.llvm.org/llvm.sh \
    && chmod +x llvm.sh && ./llvm.sh ${LLVM_VERSION} \
    && update-alternatives --install /usr/bin/clang   clang    /usr/bin/clang-${LLVM_VERSION} 100 \
                           --slave   /usr/bin/clang++ clang++  /usr/bin/clang++-${LLVM_VERSION}

# Install Hexagon SDK
RUN /bin/fetch-and-untar hexagon-sdk https://github.com/snapdragon-toolchain/hexagon-sdk/releases/download/v${HEXAGON_SDK_VERSION}/hexagon-sdk-v${HEXAGON_SDK_VERSION}-amd64-lnx.tar.xz /opt/hexagon

### Build stages

## Android arm64 build stage with intermediate stuff
FROM base AS arm64-android-build

# Install Android NDK
RUN /bin/fetch-and-unzip android-ndk https://dl.google.com/android/repository/android-ndk-${ANDROID_NDK_VERSION}-linux.zip /opt

# Install OpenCL SDK
RUN    /bin/fetch-and-untar opencl-headers    ${OPENCL_URL}-Headers/archive/refs/tags/v${OPENCL_REL}.tar.gz    /tmp/opencl \
    && /bin/fetch-and-untar opencl-clhpp      ${OPENCL_URL}-CLHPP/archive/refs/tags/v${OPENCL_REL}.tar.gz      /tmp/opencl \
    && /bin/fetch-and-untar opencl-icd-loader ${OPENCL_URL}-ICD-Loader/archive/refs/tags/v${OPENCL_REL}.tar.gz /tmp/opencl \
    && cp -r /tmp/opencl/OpenCL-Headers-${OPENCL_REL}/CL         ${ANDROID_NDK_ROOT}/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/include    \
    && cp -r /tmp/opencl/OpenCL-CLHPP-${OPENCL_REL}/include/CL/* ${ANDROID_NDK_ROOT}/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/include/CL \
    && cd /tmp/opencl/OpenCL-ICD-Loader-${OPENCL_REL}     \
    && cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_TOOLCHAIN_FILE=${ANDROID_NDK_ROOT}/build/cmake/android.toolchain.cmake \
    -DOPENCL_ICD_LOADER_HEADERS_DIR=${ANDROID_NDK_ROOT}/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/include \
    -DANDROID_ABI=arm64-v8a  \
    -DANDROID_PLATFORM=31    \
    -DANDROID_STL=c++_shared \
    && cmake --build build   \
    && cp build/libOpenCL.so ${ANDROID_NDK_ROOT}/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/aarch64-linux-android \
    && rm -rf /tmp/opencl

## Debian arm64 build stage with intermediate stuff
FROM base AS arm64-debian-build

# Install cross-build essentials
RUN apt-get update && apt-get install -y -q --no-install-recommends \
    cross-config crossbuild-essential-arm64

# Install OpenCL SDK (cross-compiled for aarch64-linux)
RUN    /bin/fetch-and-untar opencl-headers    ${OPENCL_URL}-Headers/archive/refs/tags/v${OPENCL_REL}.tar.gz    /tmp/opencl \
    && /bin/fetch-and-untar opencl-clhpp      ${OPENCL_URL}-CLHPP/archive/refs/tags/v${OPENCL_REL}.tar.gz      /tmp/opencl \
    && /bin/fetch-and-untar opencl-icd-loader ${OPENCL_URL}-ICD-Loader/archive/refs/tags/v${OPENCL_REL}.tar.gz /tmp/opencl \
    && cp -r /tmp/opencl/OpenCL-Headers-${OPENCL_REL}/CL         /usr/aarch64-linux-gnu/include    \
    && cp -r /tmp/opencl/OpenCL-CLHPP-${OPENCL_REL}/include/CL/* /usr/aarch64-linux-gnu/include/CL \
    && cd /tmp/opencl/OpenCL-ICD-Loader-${OPENCL_REL}     \
    && cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_SYSTEM_NAME=Linux -DCMAKE_SYSTEM_PROCESSOR=aarch64 \
    -DCMAKE_C_COMPILER=aarch64-linux-gnu-gcc \
    -DCMAKE_CXX_COMPILER=aarch64-linux-gnu-g++ \
    -DOPENCL_ICD_LOADER_HEADERS_DIR=/usr/aarch64-linux-gnu/include \
    && cmake --build build   \
    && cp build/libOpenCL.so /usr/aarch64-linux-gnu/lib/libOpenCL.so.1 \
    && ln -s libOpenCL.so.1 /usr/aarch64-linux-gnu/lib/libOpenCL.so \
    && rm -rf /tmp/opencl

### Final stages

### Final Android arm64 image
FROM base AS arm64-android
COPY --from=arm64-android-build /opt /opt
RUN  /bin/image-cleanup

### Final Debian arm64 image
FROM base AS arm64-linux
COPY --from=arm64-debian-build /opt /opt
COPY --from=arm64-debian-build /usr/aarch64-linux-gnu/include/CL /usr/aarch64-linux-gnu/include/CL
COPY --from=arm64-debian-build /usr/aarch64-linux-gnu/lib/libOpenCL.so.1 /usr/aarch64-linux-gnu/lib/libOpenCL.so.1
RUN ln -s libOpenCL.so.1 /usr/aarch64-linux-gnu/lib/libOpenCL.so
# setting the OPENCL_SDK_ROOT env var so CMake can find them
ENV OPENCL_SDK_ROOT="/usr/aarch64-linux-gnu"

# Install cross-build essentials
RUN apt-get update && apt-get install -y -q --no-install-recommends \
    cross-config crossbuild-essential-arm64

RUN  /bin/image-cleanup
