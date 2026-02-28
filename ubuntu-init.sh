#!/bin/bash
set -e

# ===================== 核心配置项 =====================
TARGET_TIMEZONE="Asia/Shanghai"
TARGET_MIRROR="aliyun"
RELEASE_VERSION=$(lsb_release -sc 2>/dev/null || echo "jammy")
DOCKER_MIRROR="https://mirror.aliyun.com/docker-ce/"
DOCKER_REGISTRY_MIRROR="https://docker.mirrors.ustc.edu.cn"  # 默认公共源

# ===================== 颜色定义 =====================
GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
BLUE="\033[34m"
PURPLE="\033[35m"
CYAN="\033[36m"
WHITE="\033[37m"
BG_BLUE="\033[44m"
NC="\033[0m"

# 日志打印函数
info() { echo -e "${GREEN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }
success() { echo -e "${CYAN}[SUCCESS]${NC} $*"; }
menu_head() { echo -e "\n${BG_BLUE}${WHITE}===== $* =====${NC}"; }
menu_title() { echo -e "${PURPLE}→ $*${NC}"; }

# ===================== 全局状态管理 =====================
# 功能执行状态（key:功能名, value:状态）
declare -A EXEC_STATUS=(
    ["时区设置"]="未执行"
    ["软件源更换"]="未执行"
    ["基础工具安装"]="未执行"
    ["中文环境配置"]="未执行"
    ["Xfce桌面安装"]="未执行"
    ["GNOME桌面安装"]="未执行"
    ["XRDP远程桌面"]="未执行"
    ["Docker安装"]="未执行"
    ["Docker加速配置"]="未执行"
)

# 已安装功能列表
INSTALLED_FEATURES=()

# ===================== 防重复安装判断函数 =====================
# 基础判断工具
is_installed() {
    command -v "$1" &> /dev/null
}

file_exists() {
    [ -f "$1" ]
}

# 1. 时区是否已设置
is_timezone_set() {
    [ "$(timedatectl show -p Timezone --value 2>/dev/null)" == "$TARGET_TIMEZONE" ]
}

# 2. 软件源是否已更换（检测是否有国内源）
is_mirror_changed() {
    grep -q "mirrors.aliyun.com\|mirrors.tuna.tsinghua.edu.cn\|mirrors.163.com\|mirrors.ustc.edu.cn" /etc/apt/sources.list 2>/dev/null
}

# 3. 基础工具是否已安装
is_base_tools_installed() {
    is_installed vim && is_installed git && is_installed curl && is_installed htop
}

# 4. 中文环境是否已配置
is_chinese_done() {
    is_installed locale && locale -a 2>/dev/null | grep -q "zh_CN.utf8"
}

# 5. Xfce是否安装
is_xfce_installed() {
    is_installed xfce4-session
}

# 6. GNOME是否安装
is_gnome_installed() {
    is_installed gnome-shell
}

# 7. XRDP是否安装
is_xrdp_installed() {
    is_installed xrdp && systemctl is-active --quiet xrdp 2>/dev/null
}

# 8. Docker是否安装
is_docker_installed() {
    is_installed docker
}

# 9. Docker加速是否配置
is_docker_mirror_configured() {
    file_exists /etc/docker/daemon.json && grep -q "registry-mirrors" /etc/docker/daemon.json 2>/dev/null
}

# ===================== 工具函数 =====================
# 检查ROOT权限
check_root() {
    [ $EUID -ne 0 ] && error "请使用ROOT权限运行（sudo ./ubuntu-init.sh）"
}

# 安装基础依赖
install_core_deps() {
    if ! command -v hwclock &>/dev/null; then
        info "安装util-linux依赖包"
        apt update -y && apt install -y util-linux
    fi
    if ! command -v timedatectl &>/dev/null; then
        info "安装systemd-timesyncd依赖包"
        apt install -y systemd-timesyncd
    fi
}

# 刷新状态显示
refresh_status() {
    clear
    menu_head " Ubuntu 一键初始化工具 - 执行状态 "
    echo -e "┌──────────────────────┬───────────┐"
    for func in "${!EXEC_STATUS[@]}"; do
        status=${EXEC_STATUS[$func]}
        # 状态颜色
        case $status in
            "已完成") status="${GREEN}${status}${NC}" ;;
            "已跳过") status="${YELLOW}${status}${NC}" ;;
            *) status="${RED}${status}${NC}" ;;
        esac
        printf "│ %-20s │ %-9s │\n" "$func" "$status"
    done
    echo -e "└──────────────────────┴───────────┘"
}

# 显示已安装功能
show_installed() {
    menu_head " 已安装功能列表 "
    if [ ${#INSTALLED_FEATURES[@]} -eq 0 ]; then
        echo -e "${YELLOW}暂无已安装功能${NC}"
    else
        for i in "${!INSTALLED_FEATURES[@]}"; do
            echo -e "${CYAN}$((i+1)).${NC} ${INSTALLED_FEATURES[$i]}"
        done
    fi
    echo -e "\n${WHITE}按回车返回菜单...${NC}"
    read -r
}

# ===================== 核心功能实现（带防重复） =====================
# 1. 时区设置
func_set_timezone() {
    refresh_status
    menu_title "时区设置 - ${TARGET_TIMEZONE}"
    
    # 防重复判断
    if is_timezone_set; then
        success "时区已设置为 ${TARGET_TIMEZONE}，跳过重复操作"
        EXEC_STATUS["时区设置"]="已完成"
        echo -e "\n${WHITE}按回车返回菜单...${NC}"
        read -r
        return
    fi

    read -p "确认设置时区为 ${TARGET_TIMEZONE}？[Y/n] " confirm
    confirm=${confirm:-Y}
    
    if [[ $confirm =~ ^[Yy]$ ]]; then
        timedatectl set-timezone ${TARGET_TIMEZONE}
        ln -sf /usr/share/zoneinfo/${TARGET_TIMEZONE} /etc/localtime
        hwclock --systohc 2>/dev/null || warn "硬件时钟同步失败（不影响系统时区）"
        success "时区设置完成：${TARGET_TIMEZONE}"
        EXEC_STATUS["时区设置"]="已完成"
        INSTALLED_FEATURES+=("时区设置（Asia/Shanghai）")
    else
        warn "已跳过时区设置"
        EXEC_STATUS["时区设置"]="已跳过"
    fi
    echo -e "\n${WHITE}按回车返回菜单...${NC}"
    read -r
}

# 2. 软件源更换
func_change_mirror() {
    refresh_status
    menu_title "软件源更换 - 可选源：aliyun/tuna/163/ustc"
    
    # 防重复判断
    if is_mirror_changed; then
        success "软件源已更换为国内源，跳过重复操作"
        EXEC_STATUS["软件源更换"]="已完成"
        echo -e "\n${WHITE}按回车返回菜单...${NC}"
        read -r
        return
    fi

    echo "当前默认源：${TARGET_MIRROR}"
    read -p "是否更换软件源？[Y/n] " confirm
    confirm=${confirm:-Y}
    
    if [[ $confirm =~ ^[Yy]$ ]]; then
        # 选择源类型
        echo -e "\n请选择软件源："
        echo "1) 阿里云（默认）"
        echo "2) 清华大学"
        echo "3) 163网易"
        echo "4) 中国科学技术大学"
        read -p "输入选项（1-4，默认1）：" mirror_choice
        mirror_choice=${mirror_choice:-1}
        
        case $mirror_choice in
            1) MIRROR="aliyun"; MIRROR_URL="http://mirrors.aliyun.com/ubuntu/" ;;
            2) MIRROR="tuna"; MIRROR_URL="https://mirrors.tuna.tsinghua.edu.cn/ubuntu/" ;;
            3) MIRROR="163"; MIRROR_URL="http://mirrors.163.com/ubuntu/" ;;
            4) MIRROR="ustc"; MIRROR_URL="https://mirrors.ustc.edu.cn/ubuntu/" ;;
            *) MIRROR="aliyun"; MIRROR_URL="http://mirrors.aliyun.com/ubuntu/" ;;
        esac
        
        # 备份并替换源
        cp /etc/apt/sources.list /etc/apt/sources.list.bak.$(date +%Y%m%d%H%M)
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
        
        apt update -y && apt upgrade -y
        success "${MIRROR}软件源更换完成，已更新系统包"
        EXEC_STATUS["软件源更换"]="已完成"
        INSTALLED_FEATURES+=("软件源更换（${MIRROR}）")
    else
        warn "已跳过软件源更换"
        EXEC_STATUS["软件源更换"]="已跳过"
    fi
    echo -e "\n${WHITE}按回车返回菜单...${NC}"
    read -r
}

# 3. 基础工具安装
func_install_base() {
    refresh_status
    menu_title "基础工具安装 - vim/git/curl/htop等"
    
    # 防重复判断
    if is_base_tools_installed; then
        success "基础工具已安装完成，跳过重复操作"
        EXEC_STATUS["基础工具安装"]="已完成"
        echo -e "\n${WHITE}按回车返回菜单...${NC}"
        read -r
        return
    fi

    read -p "确认安装基础工具？[Y/n] " confirm
    confirm=${confirm:-Y}
    
    if [[ $confirm =~ ^[Yy]$ ]]; then
        apt install -y \
            vim git curl wget net-tools htop lsof tree \
            unzip zip bzip2 rsync screen tmux ncdu sysstat util-linux
        # Vim优化配置
        grep -q "set nu" /etc/vim/vimrc || echo -e "set nu\nset tabstop=4\nset shiftwidth=4" >> /etc/vim/vimrc
        success "基础工具安装完成"
        EXEC_STATUS["基础工具安装"]="已完成"
        INSTALLED_FEATURES+=("基础工具（vim/git/curl/htop等）")
    else
        warn "已跳过基础工具安装"
        EXEC_STATUS["基础工具安装"]="已跳过"
    fi
    echo -e "\n${WHITE}按回车返回菜单...${NC}"
    read -r
}

# 4. 中文环境配置
func_install_chinese() {
    refresh_status
    menu_title "中文环境配置 - 语言包+中文字体"
    
    # 防重复判断
    if is_chinese_done; then
        success "中文环境已配置完成，跳过重复操作"
        EXEC_STATUS["中文环境配置"]="已完成"
        echo -e "\n${WHITE}按回车返回菜单...${NC}"
        read -r
        return
    fi

    read -p "确认安装中文环境？[Y/n] " confirm
    confirm=${confirm:-Y}
    
    if [[ $confirm =~ ^[Yy]$ ]]; then
        apt install -y language-pack-zh-hans language-pack-zh-hans-base
        update-locale LANG=zh_CN.UTF-8 LC_ALL=zh_CN.UTF-8
        apt install -y fonts-wqy-microhei fonts-wqy-zenhei fonts-noto-cjk fonts-noto-color-emoji
        success "中文环境配置完成（语言包+字体）"
        EXEC_STATUS["中文环境配置"]="已完成"
        INSTALLED_FEATURES+=("中文环境（语言包+中文字体）")
    else
        warn "已跳过中文环境配置"
        EXEC_STATUS["中文环境配置"]="已跳过"
    fi
    echo -e "\n${WHITE}按回车返回菜单...${NC}"
    read -r
}

# 5. 桌面环境安装（含XRDP）
func_install_desktop() {
    refresh_status
    menu_title "桌面环境安装 - Xfce/GNOME"
    
    # 防重复判断（任意桌面已安装则跳过）
    if is_xfce_installed || is_gnome_installed; then
        local desk_type="Xfce"
        is_gnome_installed && desk_type="GNOME"
        success "${desk_type}桌面已安装，跳过重复操作"
        EXEC_STATUS["${desk_type}桌面安装"]="已完成"
        echo -e "\n${WHITE}按回车返回菜单...${NC}"
        read -r
        return
    fi

    echo "请选择要安装的桌面环境："
    echo "1) Xfce（轻量级，推荐服务器使用）"
    echo "2) GNOME（Ubuntu官方桌面）"
    echo "0) 取消"
    read -p "输入选项（0-2，默认0）：" desk_choice
    desk_choice=${desk_choice:-0}
    
    case $desk_choice in
        1)
            # 安装Xfce
            apt install -y xfce4 xfce4-goodies lightdm
            systemctl set-default graphical.target
            systemctl enable lightdm
            success "Xfce桌面安装完成"
            EXEC_STATUS["Xfce桌面安装"]="已完成"
            INSTALLED_FEATURES+=("Xfce桌面环境")
            
            # XRDP安装（带防重复）
            if is_xrdp_installed; then
                success "XRDP已安装，跳过重复操作"
                EXEC_STATUS["XRDP远程桌面"]="已完成"
            else
                read -p "是否安装XRDP远程桌面？[Y/n] " xrdp_confirm
                xrdp_confirm=${xrdp_confirm:-Y}
                if [[ $xrdp_confirm =~ ^[Yy]$ ]]; then
                    apt install -y xrdp
                    adduser xrdp ssl-cert
                    ufw allow 3389/tcp 2>/dev/null || true
                    systemctl enable --now xrdp
                    success "XRDP远程桌面安装完成"
                    success "连接地址：$(hostname -I | awk '{print $1}'):3389"
                    EXEC_STATUS["XRDP远程桌面"]="已完成"
                    INSTALLED_FEATURES+=("XRDP远程桌面（3389端口）")
                else
                    EXEC_STATUS["XRDP远程桌面"]="已跳过"
                fi
            fi
            ;;
        2)
            # 安装GNOME
            apt install -y ubuntu-desktop gnome-tweaks chrome-gnome-shell
            systemctl set-default graphical.target
            success "GNOME桌面安装完成"
            EXEC_STATUS["GNOME桌面安装"]="已完成"
            INSTALLED_FEATURES+=("GNOME桌面环境")
            
            # XRDP安装（带防重复）
            if is_xrdp_installed; then
                success "XRDP已安装，跳过重复操作"
                EXEC_STATUS["XRDP远程桌面"]="已完成"
            else
                read -p "是否安装XRDP远程桌面？[Y/n] " xrdp_confirm
                xrdp_confirm=${xrdp_confirm:-Y}
                if [[ $xrdp_confirm =~ ^[Yy]$ ]]; then
                    apt install -y xrdp
                    adduser xrdp ssl-cert
                    ufw allow 3389/tcp 2>/dev/null || true
                    systemctl enable --now xrdp
                    success "XRDP远程桌面安装完成"
                    success "连接地址：$(hostname -I | awk '{print $1}'):3389"
                    EXEC_STATUS["XRDP远程桌面"]="已完成"
                    INSTALLED_FEATURES+=("XRDP远程桌面（3389端口）")
                else
                    EXEC_STATUS["XRDP远程桌面"]="已跳过"
                fi
            fi
            ;;
        0)
            warn "已取消桌面环境安装"
            EXEC_STATUS["Xfce桌面安装"]="已跳过"
            EXEC_STATUS["GNOME桌面安装"]="已跳过"
            ;;
        *)
            error "无效选项"
            ;;
    esac
    echo -e "\n${WHITE}按回车返回菜单...${NC}"
    read -r
}

# 6. Docker安装（含加速）
func_install_docker() {
    refresh_status
    menu_title "Docker安装 - Docker + Compose + 镜像加速"
    
    # 防重复判断
    if is_docker_installed; then
        success "Docker已安装完成，跳过重复操作"
        EXEC_STATUS["Docker安装"]="已完成"
        
        # 检查Docker加速配置
        if is_docker_mirror_configured; then
            success "Docker加速已配置，跳过重复操作"
            EXEC_STATUS["Docker加速配置"]="已完成"
        fi
        echo -e "\n${WHITE}按回车返回菜单...${NC}"
        read -r
        return
    fi

    read -p "确认安装Docker + Docker Compose？[y/N] " confirm
    confirm=${confirm:-N}
    
    if [[ $confirm =~ ^[Yy]$ ]]; then
        # 安装Docker依赖
        apt install -y apt-transport-https ca-certificates curl gnupg-agent software-properties-common
        # Docker源配置
        curl -fsSL ${DOCKER_MIRROR}gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] ${DOCKER_MIRROR}linux/ubuntu ${RELEASE_VERSION} stable" | tee /etc/apt/sources.list.d/docker.list >/dev/null
        
        # 安装Docker
        apt update -y && apt install -y docker-ce docker-ce-cli containerd.io
        # 安装Compose
        curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
        
        success "Docker + Docker Compose安装完成"
        EXEC_STATUS["Docker安装"]="已完成"
        INSTALLED_FEATURES+=("Docker + Docker Compose")
        
        # Docker加速配置（带防重复）
        if is_docker_mirror_configured; then
            success "Docker加速已配置，跳过重复操作"
            EXEC_STATUS["Docker加速配置"]="已完成"
        else
            read -p "是否配置Docker镜像加速？[Y/n] " mirror_confirm
            mirror_confirm=${mirror_confirm:-Y}
            if [[ $mirror_confirm =~ ^[Yy]$ ]]; then
                echo -e "\n请选择Docker加速源："
                echo "1) 科大源（默认，无需申请）"
                echo "2) 网易云源"
                echo "3) 阿里云源（需自行申请）"
                echo "4) 自定义地址"
                read -p "输入选项（1-4，默认1）：" docker_mirror_choice
                docker_mirror_choice=${docker_mirror_choice:-1}
                
                case $docker_mirror_choice in
                    1) DOCKER_REGISTRY_MIRROR="https://docker.mirrors.ustc.edu.cn" ;;
                    2) DOCKER_REGISTRY_MIRROR="https://hub-mirror.c.163.com" ;;
                    3)
                        read -p "请输入阿里云加速地址：" ali_mirror
                        DOCKER_REGISTRY_MIRROR=${ali_mirror:-"https://docker.mirrors.ustc.edu.cn"}
                        ;;
                    4)
                        read -p "请输入自定义加速地址：" custom_mirror
                        [ -z "$custom_mirror" ] && error "自定义地址不能为空"
                        DOCKER_REGISTRY_MIRROR=$custom_mirror
                        ;;
                    *) DOCKER_REGISTRY_MIRROR="https://docker.mirrors.ustc.edu.cn" ;;
                esac
                
                # 配置加速
                mkdir -p /etc/docker
                cat >/etc/docker/daemon.json <<EOF
{
  "registry-mirrors": ["${DOCKER_REGISTRY_MIRROR}"]
}
EOF
                systemctl daemon-reload && systemctl restart docker
                success "Docker镜像加速配置完成：${DOCKER_REGISTRY_MIRROR}"
                EXEC_STATUS["Docker加速配置"]="已完成"
                INSTALLED_FEATURES+=("Docker镜像加速（${DOCKER_REGISTRY_MIRROR}）")
            else
                warn "已跳过Docker加速配置"
                EXEC_STATUS["Docker加速配置"]="已跳过"
            fi
        fi
        
        # 配置Docker权限
        systemctl enable --now docker
        usermod -aG docker $SUDO_USER 2>/dev/null || true
    else
        warn "已跳过Docker安装"
        EXEC_STATUS["Docker安装"]="已跳过"
        EXEC_STATUS["Docker加速配置"]="已跳过"
    fi
    echo -e "\n${WHITE}按回车返回菜单...${NC}"
    read -r
}

# ===================== 多级菜单定义 =====================
# 主菜单
main_menu() {
    while true; do
        refresh_status
        menu_head " 主菜单 - 功能选择 "
        echo "请选择要执行的功能（输入数字）："
        echo "1) 时区设置                2) 软件源更换"
        echo "3) 基础工具安装            4) 中文环境配置"
        echo "5) 桌面环境安装（含XRDP）  6) Docker安装（含加速）"
        echo "7) 查看已安装功能          0) 退出脚本"
        echo -e "${WHITE}"
        read -p "请输入选项（0-7）：" choice
        
        case $choice in
            1) func_set_timezone ;;
            2) func_change_mirror ;;
            3) func_install_base ;;
            4) func_install_chinese ;;
            5) func_install_desktop ;;
            6) func_install_docker ;;
            7) show_installed ;;
            0)
                info "感谢使用，脚本退出"
                exit 0
                ;;
            *)
                error "无效选项，请输入0-7之间的数字"
                ;;
        esac
    done
}

# ===================== 主流程 =====================
main() {
    # 前置检查
    check_root
    install_core_deps
    
    # 启动主菜单
    main_menu
}

# 启动脚本
main
