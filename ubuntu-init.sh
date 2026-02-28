#!/bin/bash
set -e

# ===================== 核心配置项 =====================
# 可根据需求修改默认值
TARGET_TIMEZONE="Asia/Shanghai"  # 目标时区
TARGET_MIRROR="aliyun"           # 软件源：aliyun/tuna/163/ustc
RELEASE_VERSION=$(lsb_release -sc 2>/dev/null || echo "jammy")  # 自动识别系统版本
# Docker加速镜像配置（默认阿里云）
DOCKER_MIRROR="https://mirror.aliyun.com/docker-ce/"
DOCKER_REGISTRY_MIRROR="https://xxxxxx.mirror.aliyuncs.com"  # 需替换为自己的阿里云镜像加速地址（或用公共源）

# ===================== 颜色定义 =====================
GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
BLUE="\033[34m"
PURPLE="\033[35m"
NC="\033[0m"

# 日志打印函数
info() { echo -e "${GREEN}[INFO] $*${NC}"; }
warn() { echo -e "${YELLOW}[WARN] $*${NC}"; }
error() { echo -e "${RED}[ERROR] $*${NC}"; exit 1; }
title() { echo -e "\n${BLUE}===== $* =====${NC}"; }
menu_title() { echo -e "\n${PURPLE}===== $* =====${NC}"; }

# ===================== 全局变量（存储用户选择） =====================
# 基础配置
CHOICE_TZ="Y"
CHOICE_MIRROR="Y"
CHOICE_BASE="Y"
CHOICE_CN="Y"
# 桌面配置
CHOICE_DESKTOP="0"
# Docker配置
CHOICE_DOCKER="N"
CHOICE_DOCKER_MIRROR="Y"
# 最终确认
CONFIRM="Y"

# ===================== 前置检查 =====================
# 检查是否为root权限
check_root() {
    if [ $EUID -ne 0 ]; then
        error "此脚本需要ROOT权限运行，请执行：sudo ./ubuntu-init.sh"
    fi
}

# 检查并安装必要依赖（解决hwclock缺失问题）
install_essential_deps() {
    title "检查基础依赖包"
    # 检查hwclock命令是否存在，不存在则安装util-linux
    if ! command -v hwclock &> /dev/null; then
        info "未检测到hwclock命令，开始安装util-linux包"
        apt update -y
        apt install -y util-linux
    fi
    # 检查timedatectl（系统时间管理）
    if ! command -v timedatectl &> /dev/null; then
        info "未检测到timedatectl，开始安装systemd-timesyncd"
        apt install -y systemd-timesyncd
    fi
    info "基础依赖检查完成"
}

# ===================== 多级菜单交互 =====================
# 主菜单
main_menu() {
    clear
    menu_title "Ubuntu 一键初始化脚本 - 主菜单"
    echo "欢迎使用Ubuntu系统一键初始化脚本！"
    echo "本脚本将帮助你完成系统基础配置、工具安装等操作"
    echo -e "\n请选择操作："
    echo "1) 进入配置菜单（设置时区/源/桌面/Docker等）"
    echo "2) 使用默认配置快速执行（时区/源/基础工具/中文环境）"
    echo "0) 退出脚本"
    read -p "请输入选项（0-2，默认1）：" MAIN_CHOICE
    MAIN_CHOICE=${MAIN_CHOICE:-1}
    
    case $MAIN_CHOICE in
        1) config_menu ;;
        2) info "使用默认配置执行，跳过自定义配置" ;;
        0) info "用户退出脚本" ; exit 0 ;;
        *) error "无效选项，请重新运行脚本" ;;
    esac
}

# 配置子菜单
config_menu() {
    clear
    menu_title "配置菜单 - 基础设置"
    # 时区配置
    read -p "1. 是否设置时区为 ${TARGET_TIMEZONE}？[Y/n] " CHOICE_TZ
    CHOICE_TZ=${CHOICE_TZ:-Y}
    # 软件源配置
    read -p "2. 是否更换为 ${TARGET_MIRROR} 软件源？[Y/n] " CHOICE_MIRROR
    CHOICE_MIRROR=${CHOICE_MIRROR:-Y}
    # 基础工具
    read -p "3. 是否安装基础工具（vim/git/curl等）？[Y/n] " CHOICE_BASE
    CHOICE_BASE=${CHOICE_BASE:-Y}
    # 中文环境
    read -p "4. 是否安装中文语言包和字体？[Y/n] " CHOICE_CN
    CHOICE_CN=${CHOICE_CN:-Y}

    # 桌面环境子菜单
    desktop_menu

    # Docker配置子菜单
    docker_menu

    # 配置确认
    confirm_menu
}

# 桌面环境子菜单
desktop_menu() {
    clear
    menu_title "配置菜单 - 桌面环境"
    echo "请选择要安装的桌面环境（二选一或都不装）："
    echo "1) Xfce：轻量级，占用资源少，适合服务器/低配机器"
    echo "2) GNOME：Ubuntu官方桌面，功能丰富，占用资源较多"
    echo "0) 不安装桌面环境（默认）"
    read -p "请输入选项（0-2，默认0）：" CHOICE_DESKTOP
    CHOICE_DESKTOP=${CHOICE_DESKTOP:-0}
}

# Docker配置子菜单
docker_menu() {
    clear
    menu_title "配置菜单 - Docker配置"
    # 是否安装Docker
    read -p "1. 是否安装Docker + Docker Compose？[y/N] " CHOICE_DOCKER
    CHOICE_DOCKER=${CHOICE_DOCKER:-N}
    
    # 如果安装Docker，配置加速镜像
    if [[ $CHOICE_DOCKER =~ ^[Yy]$ ]]; then
        read -p "2. 是否配置Docker镜像加速？[Y/n] " CHOICE_DOCKER_MIRROR
        CHOICE_DOCKER_MIRROR=${CHOICE_DOCKER_MIRROR:-Y}
        
        if [[ $CHOICE_DOCKER_MIRROR =~ ^[Yy]$ ]]; then
            echo -e "\n可选的Docker加速源："
            echo "1) 阿里云（默认，需替换为自己的加速地址）"
            echo "2) 网易云：https://hub-mirror.c.163.com"
            echo "3) 科大：https://docker.mirrors.ustc.edu.cn"
            echo "4) 自定义地址"
            read -p "请选择Docker加速源（1-4，默认1）：" DOCKER_MIRROR_CHOICE
            DOCKER_MIRROR_CHOICE=${DOCKER_MIRROR_CHOICE:-1}
            
            case $DOCKER_MIRROR_CHOICE in
                1) 
                    warn "注意：阿里云镜像加速需要自己申请，地址格式为 https://xxxxxx.mirror.aliyuncs.com"
                    read -p "请输入你的阿里云Docker加速地址（直接回车使用公共源）：" CUSTOM_MIRROR
                    DOCKER_REGISTRY_MIRROR=${CUSTOM_MIRROR:-"https://docker.mirrors.ustc.edu.cn"}
                    ;;
                2) DOCKER_REGISTRY_MIRROR="https://hub-mirror.c.163.com" ;;
                3) DOCKER_REGISTRY_MIRROR="https://docker.mirrors.ustc.edu.cn" ;;
                4) 
                    read -p "请输入自定义Docker加速地址：" CUSTOM_MIRROR
                    if [[ -z $CUSTOM_MIRROR ]]; then
                        error "自定义地址不能为空"
                    fi
                    DOCKER_REGISTRY_MIRROR=$CUSTOM_MIRROR
                    ;;
                *) DOCKER_REGISTRY_MIRROR="https://docker.mirrors.ustc.edu.cn" ;;
            esac
        fi
    fi
}

# 配置确认菜单
confirm_menu() {
    clear
    menu_title "配置确认"
    echo "以下是你的配置选择："
    echo "==================== 基础配置 ===================="
    echo "时区设置：${CHOICE_TZ}"
    echo "更换软件源：${CHOICE_MIRROR}（源类型：${TARGET_MIRROR}）"
    echo "安装基础工具：${CHOICE_BASE}"
    echo "安装中文环境：${CHOICE_CN}"
    echo "==================== 桌面配置 ===================="
    case $CHOICE_DESKTOP in
        1) echo "桌面环境：Xfce" ;;
        2) echo "桌面环境：GNOME" ;;
        *) echo "桌面环境：不安装" ;;
    esac
    echo "==================== Docker配置 ==================="
    echo "安装Docker：${CHOICE_DOCKER}"
    if [[ $CHOICE_DOCKER =~ ^[Yy]$ ]]; then
        echo "配置Docker加速：${CHOICE_DOCKER_MIRROR}"
        echo "Docker加速地址：${DOCKER_REGISTRY_MIRROR}"
    fi
    
    read -p "确认执行以上配置？[Y/n] " CONFIRM
    CONFIRM=${CONFIRM:-Y}
    if [[ $CONFIRM =~ ^[Nn]$ ]]; then
        info "用户取消配置，返回主菜单"
        main_menu
    fi
}

# ===================== 核心功能 =====================
# 1. 设置时区
set_timezone() {
    if [[ ! $CHOICE_TZ =~ ^[Nn]$ ]]; then
        title "设置系统时区"
        # 核心时区配置（兼容所有Ubuntu版本）
        timedatectl set-timezone ${TARGET_TIMEZONE}
        ln -sf /usr/share/zoneinfo/${TARGET_TIMEZONE} /etc/localtime
        
        # hwclock同步硬件时钟（增加容错，失败不中断）
        if command -v hwclock &> /dev/null; then
            hwclock --systohc 2>/dev/null || warn "硬件时钟同步失败（不影响系统时区）"
        else
            warn "未找到hwclock命令，跳过硬件时钟同步"
        fi
        
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
            unzip zip bzip2 rsync screen tmux ncdu sysstat util-linux
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

# 7. 安装Docker和Compose（含加速配置）
install_docker() {
    if [[ $CHOICE_DOCKER =~ ^[Yy]$ ]]; then
        title "安装Docker和Docker Compose"
        # 安装依赖
        apt install -y apt-transport-https ca-certificates curl gnupg-agent software-properties-common
        
        # 配置Docker镜像源（加速安装）
        curl -fsSL ${DOCKER_MIRROR}gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] ${DOCKER_MIRROR}linux/ubuntu ${RELEASE_VERSION} stable" | tee /etc/apt/sources.list.d/docker.list >/dev/null
        
        # 安装Docker
        apt update -y
        apt install -y docker-ce docker-ce-cli containerd.io
        
        # 安装Docker Compose
        curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
        
        # 配置Docker镜像加速（registry-mirror）
        if [[ $CHOICE_DOCKER_MIRROR =~ ^[Yy]$ ]]; then
            title "配置Docker镜像加速"
            mkdir -p /etc/docker
            cat > /etc/docker/daemon.json << EOF
{
  "registry-mirrors": ["${DOCKER_REGISTRY_MIRROR}"]
}
EOF
            # 重启Docker生效
            systemctl daemon-reload
            systemctl restart docker
            info "Docker镜像加速配置完成，加速地址：${DOCKER_REGISTRY_MIRROR}"
        fi
        
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
    # 安装核心依赖（解决hwclock缺失）
    install_essential_deps
    # 启动多级菜单交互
    main_menu
    
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
    # 安装并配置Docker
    install_docker

    # 完成提示
    title "初始化完成"
    info "✅ 所有配置已执行完毕！"
    info "💡 建议执行重启使配置生效：sudo reboot"
    info "🌐 若安装了桌面，重启后会自动进入图形界面"
    info "🐳 若安装了Docker，可执行 docker -v 验证安装结果"
}

# 启动脚本
main
