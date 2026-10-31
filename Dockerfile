FROM ubuntu:26.04

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        python3.14 \
        python3.14-venv \
        python3-pip \
    && python3.14 -m pip install --no-cache-dir --break-system-packages \
        ecdsa flask waitress websockets \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# The source tree is mounted at /app by compose.yaml. Keeping COPY here also
# allows the image to be run directly if desired.
COPY . /app

RUN chmod +x /app/bombsquad_server \
    /app/dist/bombsquad_headless \
    /app/dist/bombsquad_headless_aarch64

STOPSIGNAL SIGTERM

CMD ["python3.14", "-OB", "/app/bombsquad_server", "--noninteractive"]
