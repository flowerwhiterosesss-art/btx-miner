#!/usr/bin/env bash
set -e

if [ -z "$BTX_WALLET" ]; then
    echo "[btx] ERROR: BTX_WALLET is not set!"
    echo "  docker run -e BTX_WALLET=btx1z... ..."
    exit 1
fi

# Auto-detect CUDA and pick binary
MINER_BIN=$(./pick-miner.sh 2>/dev/null || echo "./btx-miner-cu12")
echo "[btx] Using miner: $MINER_BIN"
echo "[btx] Pool: $BTX_POOL"
echo "[btx] Wallet: $BTX_WALLET"
echo "[btx] Worker: $BTX_WORKER"

exec $MINER_BIN \
    -mode stratum \
    -backend cuda \
    -gpu-devices all \
    -payout "$BTX_WALLET" \
    -worker "$BTX_WORKER" \
    -pool "$BTX_POOL" \
    $BTX_EXTRA
