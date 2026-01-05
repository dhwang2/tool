#!/bin/bash

# Sing-box 自动化部署引导脚本 (Public Entry)
# 作用：从私有仓库拉取安装逻辑并执行

# --- 配置 ---
DEFAULT_USER="dhwang2"
PRIVATE_REPO="sing-box"
BRANCH="main"

# 颜色
red() { echo -e "\033[31m\033[01m$1\033[0m"; }
green() { echo -e "\033[32m\033[01m$1\033[0m"; }

# --- 主逻辑 ---

echo "================================================="
echo "   Sing-box Server 自动化部署 (Private Repo)"
echo "================================================="

# 1. 获取 PAT
read -p "请输入 GitHub PAT (Personal Access Token): " PAT
if [[ -z "$PAT" ]]; then
    red "错误: 必须提供 PAT 才能访问私有仓库。"
    exit 1
fi

# 2. 确认仓库用户 (可选)
read -p "请输入 GitHub 用户名 [默认: $DEFAULT_USER]: " REPO_USER
REPO_USER=${REPO_USER:-$DEFAULT_USER}

echo "正在准备环境..."
INSTALL_DIR="/tmp/sing-box-install"
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR"

# 3. 下载私有安装脚本
INSTALL_SCRIPT_URL="https://raw.githubusercontent.com/${REPO_USER}/${PRIVATE_REPO}/${BRANCH}/scripts/install.sh"
ENV_SCRIPT_URL="https://raw.githubusercontent.com/${REPO_USER}/${PRIVATE_REPO}/${BRANCH}/scripts/env.sh"

green "正在从私有仓库拉取安装脚本..."
# -H "Authorization: token $PAT"
curl -s -H "Authorization: token $PAT" -L "$INSTALL_SCRIPT_URL" -o "$INSTALL_DIR/install.sh"
curl -s -H "Authorization: token $PAT" -L "$ENV_SCRIPT_URL" -o "$INSTALL_DIR/env.sh"

if [[ ! -s "$INSTALL_DIR/install.sh" ]] || [[ ! -s "$INSTALL_DIR/env.sh" ]]; then
    red "下载失败！请检查："
    echo "1. PAT 是否正确且有权限访问该私有仓库。"
    echo "2. 仓库地址是否正确: $REPO_USER/$PRIVATE_REPO"
    echo "3. 脚本路径是否存在: scripts/install.sh"
    exit 1
fi

chmod +x "$INSTALL_DIR/install.sh"

# 4. 执行安装
green "脚本拉取成功，开始执行安装..."
cd "$INSTALL_DIR"
# 将 PAT 作为参数传递给 install.sh
bash install.sh "$PAT"

# 清理
cd /
rm -rf "$INSTALL_DIR"
