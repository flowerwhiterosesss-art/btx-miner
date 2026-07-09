#!/usr/bin/env bash
# HiveOS h-stats.sh — btx (golden-miner-pool-prover / 新版表格日志)
# 被 HiveOS source（非执行）：只需设好 $khs 和 $stats，不要 echo。
#   khs   : 整机总算力 (kH/s)
#   stats : 上报 JSON（hs=每卡算力数组，power=每卡功耗数组）
# 数据来源：矿机每 ~10s 打一屏 ASCII 表格：
#   | Device | Target | Nonce | TChecks | Attempts | Power |
#   | GPU N  | 5.5K/s | 318M/s| ...     | ...      | 111W  |
#   | Total  | 43.7K/s| 2.5G/s| ...     | ...      | 945W  |
# 口径：Target 列（K/s 档）＝旧版 rate= 口径；Nonce 列是原始穷举吞吐，不采用。

# 稳健引入 manifest（兼容被 source 与被直接执行两种调用），拿到 CUSTOM_LOG_BASENAME。
MINER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -f "$MINER_DIR/h-manifest.conf" ]] && . "$MINER_DIR/h-manifest.conf"

# 日志源：原版 HiveOS = ${CUSTOM_LOG_BASENAME}.log（由 h-run.sh tee 落盘）；
#        若不存在则回退到 minerX (os-fork) agent 的日志，保证双平台兼容。
# 注意：os-fork 的日志名取的是“算法名”(历史上是 nock)，并非矿机文件夹名；
#      故此处与文件夹改名(btx)无关。为覆盖 os-fork 侧可能的改名，按 btx→nock 双候选探测。
LOG_FILE="${CUSTOM_LOG_BASENAME}.log"
if [[ ! -f "$LOG_FILE" ]]; then
    for _cand in /var/log/os/os_miner_btx.log /var/log/os/os_miner_nock.log; do
        [[ -f "$_cand" ]] && { LOG_FILE="$_cand"; break; }
    done
fi

khs=0
stats=""

if [[ -f $LOG_FILE ]]; then
    # —— 日志新鲜度：mtime 必须在 60s 内，否则视为矿机已停/卡死 -> 上报 0 ——
    log_age=$(( $(date +%s) - $(stat -c %Y "$LOG_FILE") ))
    if (( log_age <= 60 )); then
        # 末尾多屏 + 去 ANSI 颜色码（防止个别带色行干扰匹配）
        tail_buf=$(tail -n 5000 "$LOG_FILE" | sed 's/\x1b\[[0-9;]*m//g')

        # 一段 awk 扫全缓冲：GPU 行累积进当前块，碰到 Total 行整块快照并清零——
        # 只保留最后一个“以 Total 收尾的完整表”，天然规避 tail 截断的半张表。
        # 输出 3 行：总 kH/s、每卡 kH/s 列表、每卡功耗(W)列表。
        parsed=$(printf '%s\n' "$tail_buf" | awk '
            function conv(s,  n, u, m) {   # "5.476K/s" -> kH/s（无后缀=H、K/M/G 自适应）
                n = s; sub(/[KMGkmg]?\/s$/, "", n)
                u = s; sub(/^[0-9.]+/, "", u); sub(/\/s$/, "", u)
                m = 1
                if (u == "K" || u == "k") m = 1e3
                else if (u == "M" || u == "m") m = 1e6
                else if (u == "G" || u == "g") m = 1e9
                return n * m / 1000
            }
            /^\| GPU [0-9]+ / { l = $0; gsub(/ /, "", l); split(l, f, "|")
                                w = f[7]; sub(/W$/, "", w)
                                hs = hs " " conv(f[3]); pw = pw " " w; next }
            /^\| Total /      { l = $0; gsub(/ /, "", l); split(l, f, "|")
                                total = conv(f[3]); last_hs = hs; last_pw = pw
                                hs = ""; pw = "" }
            END { if (total != "") printf "%.3f\n%s\n%s\n", total, last_hs, last_pw }
        ')

        if [[ -n $parsed ]]; then
            khs=$(printf '%s\n' "$parsed" | sed -n 1p)
            hs_list=$(printf '%s\n' "$parsed" | sed -n 2p | sed 's/^ //')
            pw_list=$(printf '%s\n' "$parsed" | sed -n 3p | sed 's/^ //')
        else
            # 回退：旧版逐行日志的独立 rate= token（未升级二进制的机器）。
            # 前置 [[:space:]] 只匹配前面是空白的 ` rate=`，天然排除 `nonce_rate=`。
            rate_tok=$(printf '%s\n' "$tail_buf" \
                | grep -oE '[[:space:]]rate=[0-9]+(\.[0-9]+)?[KMGkmg]?/s' | tail -n 1)
            rate_val=$(printf '%s' "$rate_tok" | grep -oE '[0-9]+(\.[0-9]+)?' | head -n 1)
            rate_unit=$(printf '%s' "$rate_tok" | grep -oE '[KMGkmg]?/s$' | grep -oE '^[KMGkmg]?')
            if [[ -n $rate_val ]]; then
                khs=$(awk -v n="$rate_val" -v u="$rate_unit" 'BEGIN{
                    m=1;
                    if(u=="K"||u=="k") m=1e3;
                    else if(u=="M"||u=="m") m=1e6;
                    else if(u=="G"||u=="g") m=1e9;
                    printf "%.3f", n*m/1000
                }')
            fi
            hs_list=""; pw_list=""
        fi
        # 极端情况（缓冲区里 Total 行前没有 GPU 行）或旧格式回退：hs 退化为 [总值]。
        [[ -z $hs_list ]] && hs_list=$khs

        # uptime：尽力取矿机进程运行秒数（日志无累计 uptime 字段），取不到则 0。
        # 按启动命令签名匹配真实进程（btx-miner-cu* 二进制 + -mode stratum），
        # 不硬编码 CUDA 版本号（cu12/cu13/未来 cu14...），换二进制也能命中。
        miner_pid=$(pgrep -f 'btx-miner.*-mode stratum' 2>/dev/null | head -n 1)
        uptime_s=0
        [[ -n $miner_pid ]] && uptime_s=$(ps -o etimes= -p "$miner_pid" 2>/dev/null | tr -d ' ')
        [[ -z $uptime_s ]] && uptime_s=0

        # hs=每卡算力(kH/s)，power=每卡功耗(W)；功耗取不到时省略该字段。
        stats=$(jq -nc \
            --arg     hs_str   "$hs_list" \
            --arg     pw_str   "$pw_list" \
            --arg     hs_units "khs" \
            --argjson uptime   "$uptime_s" \
            --arg     algo     "nock" \
            --arg     ver      "golden-miner-pool-prover" \
            '{hs: ($hs_str | split(" ") | map(tonumber)),
              hs_units: $hs_units, uptime: $uptime,
              ar: [0,0], algo: $algo, ver: $ver}
             + (if $pw_str != "" then {power: ($pw_str | split(" ") | map(tonumber))} else {} end)')
    fi
fi

[[ -z $khs ]] && khs=0
[[ -z $stats ]] && stats='{"hs":[0],"hs_units":"khs","uptime":0,"ar":[0,0],"algo":"nock","ver":"golden-miner-pool-prover"}'
