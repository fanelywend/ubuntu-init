#!/bin/bash
set -e

# ===================== 核心配置项 =====================
# 可根据需求修改默认值
TARGET_TIMEZONE="Asia/Shanghai"  # 目标时区
TARGET_MIRROR="aliyun"           # 软件源：aliyun/tuna/163/ustc
RELEASE_VERSION=$(lsb_release -sc 2>/dev/null || echo "jammy")  # 自动识别系统版本

# ===================== 颜色定义 =====================
GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
BLUE="\033[34m"
NC="\033[0m"

# 日志打印函数
info() { echo -e "${GREEN}[INFO] $*${NC}"; }
warn() { echo -e "${YELLOW}[WARN] $*${NC}"; }
error() { echo -e "${RED}[ERROR] $*${NC}"; exit 1; }
title() { echo -e "\n${BLUE}===== $* =====${NC}"; }

# ===================== 前置检查 =====================
# 检查是否为root权限
check_root() {
    if [ $EUID -ne 0 ]; then
        error "此脚本需要ROOT权限运行，请执行：sudo ./ubuntu-init.sh"
    fi
}

# ===================== 交互式选择 =====================
select_options() {
    clear
    title "Ubuntu 系统一键初始化配置"
    
    # 基础配置选择
    read -p "1. 是否设置时区为 ${TARGET_TIMEZONE}？[Y/n] " CHOICE_TZ
    read -p "2. 是否更换为 ${TARGET_MIRROR} 软件源？[Y/n] " CHOICE_MIRROR
    read -p "3. 是否安装基础工具（vim/git/curl等）？[Y/n] " CHOICE_BASE
    read -p "4. 是否安装中文语言包和字体？[Y/n] " CHOICE_CN
    
    # 桌面环境选择
    title "桌面环境选择（二选一或都不装）"
    echo "1) Xfce：轻量级，占用资源少，适合服务器/低配机器"
    echo "2) GNOME：Ubuntu官方桌面，功能丰富，占用资源较多"
    read -p "请选择要安装的桌面环境（1=Xfce/2=GNOME/0=不安装，默认0）：" CHOICE_DESKTOP
    
    # Docker选择
    read -p "5. 是否安装Docker + Docker Compose？[y/N] " CHOICE_DOCKER

    # 确认配置
    title "配置确认"
    echo "时区设置：${CHOICE_TZ:-Y}"
    echo "更换源：${CHOICE_MIRROR:-Y}"
    echo "基础工具：${CHOICE_BASE:-Y}"
    echo "中文环境：${CHOICE_CN:-Y}"
    case $CHOICE_DESKTOP in
        1) echo "桌面环境：Xfce" ;;
        2) echo "桌面环境：GNOME" ;;
        *) echo "桌面环境：不安装" ;;
    esac
    echo "Docker：${CHOICE_DOCKER:-N}"
    
    read -p "确认执行以上配置？[Y/n] " CONFIRM
    if [[ $CONFIRM =~ ^[Nn]$ ]]; then
        info "用户取消操作，脚本退出"
        exit 0
    fi
}

# ===================== 核心功能 =====================
# 1. 设置时区
set_timezone() {
    if [[ ! $CHOICE_TZ =~ ^[Nn]$ ]]; then
        title "设置系统时区"
        timedatectl set-timezone ${TARGET_TIMEZONE}
        ln -sf /usr/share/zoneinfo/${TARGET_TIMEZONE} /etc/localtime
        hwclock --systohc
        info "时区已设置为 ${TARGET_TIMEZONE}"
    fi
}

# 2. 更换软件源
change_mirror() {
    if [[ ! $CHOICE_MIRROR =~ ^[Nn]$ ]]; then
        title "更换${TARGET_MIRROR}软件源"
        # 备份原有源文件
        cp /etc/apt/sources.list /etc/apt/sources.list.bak.$(date +%Y%m%d%H%M)
        
        # 写入对应源配置
        case ${TARGET_MIRROR} in
            aliyun)
                MIRROR_URL="http://mirrors.aliyun.com/ubuntu/"
                ;;
            tuna)
                MIRROR_URL="https://mirrors.tuna.tsinghua.edu.cn/ubuntu/"
                ;;
            163)
                MIRROR_URL="http://mirrors.163.com/ubuntu/"
                ;;
            ustc)
                MIRROR_URL="https://mirrors.ustc.edu.cn/ubuntu/"
                ;;
            *)
                error "不支持的源类型：${TARGET_MIRROR}"
                ;;
        esac

        cat >/etc/apt/sources.list <<EOF
deb ${MIRROR_URL} ${RELEASE_VERSION} main restricted universe multiverse
deb-src ${MIRROR_URL} ${RELEASE_VERSION} main restricted universe multiverse
deb ${MIRROR_URL} ${RELEASE_VERSION}-security main restricted universe multiverse
deb-src ${MIRROR_URL} ${RELEASE_VERSION}-security main restricted universe multiverse
deb ${MIRROR_URL} ${RELEASE_VERSION}-updates main restricted universe multiverse
deb-src ${MIRROR_URL} ${RELEASE_VERSION}-updates main restricted universe multiverse
deb ${MIRROR_URL} ${RELEASE_VERSION}-backports main restricted universe multiverse
deb-src ${MIRROR_URL} ${RELEASE_VERSION}-backports main restricted universe multiverse
EOF

        # 更新源并升级系统
        apt update -y
        apt upgrade -y
        info "软件源已更换并完成系统更新"
    fi
}

# 3. 安装基础工具
install_base_tools() {
    if [[ ! $CHOICE_BASE =~ ^[Nn]$ ]]; then
        title "安装基础工具"
        apt install -y \
            vim git curl wget net-tools htop lsof tree \
            unzip zip bzip2 rsync screen tmux ncdu sysstat
        # 优化vim配置
        echo -e "set nu\nset tabstop=4\nset shiftwidth=4" >> /etc/vim/vimrc
        info "基础工具安装完成"
    fi
}

# 4. 安装中文环境和字体
install_chinese_env() {
    if [[ ! $CHOICE_CN =~ ^[Nn]$ ]]; then
        title "安装中文语言包和字体"
        # 安装中文语言包
        apt install -y language-pack-zh-hans language-pack-zh-hans-base
        # 配置系统语言为中文
        update-locale LANG=zh_CN.UTF-8 LC_ALL=zh_CN.UTF-8
        # 安装中文字体（解决乱码问题）
        apt install -y \
            fonts-wqy-microhei fonts-wqy-zenhei \
            fonts-noto-cjk fonts-noto-color-emoji
        info "中文环境配置完成"
    fi
}

# 5. 安装Xfce桌面
install_xfce() {
    title "安装Xfce桌面环境"
    apt install -y xfce4 xfce4-goodies lightdm
    # 设置默认图形界面启动
    systemctl set-default graphical.target
    systemctl enable lightdm
    info "Xfce桌面安装完成"
}

# 6. 安装GNOME桌面
install_gnome() {
    title "安装GNOME桌面环境"
    apt install -y ubuntu-desktop
    # 安装GNOME扩展工具（可选）
    apt install -y gnome-tweaks chrome-gnome-shell
    # 设置默认图形界面启动
    systemctl set-default graphical.target
    info "GNOME桌面安装完成"
}

# 7. 安装Docker和Compose
install_docker() {
    if [[ $CHOICE_DOCKER =~ ^[Yy]$ ]]; then
        title "安装Docker和Docker Compose"
        # 安装依赖
        apt install -y apt-transport-https ca-certificates curl gnupg-agent software-properties-common
        # 添加Docker GPG密钥
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
        # 添加Docker源
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu ${RELEASE_VERSION} stable" | tee /etc/apt/sources.list.d/docker.list >/dev/null
        # 安装Docker
        apt update -y
        apt install -y docker-ce docker-ce-cli containerd.io
        # 安装Docker Compose
        curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
        # 开机自启并加入用户组
        systemctl enable --now docker
        usermod -aG docker $SUDO_USER 2>/dev/null || true
        info "Docker安装完成"
    fi
}

# ===================== 主流程 =====================
main() {
    # 前置检查
    check_root
    # 交互式选择配置
    select_options
    # 执行核心功能
    set_timezone
    change_mirror
    install_base_tools
    install_chinese_env
    # 根据选择安装桌面
    case $CHOICE_DESKTOP in
        1) install_xfce ;;
        2) install_gnome ;;
        *) info "不安装桌面环境" ;;
    esac
    install_docker

    # 完成提示
    title "初始化完成"
    info "✅ 所有配置已执行完毕！"
    info "💡 建议执行重启使配置生效：sudo reboot"
    info "🌐 若安装了桌面，重启后会自动进入图形界面"
}

# 启动脚本
main
