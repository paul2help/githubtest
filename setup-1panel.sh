#!/bin/bash

echo "正在安装 1panel 和 Cloudflared..."

# ============================================================
# 安装 Cloudflared（用于外网访问 1panel 面板）
# ============================================================
ARCH=$(uname -m)
if [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
    wget -q https://github.com/cloudflare/cloudflared/releases/download/2025.10.1/cloudflared-linux-arm64 -O cloudflared
else
    wget -q https://github.com/cloudflare/cloudflared/releases/download/2025.10.1/cloudflared-linux-amd64 -O cloudflared
fi
chmod +x cloudflared
sudo mv cloudflared /usr/local/bin/

# ============================================================
# 安装 1panel
# ============================================================
echo "开始安装 1panel..."

# 设置非交互模式
export PANEL_NON_INTERACTIVE=true
export PANEL_LANG=zh
export PANEL_PORT=$(( ( RANDOM % 10000 ) + 10000 ))
export PANEL_USERNAME=admin
export PANEL_PASSWORD=admin12345678
export PANEL_INSTALL_DOCKER=y
export PANEL_DOCKER_MODE=auto
export PANEL_CONFIGURE_ACCELERATOR=n
export PANEL_REPLACE_DAEMON_JSON=n
export PANEL_ENTRANCE=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c 16)

sudo -E bash -c "$(curl -sSL https://resource.fit2cloud.com/1panel/package/v2/quick_start.sh)"

# 检查端口
if netstat -tuln 2>/dev/null | grep -q ":${PANEL_PORT}"; then
    echo "✓ 1panel 正在监听端口 ${PANEL_PORT}"
else
    echo "✗ 1panel 未监听端口 ${PANEL_PORT}，尝试等待更长时间..."
    sleep 5
    if netstat -tuln 2>/dev/null | grep -q ":${PANEL_PORT}"; then
        echo "✓ 1panel 正在监听端口 ${PANEL_PORT}"
    else
        echo "✗ 1panel 仍未监听端口 ${PANEL_PORT}"
        exit 1
    fi
fi

# 启动 Cloudflared 隧道
echo "启动 Cloudflared 隧道..."
nohup cloudflared tunnel --url http://localhost:${PANEL_PORT} > cloudflared.log 2>&1 &
CLOUDFLARED_PID=$!

# 等待隧道建立
echo "等待隧道建立..."
sleep 10

# 获取公共 URL
PUBLIC_URL=""
for i in {1..10}; do
    if [ -f cloudflared.log ]; then
        PUBLIC_URL=$(grep -o "https://[a-zA-Z0-9.-]*\.trycloudflare\.com" cloudflared.log | head -1)
        if [ -n "$PUBLIC_URL" ]; then
            break
        fi
    fi
    sleep 2
done

# 显示访问信息
IP=$(hostname -I | awk '{print $1}')
echo ""
echo "=================================================="
echo "1panel 安装完成！"
echo "=================================================="
echo "默认账户: $PANEL_USERNAME"
echo "默认密码: $PANEL_PASSWORD"
echo "本地访问: http://$IP:${PANEL_PORT}/${PANEL_ENTRANCE}"
if [ -n "$PUBLIC_URL" ]; then
    echo "外网访问: ${PUBLIC_URL}/${PANEL_ENTRANCE}"
else
    echo "外网访问: 正在生成... (查看: cat cloudflared.log)"
fi
echo ""
echo "=================================================="

# 保存进程信息
echo $CLOUDFLARED_PID > cloudflared.pid
