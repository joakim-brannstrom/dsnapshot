# ubuntu_bionic_base
FROM ubuntu:bionic
MAINTAINER Joakim Brännström <joakim.brannstrom@gmx.com>

# Dependencies:
# ca-certificates - "Problem with the SSL CA cert" when cloning dextool otherwise.
# sqlite3 - generates SQLite reports.
RUN apt-get update && \
    apt-get -y --no-install-recommends install \
        ca-certificates \
        git \
        make

RUN apt-get -y --no-install-recommends install \
        curl \
        xz-utils \
        gcc g++

WORKDIR /opt

# dmd_latest_version
ARG DMD_VERSION

# dmd
ENV DC "dmd"
RUN curl -OL http://downloads.dlang.org/releases/2.x/${DMD_VERSION}/dmd.${DMD_VERSION}.linux.tar.xz
RUN set -ex && \
    tar xf dmd.${DMD_VERSION}.linux.tar.xz && \
    rm -f dmd.${DMD_VERSION}*.tar.xz
ENV PATH "/opt/dmd2/linux/bin64:$PATH"
RUN dmd --version && dub --version

# fix_repo
COPY repo.tar.gz /opt
RUN mkdir repo
RUN tar xfz repo.tar.gz -C repo && rm repo.tar.gz

# build_with_dub
RUN cd repo && dub test
# unable to run integration tests because some requires ssh
#RUN cd repo && dub run -c integration_test
