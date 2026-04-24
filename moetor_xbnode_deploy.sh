#!/bin/bash
set -e

# 检查 root 权限
if [ "$EUID" -ne 0 ]; then 
  echo "请使用 root 权限运行此脚本"
  exit 1
fi

# 提示输入配置信息（面板 URL 有默认值）
read -p "请输入面板 URL (默认 https://dash.tors.moe): " -i "https://dash.tors.moe" PANEL_URL
# 如果用户直接回车（空值），则使用默认值
PANEL_URL="${PANEL_URL:-https://dash.tors.moe}"
echo "使用面板 URL: $PANEL_URL"

read -p "请输入面板 Token: " PANEL_TOKEN
if [ -z "$PANEL_TOKEN" ]; then
  echo "Token 不能为空"
  exit 1
fi

read -p "请输入节点 ID (node_id): " NODE_ID
if [ -z "$NODE_ID" ]; then
  echo "节点 ID 不能为空"
  exit 1
fi

# 检查并安装 Docker
if ! command -v docker &> /dev/null; then
  echo "Docker 未安装，正在安装..."
  curl -sSL https://get.docker.com | bash
  systemctl enable docker
  systemctl start docker
else
  echo "Docker 已安装，跳过安装步骤。"
  # 确保 Docker 服务已启动且开机自启
  systemctl enable docker 2>/dev/null
  systemctl start docker 2>/dev/null
fi

# 检查并安装 git
if ! command -v git &> /dev/null; then
  echo "git 未安装，正在安装..."
  apt-get update && apt-get install -y git
else
  echo "git 已安装，跳过。"
fi

# 检查并处理已存在的 xboard-node 目录
if [ -d "xboard-node" ]; then
  echo "检测到已存在的 xboard-node 目录。"
  read -p "是否删除并重新部署？(y/n) " confirm
  if [[ "$confirm" =~ ^[Yy](es)?$ ]]; then
    echo "正在删除旧目录..."
    rm -rf xboard-node
  else
    echo "已取消部署。"
    exit 0
  fi
fi

echo "克隆 xboard-node 仓库..."
git clone -b compose --depth 1 https://github.com/cedar2025/xboard-node.git
cd xboard-node

# 确保 config 目录存在并生成配置
mkdir -p config
cat > config/config.yml <<EOF
panel:
  url: "${PANEL_URL}"
  token: "${PANEL_TOKEN}"
  node_id: ${NODE_ID}
EOF

echo "配置文件已生成："
cat config/config.yml

echo "启动容器..."
docker compose up -d

echo "============================================"
echo "部署完成！"
echo "============================================"

# 询问是否查看日志
read -p "是否查看容器日志？(y/n) " show_logs
if [[ "$show_logs" =~ ^[Yy](es)?$ ]]; then
  echo "等待容器初始化..."
  sleep 5
  echo "---------- 容器最近日志 ----------"
  docker compose logs --tail 50
  echo ""
  echo "提示：如需持续查看日志，请执行: docker compose logs -f"
else
  echo "跳过日志查看。"
fi
