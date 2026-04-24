#!/bin/bash
# 注意：不使用 set -e，改用每个关键步骤的返回值检查

# 强制 root 检查
if [ "$EUID" -ne 0 ]; then 
  echo "请使用 root 权限运行此脚本" >&2
  exit 1
fi

# 定义一个安全读取函数，强制从终端读取
safe_read() {
  local prompt="$1"
  local var_name="$2"
  local default="$3"
  local input
  
  # 打印提示到 stderr，以便在管道中也能看到
  printf "%s" "$prompt" >&2
  
  # 尝试从终端读取，失败则报错退出
  if ! read -r input < /dev/tty 2>/dev/null; then
    echo "" >&2
    echo "错误：无法读取终端输入。" >&2
    echo "建议使用 wget 下载脚本后执行：" >&2
    echo "  wget $0 && chmod +x $0 && sudo ./$0" >&2
    exit 1
  fi
  
  # 处理默认值
  if [ -z "$input" ] && [ -n "$default" ]; then
    input="$default"
  fi
  
  # 将结果赋值给调用者指定的变量
  eval "$var_name='$input'"
  echo "" >&2  # 换行
}

# 显示欢迎信息（脚本开始）
echo "========================================" >&2
echo "  萌通加速 Xboard-Node 部署脚本" >&2
echo "========================================" >&2

# 使用 safe_read 获取所有配置
safe_read '请输入面板 URL [默认: https://dash.tors.moe]: ' PANEL_URL 'https://dash.tors.moe'
safe_read '请输入面板 Token: ' PANEL_TOKEN ''
if [ -z "$PANEL_TOKEN" ]; then
  echo "Token 不能为空" >&2
  exit 1
fi

safe_read '请输入节点 ID (node_id): ' NODE_ID ''
if [ -z "$NODE_ID" ]; then
  echo "节点 ID 不能为空" >&2
  exit 1
fi

echo "面板 URL: $PANEL_URL" >&2
echo "Token: ${PANEL_TOKEN:0:4}****" >&2
echo "节点 ID: $NODE_ID" >&2

# 安装 Docker
if ! command -v docker &> /dev/null; then
  echo "Docker 未安装，正在安装..." >&2
  curl -sSL https://get.docker.com | bash
  systemctl enable docker
  systemctl start docker
else
  echo "Docker 已安装" >&2
  systemctl enable docker 2>/dev/null
  systemctl start docker 2>/dev/null
fi

# 安装 git
if ! command -v git &> /dev/null; then
  echo "git 未安装，正在安装..." >&2
  apt-get update && apt-get install -y git
else
  echo "git 已安装" >&2
fi

# 处理旧目录
if [ -d "xboard-node" ]; then
  echo "检测到已存在的 xboard-node 目录。" >&2
  safe_read '是否删除并重新部署？(y/n) ' confirm 'n'
  if [[ "$confirm" =~ ^[Yy](es)?$ ]]; then
    echo "正在删除旧目录..." >&2
    rm -rf xboard-node
  else
    echo "已取消部署。" >&2
    exit 0
  fi
fi

echo "克隆 xboard-node 仓库..." >&2
if ! git clone -b compose --depth 1 https://github.com/cedar2025/xboard-node.git; then
  echo "仓库克隆失败，请检查网络或地址。" >&2
  exit 1
fi

cd xboard-node

# 生成配置
mkdir -p config
cat > config/config.yml <<EOF
panel:
  url: "${PANEL_URL}"
  token: "${PANEL_TOKEN}"
  node_id: ${NODE_ID}
EOF

echo "配置文件已生成：" >&2
cat config/config.yml >&2

echo "启动容器..." >&2
if ! docker compose up -d; then
  echo "容器启动失败，请检查配置和 Docker 日志。" >&2
  exit 1
fi

echo "============================================" >&2
echo "部署完成！" >&2
echo "============================================" >&2

safe_read '是否查看容器日志？(y/n) ' show_logs 'n'
if [[ "$show_logs" =~ ^[Yy](es)?$ ]]; then
  echo "等待容器初始化..." >&2
  sleep 5
  docker compose logs --tail 50
  echo "提示：如需持续查看日志，请执行: docker compose logs -f" >&2
else
  echo "跳过日志查看。" >&2
fi
