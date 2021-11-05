#
# nut Dockerfile
#
# https://github.com/shawly/docker-nut
#

# Set python image version
ARG PYTHON_VERSION=alpine

# Set vars for s6 overlay
ARG S6_OVERLAY_VERSION=v2.2.0.3
ARG S6_OVERLAY_BASE_URL=https://github.com/just-containers/s6-overlay/releases/download/${S6_OVERLAY_VERSION}

# Set NUT vars
ARG NUT_BRANCH=tags/v3.3
ARG NUT_RELEASE=https://github.com/blawar/nut/archive/refs/${NUT_BRANCH}.tar.gz
ARG TITLEDB_URL=https://github.com/blawar/titledb

# Set base images with s6 overlay download variable (necessary for multi-arch building via GitHub workflows)
FROM python:${PYTHON_VERSION} as python-amd64

ARG S6_OVERLAY_VERSION
ARG S6_OVERLAY_BASE_URL
ENV S6_OVERLAY_RELEASE="${S6_OVERLAY_BASE_URL}/s6-overlay-amd64.tar.gz"

FROM python:${PYTHON_VERSION} as python-386

ARG S6_OVERLAY_VERSION
ARG S6_OVERLAY_BASE_URL
ENV S6_OVERLAY_RELEASE="${S6_OVERLAY_BASE_URL}/s6-overlay-x86.tar.gz"

FROM python:${PYTHON_VERSION} as python-armv6

ARG S6_OVERLAY_VERSION
ARG S6_OVERLAY_BASE_URL
ENV S6_OVERLAY_RELEASE="${S6_OVERLAY_BASE_URL}/s6-overlay-armhf.tar.gz"

FROM python:${PYTHON_VERSION} as python-armv7

ARG S6_OVERLAY_VERSION
ARG S6_OVERLAY_BASE_URL
ENV S6_OVERLAY_RELEASE="${S6_OVERLAY_BASE_URL}/s6-overlay-arm.tar.gz"

FROM python:${PYTHON_VERSION} as python-arm64

ARG S6_OVERLAY_VERSION
ARG S6_OVERLAY_BASE_URL
ENV S6_OVERLAY_RELEASE="${S6_OVERLAY_BASE_URL}/s6-overlay-aarch64.tar.gz"

FROM python:${PYTHON_VERSION} as python-ppc64le

ARG S6_OVERLAY_VERSION
ARG S6_OVERLAY_BASE_URL
ENV S6_OVERLAY_RELEASE="${S6_OVERLAY_BASE_URL}/s6-overlay-ppc64le.tar.gz"

# Build crafty-web:master
FROM python-${TARGETARCH:-amd64}${TARGETVARIANT} as builder

ARG NUT_RELEASE

# Change working dir
WORKDIR /nut

# Install build deps and install python dependencies
RUN \
  set -ex && \
  echo "Installing build dependencies..." && \
    apk add --no-cache \
      git \
      build-base \
      libusb-dev \
      libressl-dev \
      libffi-dev \
      curl-dev \
      jpeg-dev \
      cargo \
      rust \
      zlib-dev && \
  echo "Cleaning up directories..." && \
    rm -rf /tmp/*

# Download NUT
ADD ${NUT_RELEASE} /tmp/nut.tar.gz

# Build wheels
RUN \
  set -ex && \
  echo "Extracting nut..." && \
    tar xzf /tmp/nut.tar.gz --strip-components=1 -C /nut && \
  echo "Upgrading pip..." && \
    pip3 install --upgrade pip && \
  echo "Removing pyqt5 from requirements.txt since we have no gui..." && \
    sed -i '/pyqt5/d' requirements.txt && \
    sed -i '/qt-range-slider/d' requirements.txt && \
  echo "Upgrading pip..." && \
    pip3 install --upgrade pip && \
  echo "Building wheels for requirements..." && \
    pip3 wheel --no-cache-dir --wheel-dir /usr/src/wheels -r requirements.txt && \
  echo "Creating volume directories..." && \
    mv -v conf conf_template && \
    mkdir -p conf _NSPOUT titles && \
  echo "Cleaning up directories..." && \
    rm -f /usr/bin/register && \
    rm -rf .github windows_driver gui tests tests-gui && \
    rm -f .coveragerc .editorconfig .gitignore .pep8 .pylintrc .pre-commit-config.yaml \
          autoformat nut.pyproj nut.sln nut_gui.py tasks.py requirements_dev.txt setup.cfg pytest.ini *.md && \
    rm -rf /tmp/*

# Build nut
FROM python-${TARGETARCH:-amd64}${TARGETVARIANT}

ARG TITLEDB_URL

ENV UMASK=022 \
    FIX_OWNERSHIP=true \
    TITLEDB_UPDATE=true \
    TITLEDB_URL=${TITLEDB_URL} \
    TITLEDB_REGION=US \
    TITLEDB_LANGUAGE=en

# Download S6 Overlay
ADD ${S6_OVERLAY_RELEASE} /tmp/s6overlay.tar.gz

# Copy wheels & crafty-web
COPY --from=builder /usr/src/wheels /usr/src/wheels
COPY --chown=1000 --from=builder /nut /nut

# Change working dir
WORKDIR /nut

# Install deps and build binary
RUN \
  set -ex && \
  echo "Installing runtime dependencies..." && \
    apk add --no-cache \
      bash \
      curl \
      shadow \
      coreutils \
      libjpeg-turbo \
      tzdata \
      diffutils \
      git && \
  echo "Extracting s6 overlay..." && \
    tar xzf /tmp/s6overlay.tar.gz -C / && \
  echo "Creating nut user..." && \
    useradd -u 1000 -U -M -s /bin/false nut && \
    usermod -G users nut && \
  echo "Upgrading pip..." && \
    pip3 install --upgrade pip && \
  echo "Install requirements..." && \
    pip3 install --no-index --find-links=/usr/src/wheels -r requirements.txt && \
  echo "Cleaning up directories..." && \
    rm -f /usr/bin/register && \
    rm -rf /tmp/*

# Add files
COPY rootfs/ /

# Define mountable directories
VOLUME ["/nut/titles", "/nut/conf", "/nut/_NSPOUT"]

# Expose ports
EXPOSE 9000

# Start s6
ENTRYPOINT ["/init"]
