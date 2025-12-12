# Ubuntu 24.04 with CUDA 12 base (adjust minor version if desired)
FROM docker.io/nvidia/cuda:12.9.1-devel-ubuntu24.04

ENV DEBIAN_FRONTEND=noninteractive

# Use bash so we can use nicer shell features in RUN steps
SHELL ["/bin/bash", "-lc"]

# --------------------------------------------------------------------------- #
# System packages + Intel MKL (Ubuntu multiverse) + Ninja + common deps
# --------------------------------------------------------------------------- #
RUN set -eux && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        software-properties-common \
        ca-certificates && \
    add-apt-repository -y multiverse && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential \
        cudss \
        curl \
        gcc-11 g++-11 \
        git \
        libboost-graph-dev \
        libboost-program-options-dev \
        libboost-system-dev \
        libcgal-dev \
        libcudss0-cuda-12 \
        libcudss0-dev-cuda-12 \
        libcudss0-static-cuda-12 \
        libeigen3-dev \
        libfreeimage-dev \
        libgflags-dev \
        libglew-dev \
        libgmock-dev \
        libgoogle-glog-dev \
        libgtest-dev \
        libjpeg-dev \
        liblz4-dev \
        libmetis-dev \
        libmkl-full-dev \
        libopenimageio-dev \
        libpng-dev \
        libqt6opengl6-dev \
        libqt6openglwidgets6 \
        libsqlite3-dev \
        libtiff-dev \
        ninja-build \
        openimageio-tools \
        pkg-config \
        qt6-base-dev \
        wget \
        zlib1g-dev \
    && \
    rm -rf /var/lib/apt/lists/*

# Patch Eigen's CholmodSupport to drop the extern "C" wrapper around cholmod.h
# which causes a break in CUDA-enabled build.
# Patch Eigen's CholmodSupport to drop the extern "C" wrapper around cholmod.h
RUN python3 - << 'EOF'
import pathlib
import sys

path = pathlib.Path("/usr/include/eigen3/Eigen/CholmodSupport")
if not path.exists():
    sys.exit("Unable to find CholmodSupport")

lines = path.read_text().splitlines(keepends=True)
out_lines = []
skip_closing_brace = False

for line in lines:
    # Drop the 'extern "C" {' line
    if 'extern "C"' in line and '{' in line:
        continue

    # Keep the cholmod include, but remember to drop the following closing brace
    if '#include <cholmod.h>' in line:
        out_lines.append(line)
        skip_closing_brace = True
        continue

    # Drop the first bare '}' after the include (closing extern "C")
    if skip_closing_brace and line.strip() == '}':
        skip_closing_brace = False
        continue

    out_lines.append(line)

path.write_text(''.join(out_lines))
EOF

# --------------------------------------------------------------------------- #
# Make GCC/G++ 11 the default compiler (required by COLMAP & GLOMAP)
# --------------------------------------------------------------------------- #
RUN set -eux && \
    update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-11 100 && \
    update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-11 100

ENV CC=/usr/bin/gcc-11 \
    CXX=/usr/bin/g++-11 \
    CUDAHOSTCXX=/usr/bin/g++-11 \
    CUDAARCHS=86 \
    CMAKE_CUDA_ARCHITECTURES=86

# --------------------------------------------------------------------------- #
# First install older CMake to build and install flann.
# Then install the latest (4.2.0) to build everything else.
# --------------------------------------------------------------------------- #
RUN test -f /usr/share/doc/kitware-archive-keyring/copyright || \
    wget -O - https://apt.kitware.com/keys/kitware-archive-latest.asc 2>/dev/null | \
    gpg --dearmor - | tee /usr/share/keyrings/kitware-archive-keyring.gpg >/dev/null && \
    echo 'deb [signed-by=/usr/share/keyrings/kitware-archive-keyring.gpg] https://apt.kitware.com/ubuntu/ noble main' | tee /etc/apt/sources.list.d/kitware.list >/dev/null && \
    apt update && \
    apt install -y cmake=4.2.1-0kitware1ubuntu24.04.1 \
      cmake-data=4.2.1-0kitware1ubuntu24.04.1
    
# --------------------------------------------------------------------------- #
# Build & install SuiteSparse from source (latest tag), CUDA + MKL, Ninja
# --------------------------------------------------------------------------- #
WORKDIR /opt/src

RUN set -eux && \
    git clone https://github.com/DrTimothyAldenDavis/SuiteSparse.git && \
    cd SuiteSparse && \
    git checkout b35a1f9318f4bd42085f4b5ea56f29c89d342d4d && \
    mkdir -p build && cd build && \
    cmake -G Ninja .. \
        -DCMAKE_BUILD_TYPE=Release \
        -DSUITESPARSE_USE_CUDA=ON \
        -DSUITESPARSE_CUDA_ARCHITECTURES="86" \
        -DBLA_VENDOR=Intel10_64lp \
        -DSUITESPARSE_USE_64BIT_BLAS=ON \
        -DMKL_ROOT=/usr \
        -DBLAS_LIBRARIES="-L/usr/lib/x86_64-linux-gnu -lmkl_intel_lp64 -lmkl_gnu_thread -lmkl_core -lgomp -lpthread -lm -ldl" \
        -DLAPACK_LIBRARIES="-L/usr/lib/x86_64-linux-gnu -lmkl_intel_lp64 -lmkl_gnu_thread -lmkl_core -lgomp -lpthread -lm -ldl" && \
    ninja && \
    ninja install

# --------------------------------------------------------------------------- #
# Build & install Ceres Solver from source (latest tag), with SuiteSparse
# --------------------------------------------------------------------------- #
RUN set -eux && \
    git clone https://ceres-solver.googlesource.com/ceres-solver && \
    cd ceres-solver && \
    git checkout 85331393dc0dff09f6fb9903ab0c4bfa3e134b01 && \
    mkdir -p build && cd build && \
    cmake -G Ninja .. \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_SHARED_LIBS=ON \
        -DCERES_THREADING_MODEL=OPENMP \
        -DSUITESPARSE=ON \
        -DCMAKE_CUDA_ARCHITECTURES=86 && \
    ninja && \
    ninja install


# --------------------------------------------------------------------------- #
# Build & install COLMAP from source (latest release tag), CUDA 8.6, Ninja
# --------------------------------------------------------------------------- #
RUN set -eux && \
    git clone https://github.com/colmap/colmap.git && \
    cd colmap && \
    git checkout 0b31f98133b470eae62811b557dc2bcff1e4f9a5 && \
    mkdir -p build && cd build && \
    cmake -G Ninja .. \
        -DCMAKE_BUILD_TYPE=Release \
        -DCUDA_ENABLED=ON \
        -DGUI_ENABLED=OFF \
        -DCMAKE_CUDA_ARCHITECTURES=86 \
        -DBLA_VENDOR=Intel10_64lp \
        -DMKL_ROOT=/usr \
        -DBLAS_LIBRARIES="-L/usr/lib/x86_64-linux-gnu -lmkl_intel_lp64 -lmkl_gnu_thread -lmkl_core -lgomp -lpthread -lm -ldl" \
        -DLAPACK_LIBRARIES="-L/usr/lib/x86_64-linux-gnu -lmkl_intel_lp64 -lmkl_gnu_thread -lmkl_core -lgomp -lpthread -lm -ldl" && \
    ninja && \
    ninja install

# --------------------------------------------------------------------------- #
# Build & install GLOMAP from source (latest release tag), Ninja, CUDA 8.6
# --------------------------------------------------------------------------- #
RUN set -eux && \
    git clone https://github.com/colmap/glomap.git && \
    cd glomap && \
    git checkout 1.2.0 && \
    mkdir -p build && cd build && \
    cmake -G Ninja .. \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_CUDA_ARCHITECTURES=86 \
        -DMKL_ROOT=/usr \
        -DBLAS_LIBRARIES="-L/usr/lib/x86_64-linux-gnu -lmkl_intel_lp64 -lmkl_gnu_thread -lmkl_core -lgomp -lpthread -lm -ldl" \
        -DLAPACK_LIBRARIES="-L/usr/lib/x86_64-linux-gnu -lmkl_intel_lp64 -lmkl_gnu_thread -lmkl_core -lgomp -lpthread -lm -ldl" && \
    ninja && \
    ninja install

WORKDIR /workspace
CMD ["/bin/bash"]

