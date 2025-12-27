# Stage 1: Build
FROM rockylinux:8 AS builder

# Parallel build processes
ARG NPROC=4

# Combine YUM commands and clean up in one layer to save space
RUN yum update -y \
    && yum install -y epel-release \
    && yum repolist \
    && yum install -y dnf-plugins-core \
    && yum install -y tar git gcc-c++ gcc make cmake python38 python38-devel \
       python38-numpy bzip2 udunits2-devel texinfo \
    && yum clean all \
  	&& rm -rf /var/cache/yum \

# Boost setup
RUN curl -L -o boost_1_86_0.tar.bz2 https://sourceforge.net/projects/boost/files/boost/1.86.0/boost_1_86_0.tar.bz2/download \
    && tar -xjf boost_1_86_0.tar.bz2 \
    && rm boost_1_86_0.tar.bz2
ENV BOOST_ROOT="/boost_1_86_0"

# ENV CXX=/usr/bin/g++

# Clone and fetch ALL submodules
RUN git clone https://github.com/mhpi/ngen.git /ngen
WORKDIR /ngen
RUN git submodule update --init --recursive

RUN cmake \
    -S . \
    -B build \
    -DCMAKE_CXX_COMPILER=/usr/bin/g++ \
    -DBOOST_ROOT="/boost_$(echo ${BOOST_VERSION} | tr '\.' '_')" \
    -DBoost_NO_BOOST_CMAKE:BOOL=TRUE \
    -DNGEN_WITH_MPI:BOOL=OFF \
    -DNGEN_WITH_NETCDF:BOOL=OFF \
    -DNGEN_WITH_SQLITE:BOOL=OFF \
    -DNGEN_WITH_UDUNITS:BOOL=ON \
    -DNGEN_WITH_BMI_FORTRAN:BOOL=OFF \
    -DNGEN_WITH_BMI_C:BOOL=OFF \
    -DNGEN_WITH_PYTHON:BOOL=ON \
    -DNGEN_WITH_TESTS:BOOL=ON \
    -DNGEN_QUIET:BOOL=OFF \
    -DNGEN_WITH_EXTERN_SLOTH:BOOL=OFF \

RUN cmake \
    --build build \
    --target all \
    -- \
    -j $(NPROC)

# --- Stage 2: Runtime (make image ~10x smaller) ---
FROM rockylinux:8
RUN yum install -y python38 python38-numpy udunits2 && yum clean all
WORKDIR /app
COPY --from=builder /ngen/build/ngen .
COPY --from=builder /ngen/build/extern /app/extern
COPY ./data /app/data

CMD ["./ngen", "data/catchment_data.geojson", "", "data/nexus_data.geojson", "", "data/example_realization_config.json"]
