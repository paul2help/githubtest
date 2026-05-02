#!/bin/bash

# 设置错误处理：如果遇到简单的错误不直接退出，但记录状态
set -e

echo "正在安装 ttyd 和 Cloudflared..."

# 识别系统架构 (x86_64 或 aarch64/arm64)
ARCH=$(uname -m)
echo "检测到系统架构: $ARCH"

# 1. 安装 ttyd (直接下载二进制，避开 Snap 错误)
if [ ! -f "/usr/local/bin/ttyd" ]; then
    echo "正在从 GitHub 下载 ttyd..."
    if [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
        wget -q https://github.com/tsl0922/ttyd/releases/download/1.7.7/ttyd.aarch64 -O ttyd
    else
        wget -q https://github.com/tsl0922/ttyd/releases/download/1.7.7/ttyd.x86_64 -O ttyd
    fi
    chmod +x ttyd
    sudo mv ttyd /usr/local/bin/
    echo "✓ ttyd 安装完成"
else
    echo "✓ ttyd 已存在，跳过安装"
fi

# 2. 安装 Cloudflared
if [ ! -f "/usr/local/bin/cloudflared" ]; then
    echo "正在下载 Cloudflared..."
    if [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
        wget -q https://github.com/cloudflare/cloudflared/releases/download/2025.10.1/cloudflared-linux-arm64 -O cloudflared
    else
        wget -q https://github.com/cloudflare/cloudflared/releases/download/2025.10.1/cloudflared-linux-amd64 -O cloudflared
    fi
    chmod +x cloudflared
    sudo mv cloudflared /usr/local/bin/
    echo "✓ Cloudflared 安装完成"
else
    echo "✓ Cloudflared 已存在，跳过安装"
fi

# 确保安装了 net-tools (用于检查端口状态)
sudo apt update -y && sudo apt install net-tools -y

# 停止可能存在的旧进程，防止端口占用
pkill -f ttyd 2>/dev/null || true
pkill -f cloudflared 2>/dev/null || true

# 3. 启动 ttyd
echo "启动 ttyd (监听端口 7681)..."
# 使用 -W 允许写入权限，bash 作为默认 shell
# 重定向输出到日志以便排查问题
nohup ttyd -p 7681 -W bash > ttyd.log 2>&1 &
TTYD_PID=$!

# 等待启动并检查端口
sleep 3
if netstat -tuln | grep -q ":7681"; then
    echo "✓ ttyd 启动成功 (PID: $TTYD_PID)"
else
    echo "✗ ttyd 启动失败，请检查 ttyd.log"
    cat ttyd.log
    exit 1
fi

# 4. 启动 Cloudflared 隧道进行内网穿透
echo "启动 Cloudflared 隧道..."
nohup cloudflared tunnel --url http://127.0.0.1:7681 > cloudflared.log 2>&1 &
CLOUDFLARED_PID=$!

# 获取 Cloudflare 生成的临时公共 URL
echo "正在获取外网访问地址 (约需 10-20 秒)..."
PUBLIC_URL=""
for i in {1..15}; do
    if [ -f cloudflared.log ]; then
        # 匹配 trycloudflare.com 的特征域名
        PUBLIC_URL=$(grep -o "https://[a-zA-Z0-9.-]*\.trycloudflare\.com" cloudflared.log | head -1)
        if [ -n "$PUBLIC_URL" ]; then
            break
        fi
    fi
    sleep 2
done

# 获取本地 IP 地址
IP=$(hostname -I | awk '{print $1}')

# 打印最终报告
echo ""
echo "=================================================="
echo "          服务启动成功！"
echo "=================================================="
echo "本地访问: http://$IP:7681"
if [ -n "$PUBLIC_URL" ]; then
    echo "外网访问: $PUBLIC_URL"
else
    echo "外网访问: 链接提取超时，请运行 'cat cloudflared.log' 查看"
fi
echo "=================================================="

# 将进程 ID 保存到文件，方便后续管理（如停止服务）
echo $TTYD_PID > ttyd.pid
echo $CLOUDFLARED_PID > cloudflared.pid
