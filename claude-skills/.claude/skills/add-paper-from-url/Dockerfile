# syntax=docker/dockerfile:1.7

FROM golang:1.26-bookworm AS builder

ARG PAPERPILE_VERSION=v0.4.0
ENV CGO_ENABLED=0 \
    GOFLAGS=-trimpath

RUN go install "github.com/garaemon/paperpile@${PAPERPILE_VERSION}"

FROM debian:bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends curl ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && useradd -u 1000 -m -s /bin/sh paperpile

COPY --from=builder /go/bin/paperpile /usr/local/bin/paperpile
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod 0755 /usr/local/bin/entrypoint.sh /usr/local/bin/paperpile

USER paperpile
WORKDIR /home/paperpile

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
