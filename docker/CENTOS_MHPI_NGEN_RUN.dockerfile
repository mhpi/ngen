ARG NPROC=4
ARG NGEN_REPO=https://github.com/mhpi/ngen.git
ARG NGEN_BRANCH=dev

# Stage 1: Get ngen source and initialize submodules
FROM rockylinux:8 AS source
ARG NPROC
ARG NGEN_REPO
ARG NGEN_BRANCH

RUN yum install -y git && \
git clone --recursive -b ${NGEN_BRANCH} ${NGEN_REPO} /src

# Clone and init all submodules
WORKDIR /src
RUN git submodule update --init --recursive --jobs ${NPROC} --depth 1


# Stage 2: Get dependencies
FROM rockylinux:8 AS dependencies

RUN yum update -y \
&& yum install -y epel-release dnf-plugins-core \
&& dnf config-manager --set-enabled powertools \
&& yum install -y \
tar \
git \
gcc-c++ \
gcc \
make \
cmake \
python38 \
python38-devel \
python38-numpy \
bzip2 \
udunits2-devel \
texinfo \
&& yum clean all \
&& rm -rf /var/cache/yum

# Boost setup
RUN curl -L -o boost_1_86_0.tar.bz2 https://sourceforge.net/projects/boost/files/boost/1.86.0/boost_1_86_0.tar.bz2/download \
&& tar -xjf boost_1_86_0.tar.bz2 \
&& rm boost_1_86_0.tar.bz2
ENV BOOST_ROOT="/boost_1_86_0"


# Stage 3: Build ngen
FROM dependencies AS build
ARG NPROC

COPY --from=source /src /ngen
WORKDIR /ngen

RUN cmake \
-S . \
-B build \
-DCMAKE_CXX_COMPILER=/usr/bin/g++ \
-DBOOST_ROOT=/boost_1_86_0 \
-DBoost_NO_BOOST_CMAKE:BOOL=TRUE \
-DBoost_NO_SYSTEM_PATHS=ON \
-DNGEN_WITH_MPI:BOOL=OFF \
-DNGEN_WITH_NETCDF:BOOL=OFF \
-DNGEN_WITH_SQLITE:BOOL=OFF \
-DNGEN_WITH_UDUNITS:BOOL=ON \
-DNGEN_WITH_BMI_FORTRAN:BOOL=OFF \
-DNGEN_WITH_BMI_C:BOOL=ON \
-DNGEN_WITH_PYTHON:BOOL=ON \
-DNGEN_WITH_TESTS:BOOL=ON \
-DNGEN_QUIET:BOOL=OFF \
-DNGEN_WITH_EXTERN_SLOTH:BOOL=OFF

RUN cmake \
--build build \
--target all \
-- \
-j ${NPROC}

# --- Stage 4: Runtime (make image ~3x smaller) ---
FROM rockylinux:8

# We must re-install epel-release so yum can find udunits2
RUN yum install -y epel-release \
&& yum install -y \
python38 \
python38-numpy \
udunits2 \
&& yum clean all
WORKDIR /app
COPY --from=build /ngen/build/ngen .
COPY --from=build /ngen/build/extern /app/extern
COPY ./data /app/data

CMD ["./ngen", "data/catchment_data.geojson", "", "data/nexus_data.geojson", "", "data/example_realization_config.json"]
