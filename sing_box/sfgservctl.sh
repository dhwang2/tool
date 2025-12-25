#!/usr/bin/env bash

# 定制版 Sing-box 安装管理脚本
# 功能：
# 1. 自动化安装 Sing-box 内核及服务
# 2. 不生成任何入站/出站配置，需用户自行上传配置文件到 /etc/sing-box/conf/
# 3. 提供 sb 命令进行服务管理和内核更新

# --- 变量定义 ---
WORK_DIR='/etc/sing-box'
TEMP_DIR='/tmp/sing-box'
CONF_DIR="${WORK_DIR}/conf"
LOG_DIR="${WORK_DIR}/logs"
BIN_FILE="${WORK_DIR}/sing-box"
SERVICE_FILE='/etc/systemd/system/sing-box.service'
GITHUB_PROXY='https://gh-proxy.com/' # 默认加速镜像

# 颜色定义
red() { echo -e "\033[31m\033[01m$1\033[0m"; }
green() { echo -e "\033[32m\033[01m$1\033[0m"; }
yellow() { echo -e "\033[33m\033[01m$1\033[0m"; }

# --- 基础检查 ---

check_root() {
    [[ $EUID -ne 0 ]] && red "错误: 必须使用 root 用户运行此脚本！\n" && exit 1
}

check_sys() {
    if [[ -f /etc/redhat-release ]]; then
        release="centos"
    elif cat /etc/issue | grep -q -E -i "debian"; then
        release="debian"
    elif cat /etc/issue | grep -q -E -i "ubuntu"; then
        release="ubuntu"
    elif cat /etc/issue | grep -q -E -i "centos|red hat|alma|rocky"; then
        release="centos"
    elif cat /proc/version | grep -q -E -i "debian"; then
        release="debian"
    elif cat /proc/version | grep -q -E -i "ubuntu"; then
        release="ubuntu"
    elif cat /proc/version | grep -q -E -i "centos|red hat|alma|rocky"; then
        release="centos"
    else
        red "不支持的系统，仅支持 Debian/Ubuntu/CentOS"
        exit 1
    fi
    
    # 检查架构
    case "$(uname -m)" in
        x86_64|amd64) ARCH="amd64" ;; 
        aarch64|arm64) ARCH="arm64" ;; 
        armv7l) ARCH="armv7" ;; 
        *) red "不支持的架构: $(uname -m)"; exit 1 ;; 
    esac
}

install_dependencies() {
    green "正在安装依赖..."
    if [[ "${release}" == "centos" ]]; then
        yum install -y wget tar jq
    else
        apt-get update
        apt-get install -y wget tar jq
    fi
}

# --- 核心功能 ---

get_latest_version() {
    # 获取 GitHub 最新版本号
    local api_url="https://api.github.com/repos/SagerNet/sing-box/releases/latest"
    local version=$(wget --no-check-certificate -qO- "${api_url}" | jq -r .tag_name | sed 's/^v//')
    
    if [[ -z "$version" || "$version" == "null" ]]; then
        yellow "无法获取最新版本，尝试使用备用源..."
        version=$(wget --no-check-certificate -qO- "${GITHUB_PROXY}${api_url}" | jq -r .tag_name | sed 's/^v//')
    fi
    
    if [[ -z "$version" || "$version" == "null" ]]; then
        red "获取版本失败，请检查网络连接。"
        exit 1
    fi
    echo "$version"
}

install_singbox() {
    local version=$1
    if [[ -z "$version" ]]; then
        version=$(get_latest_version)
    fi
    
    green "准备安装 Sing-box v${version} (${ARCH})..."
    
    # 清理旧文件
    rm -rf "$TEMP_DIR"
    mkdir -p "$TEMP_DIR"
    mkdir -p "$WORK_DIR" "$CONF_DIR" "$LOG_DIR"
    
    # 下载
    local filename="sing-box-${version}-linux-${ARCH}.tar.gz"
    local download_url="https://github.com/SagerNet/sing-box/releases/download/v${version}/${filename}"
    local proxy_download_url="${GITHUB_PROXY}${download_url}"
    
    green "正在下载: ${filename}"
    # 尝试直连下载，失败则走代理
    wget -O "${TEMP_DIR}/${filename}" "$download_url" || wget -O "${TEMP_DIR}/${filename}" "$proxy_download_url"
    
    if [[ ! -f "${TEMP_DIR}/${filename}" ]]; then
        red "下载失败！"
        exit 1
    fi
    
    # 解压安装
    tar -zxvf "${TEMP_DIR}/${filename}" -C "$TEMP_DIR"
    # 查找解压后的二进制文件（目录名可能包含版本号）
    local extracted_bin=$(find "$TEMP_DIR" -name sing-box -type f | head -n 1)
    
    if [[ -f "$extracted_bin" ]]; then
        mv "$extracted_bin" "$BIN_FILE"
        chmod +x "$BIN_FILE"
        green "Sing-box 二进制文件安装成功！"
    else
        red "解压失败或未找到二进制文件！"
        exit 1
    fi
    
    rm -rf "$TEMP_DIR"
}

create_service() {
    green "配置 Systemd 服务..."
    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Sing-box Service
Documentation=https://sing-box.sagernet.org
After=network.target nss-lookup.target network-online.target

[Service]
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
ExecStart=${BIN_FILE} run -C ${CONF_DIR}
ExecReload=/bin/kill -HUP $MAINPID
Restart=on-failure
RestartSec=10
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable sing-box
}

install_sb_command() {
    # 备份本脚本到工作目录，用于后续管理
    # 如果当前脚本是本地文件，则直接复制
    if [[ -f "$0" ]]; then
        cp "$0" "${WORK_DIR}/sfgservctl.sh"
    else
        # 否则（如通过管道执行），从 GitHub 下载
        green "正在下载管理脚本..."
        local script_url="https://raw.githubusercontent.com/dhwang2/tool/main/sing-box/install/sfgservctl.sh"
        # 尝试下载
        wget -O "${WORK_DIR}/sfgservctl.sh" "${script_url}" || \
        wget -O "${WORK_DIR}/sfgservctl.sh" "${GITHUB_PROXY}${script_url}"
        
        if [[ ! -f "${WORK_DIR}/sfgservctl.sh" ]]; then
            red "管理脚本下载失败，'sb' 命令可能无法使用！"
        fi
    fi
    chmod +x "${WORK_DIR}/sfgservctl.sh"

    # 创建快捷指令 /usr/bin/sb
    # 注意: 使用 "\$@" 来传递参数，并转义 $ 符号，防止在生成文件时被展开
    cat > /usr/bin/sb <<EOF
#!/bin/bash
bash ${WORK_DIR}/sfgservctl.sh "\$@"
EOF
    chmod +x /usr/bin/sb
}

# --- 管理功能 ---

show_menu() {
    clear
    echo "=================================="
    echo "   Sing-box 管理脚本 (定制版)"
    echo "   配置目录: ${CONF_DIR}"
    echo "=================================="
    echo " 1. 启动 Sing-box"
    echo " 2. 停止 Sing-box"
    echo " 3. 重启 Sing-box"
    echo " 4. 查看 运行状态"
    echo " 5. 查看 日志 (最后100行)"
    echo "----------------------------------"
    echo " 6. 更新 Sing-box 内核"
    echo " 7. 卸载 Sing-box"
    echo " 0. 退出"
    echo "=================================="
    read -p "请输入选择 [0-7]: " choice
    case $choice in
        1) systemctl start sing-box && green "已启动" ;;
        2) systemctl stop sing-box && green "已停止" ;;
        3) systemctl restart sing-box && green "已重启" ;;
        4) systemctl status sing-box --no-pager ;; 
        5) journalctl -u sing-box --no-pager -n 100 ;; 
        6) update_core ;; 
        7) uninstall_singbox ;; 
        0) exit 0 ;; 
        *) red "输入错误" ;; 
    esac
}

update_core() {
    local current_ver=$($BIN_FILE version | head -n 1 | awk '{print $3}')
    local latest_ver=$(get_latest_version)
    
    green "当前版本: $current_ver"
    green "最新版本: $latest_ver"
    
    if [[ "$current_ver" == "$latest_ver" ]]; then
        yellow "已经是最新版本，无需更新。"
        read -p "是否强制重新安装? [y/N]: " force
        if [[ "${force,,}" != "y" ]]; then
            return
        fi
    fi
    
    systemctl stop sing-box
    install_singbox "$latest_ver"
    systemctl start sing-box
    green "更新完成！"
}

uninstall_singbox() {
    read -p "确定要卸载 Sing-box 吗? (配置不会被删除) [y/N]: " confirm
    if [[ "${confirm,,}" == "y" ]]; then
        systemctl stop sing-box
        systemctl disable sing-box
        rm -f "$SERVICE_FILE"
        systemctl daemon-reload
        rm -f "$BIN_FILE"
        rm -f /usr/bin/sb
        rm -f "${WORK_DIR}/sfgservctl.sh"
        green "Sing-box 已卸载。配置文件保留在 ${WORK_DIR}。"
    fi
}

# --- 主逻辑 ---

main() {
    check_root
    
    # 如果有参数，执行对应命令（用于 sb 快捷指令）
    if [[ -n "$1" ]]; then
        case "$1" in
            menu) show_menu ;; 
            status) systemctl status sing-box ;; 
            start) systemctl start sing-box ;; 
            stop) systemctl stop sing-box ;; 
            restart) systemctl restart sing-box ;; 
            log) journalctl -u sing-box -f ;; 
            update) update_core ;; 
            *) show_menu ;; 
        esac
        return
    fi

    # 如果没有参数，且未安装，进入安装流程
    if [[ ! -f "$BIN_FILE" ]]; then
        check_sys
        install_dependencies
        install_singbox
        create_service
        install_sb_command
        
        green "\n安装完成！"
        yellow "--------------------------------------------------------"
        yellow "注意：本脚本不生成配置文件。"
        yellow "请将您的 .json 配置文件上传到: ${CONF_DIR}/"
        yellow "上传后执行 'sb restart' 即可启动服务。"
        yellow "--------------------------------------------------------"
        yellow "常用命令:"
        yellow "  sb          - 打开管理菜单"
        yellow "  sb log      - 查看日志"
        yellow "  sb update   - 更新内核"
        yellow "--------------------------------------------------------"
    else
        # 已安装，直接显示菜单
        show_menu
    fi
}

main "$@"
