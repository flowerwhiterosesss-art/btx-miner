#!/usr/bin/env bash
# 本矿机所有参数都由 h-run.sh 通过命令行传入，无需生成配置文件。
# 仅占位创建 $CUSTOM_CONFIG_FILENAME，避免 HiveOS 报 "config not found"。
[[ -n "$CUSTOM_CONFIG_FILENAME" ]] && {
  mkdir -p "$(dirname "$CUSTOM_CONFIG_FILENAME")"
  : > "$CUSTOM_CONFIG_FILENAME"
}
