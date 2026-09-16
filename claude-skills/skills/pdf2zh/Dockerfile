FROM python:3.12-slim

# Runtime libraries for opencv-python (pulled in transitively by pdf2zh).
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        libgl1 \
        libglib2.0-0 \
        libxcb1 \
        libxext6 \
        libxrender1 \
        libsm6 \
    && rm -rf /var/lib/apt/lists/*

RUN groupadd --system --gid 1000 pdf2zh \
    && useradd --system --uid 1000 --gid 1000 --shell /usr/sbin/nologin pdf2zh

# pdf2zh writes a cache under $HOME on import. Point HOME at /tmp so the
# cache lives in the tmpfs that run.sh mounts at /tmp under --read-only.
ENV HOME=/tmp

WORKDIR /app

COPY requirements.txt ./
RUN pip install --no-cache-dir --require-hashes --no-deps -r requirements.txt

COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh \
    && mkdir -p /input /output /secrets \
    && chown pdf2zh:pdf2zh /output

USER pdf2zh

ENTRYPOINT ["/app/entrypoint.sh"]
