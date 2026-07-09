#!/usr/bin/env bash
# HiveOS / minerX 通用启动脚本 —— btx (nockchain GPU prover, btxpow)
# 双平台兼容：可移植 cd 同时适配 /hive/miners/custom/... 与 /os/miners/custom/...

cd "$(dirname "$(readlink -f "$0")")" || exit 1
. h-manifest.conf

# HiveOS 不自动捕获 stdout，需自建日志目录并由本脚本 tee 落盘；
# minerX 上 stdout 经 tee 仍会流向其 agent，旧行为不变。
mkdir -p "$(dirname "$CUSTOM_LOG_BASENAME")"

# 关键：HiveOS 的 custom runner 只 `. wallet.conf`（不 export），而 h-run.sh 是被当“子进程”
# 执行的，子进程只继承 export 过的变量 → 直接引用 $CUSTOM_TEMPLATE/$CUSTOM_URL 会是空的。
# （-worker 不受影响，因为它用的是脚本内现算的 $(hostname)。）
# 所以这里主动 source wallet.conf 把钱包/矿池补齐；优先用 runner 传入的 $WALLET_CONF。
if [[ -z "$CUSTOM_TEMPLATE" || -z "$CUSTOM_URL" ]]; then
  for _wc in "$WALLET_CONF" /hive-config/wallet.conf /os-config/wallet.conf; do
    [[ -n "$_wc" && -f "$_wc" ]] && . "$_wc" && break
  done
fi

# 硬校验：payout(钱包) 或 pool(矿池) 为空就报错退出，绝不带空地址白挖。
if [[ -z "$CUSTOM_TEMPLATE" ]]; then
  echo "[btx] 致命错误: CUSTOM_TEMPLATE(钱包/payout) 为空 —— 请在飞行表 'Wallet and worker template' 填入 btx 地址，再重启矿机" >&2
  exit 1
fi
if [[ -z "$CUSTOM_URL" ]]; then
  echo "[btx] 致命错误: CUSTOM_URL(矿池) 为空 —— 请在飞行表 'Pool URL' 填写矿池地址，再重启矿机" >&2
  exit 1
fi

# 飞行表变量：CUSTOM_TEMPLATE=钱包/账户(payout)，CUSTOM_URL=矿池地址，
#             CUSTOM_USER_CONFIG=额外参数(可在飞行表里临时加 -maxtries / -log-interval / CORE_* 等)。
# 环境变量调优（保留现状）：
#   CORE_CUDA_FUSED_RHS=1
#   CORE_STRATUM_GPU_DIGEST=1
#   CORE_POW_PREHASH_SCAN_FACTOR=4096
# CORE_STRATUM_BATCH_SIZE=768 ./btx-miner \

MINER_BIN="$(./pick-miner.sh)"
echo "Debug MINER_BIN = $MINER_BIN"

$MINER_BIN \
  -mode stratum \
  -backend cuda \
  -gpu-devices all \
  -payout "${CUSTOM_TEMPLATE}" \
  -worker "core$(hostname)" \
  -pool "${CUSTOM_URL}" \
  ${CUSTOM_USER_CONFIG} \
  2>&1 | tee "${CUSTOM_LOG_BASENAME}.log"
