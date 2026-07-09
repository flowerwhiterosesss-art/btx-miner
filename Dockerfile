FROM nvidia/cuda:12.4.1-runtime-ubuntu22.04

LABEL org.opencontainers.image.source="https://github.com/flowerwhiterosesss-art/btx-miner"
LABEL org.opencontainers.image.description="BTX Miner v2.7.0 - MatMul PoW (CUDA 12/13)"
LABEL org.opencontainers.image.licenses="MIT"

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl ca-certificates && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /miner

COPY btx/btx-miner-cu12 btx/btx-miner-cu13 btx/pick-miner.sh ./
RUN chmod +x btx-miner-cu12 btx-miner-cu13 pick-miner.sh

ENV BTX_POOL="btx.pearlfortune.org:23333"
ENV BTX_WALLET=""
ENV BTX_WORKER="docker"
ENV BTX_EXTRA=""

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
