#Container
FROM alpine:3.7

RUN apk add --update \
  gettext \
  jq \
  groff \
  less \
  python \
  python-dev \
  py-pip \
  py-cffi \
  py-cryptography \
  gcc \
  libffi-dev \
  linux-headers \
  musl-dev \
  openssl-dev

RUN pip install \
  gsutil \
  awscli

RUN rm /var/cache/apk/*
