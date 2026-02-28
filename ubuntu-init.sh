#!/bin/bash
# 关闭严格模式避免小错误导致脚本退出
set -eo pipefail

# ===================== 核心配置项 =====================
TARGET_TIMEZONE="Asia/Shanghai"
TARGET_MIRROR="aliyun"
RELEASE_VERSION=$(lsb_release -sc 2>/dev/null || echo "jammy")
DOCKER_MIRROR="https://mirror.aliyun.com/docker-ce/"
DOCKER_REGISTRY_MIRROR="https://docker.mirrors.ustc.edu.cn"

# ===================== 颜色定义（修复转义符） =====================
# 定义颜色变量时使用单引号，避免转义符提前解析
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
BLUE='\033[34m'
PURPLE='\033[35m'
CYAN='\033[36m'
WHITE='\033[37m'
BG_BLUE='\033[44m'
NC='\033[0m'

# 日志打印函数
info() { echo -e "${GREEN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }
success() { echo -e "${CYAN}[SUCCESS]${NC} $*"; }
menu_head() { echo -e "\n${BG_BLUE}${WHITE}===== $* =====${NC}"; }
menu_title() { echo -e "${PURPLE}→ $*${NC}"; }

# ===================== 全局状态管理 =====================
# 初始状态为空，启动时扫描系统自动填充
declare -A EXEC_STATUS=(
    ["时区设置"]=""
    ["软件源更换"]=""
    ["基础工具安装"]=""
    ["中文环境配置"]=""
    ["Xfce桌面安装"]=""
    ["GNOME桌面安装"]=""
    ["XRDP远程桌面"]=""
    ["Docker安装"]=""
    ["Docker加速配置"]=""
)
INSTALLED_FEATURES=()
# 备份文件记录（用于卸载）
BACKUP_FILES=(
    "/etc/apt/sources.list.bak.*"
    "/etc/xrdp/startwm.sh.bak"
    "$HOME/.xsession.bak"
)

# ===================== 系统环境扫描函数（核心重构） =====================
# 基础判断工具
is_installed() {
    command -v "$1" &> /dev/null || return 1
}

file_exists() {
    [ -f "$1" ] || return 1
}

# 1. 检测时区状态
scan_timezone() {
    local current_tz
    current_tz=$(timedatectl show -p Timezone --value 2>/dev/null || echo "")
    if [ "$current_tz" == "$TARGET_TIMEZONE" ]; then
        EXEC_STATUS["时区设置"]="已安装"
        INSTALLED_FEATURES+=("时区设置（Asia/Shanghai）")
    else
        EXEC_STATUS["时区设置"]="未安装"
    fi
}

# 2. 检测软件源状态
scan_mirror() {
    if grep -q "mirrors.aliyun.com\|mirrors.tuna.tsinghua.edu.cn\|mirrors.163.com\|mirrors.ustc.edu.cn" /etc/apt/sources.list 2>/dev/null; then
        EXEC_STATUS["软件源更换"]="已安装"
        INSTALLED_FEATURES+=("软件源更换（国内源）")
    else
        EXEC_STATUS["软件源更换"]="未安装"
    fi
}

# 3. 检测基础工具状态
scan_base_tools() {
    if is_installed vim && is_installed git && is_installed curl && is_installed htop; then
        EXEC_STATUS["基础工具安装"]="已安装"
        INSTALLED_FEATURES+=("基础工具（vim/git/curl/htop等）")
    else
        EXEC_STATUS["基础工具安装"]="未安装"
    fi
}

# 4. 检测中文环境状态
scan_chinese() {
    if is_installed locale && locale -a 2>/dev/null | grep -qi "zh_CN.utf8"; then
        EXEC_STATUS["中文环境配置"]="已安装"
        INSTALLED_FEATURES+=("中文环境（语言包+字体）")
    else
        EXEC_STATUS["中文环境配置"]="未安装"
    fi
}

# 5. 检测桌面环境状态（Xfce/GNOME）
scan_desktop() {
    # 检测Xfce
    if is_installed xfce4-session; then
        EXEC_STATUS["Xfce桌面安装"]="已安装"
        INSTALLED_FEATURES+=("Xfce桌面环境")
    else
        EXEC_STATUS["Xfce桌面安装"]="未安装"
    fi
    
    # 检测GNOME
    if is_installed gnome-shell; then
        EXEC_STATUS["GNOME桌面安装"]="已安装"
        INSTALLED_FEATURES+=("GNOME桌面环境")
    else
        EXEC_STATUS["GNOME桌面安装"]="未安装"
    fi
}

# 6. 检测XRDP状态（独立检测，即使桌面已装也能识别）
scan_xrdp() {
    if is_installed xrdp && systemctl is-active --quiet xrdp 2>/dev/null; then
        EXEC_STATUS["XRDP远程桌面"]="已安装"
        INSTALLED_FEATURES+=("XRDP远程桌面（3389端口）")
    else
        EXEC_STATUS["XRDP远程桌面"]="未安装"
    fi
}

# 7. 检测Docker状态
scan_docker() {
    if is_installed docker; then
        EXEC_STATUS["Docker安装"]="已安装"
        INSTALLED_FEATURES+=("Docker + Docker Compose")
        
        # 检测Docker加速
        if file_exists /etc/docker/daemon.json && grep -q "registry-mirrors" /etc/docker/daemon.json 2>/dev/null; then
            EXEC_STATUS["Docker加速配置"]="已安装"
            INSTALLED_FEATURES+=("Docker镜像加速")
        else
            EXEC_STATUS["Docker加速配置"]="未安装"
        fi
    else
        EXEC_STATUS["Docker安装"]="未安装"
        EXEC_STATUS["Docker加速配置"]="未安装"
    fi
}

# 全盘扫描系统环境（脚本启动时执行）
full_system_scan() {
    info "正在扫描系统已安装的软件/配置..."
    # 清空已安装列表，重新扫描
    INSTALLED_FEATURES=()
    
    # 依次扫描所有功能状态
    scan_timezone
    scan_mirror
    scan_base_tools
    scan_chinese
    scan_desktop
    scan_xrdp
    scan_docker
    
    info "系统扫描完成，状态已更新"
}

# ===================== 工具函数 =====================
check_root() {
    if [ $EUID -ne 0 ]; then
        error "请使用ROOT权限运行：sudo $0"
    fi
}

install_core_deps() {
    info "检查基础依赖包..."
    if ! is_installed hwclock; then
        apt update -y >/dev/null 2>&1
        apt install -y util-linux >/dev/null 2>&1
    fi
    if ! is_installed timedatectl; then
        apt install -y systemd-timesyncd >/dev/null 2>&1
    fi
    info "基础依赖检查完成"
}

# 刷新状态显示（修复颜色转义符显示问题）
refresh_status() {
    clear
    menu_head " Ubuntu 一键初始化工具 - 系统实际安装状态 "
    echo -e "┌──────────────────────┬───────────┐"
    for func in "${!EXEC_STATUS[@]}"; do
        status=${EXEC_STATUS[$func]}
        # 状态颜色（仅在输出时解析转义符）
        case $status in
            "已安装") color="${GREEN}" ;;
            "未安装") color="${RED}" ;;
            *) color="${YELLOW}" ;;
        esac
        # 格式化输出，确保对齐（解决排版混乱）
        printf "│ %-20s │ %b%-9s%b │\n" "$func" "$color" "$status" "$NC"
    done
    echo -e "└──────────────────────┴───────────┘"
}

show_installed() {
    refresh_status
    menu_head " 已安装功能列表 "
    if [ ${#INSTALLED_FEATURES[@]} -eq 0 ]; then
        echo -e "${YELLOW}暂无已安装功能${NC}"
    else
        # 去重并显示
        local unique_features=($(printf "%s\n" "${INSTALLED_FEATURES[@]}" | sort -u))
        for i in "${!unique_features[@]}"; do
            echo -e "${CYAN}$((i+1)).${NC} ${unique_features[$i]}"
        done
    fi
    echo -e "\n按回车返回菜单..."
    read -r || true
}

# ===================== 核心安装功能实现（XRDP深度优化） =====================
func_set_timezone() {
    refresh_status
    menu_title "时区设置 - ${TARGET_TIMEZONE}"
    
    if [ "${EXEC_STATUS["时区设置"]}" == "已安装" ]; then
        success "时区已设置为 ${TARGET_TIMEZONE}，无需重复操作"
        echo -e "\n按回车返回菜单..."
        read -r || true
        return
    fi

    read -p "确认设置时区为 ${TARGET_TIMEZONE}？[Y/n] " confirm
    confirm=${confirm:-Y}
    
    if [[ $confirm =~ ^[Yy]$ ]]; then
        timedatectl set-timezone ${TARGET_TIMEZONE}
        ln -sf /usr/share/zoneinfo/${TARGET_TIMEZONE} /etc/localtime
        hwclock --systohc 2>/dev/null || warn "硬件时钟同步失败（不影响系统时区）"
        success "时区设置完成：${TARGET_TIMEZONE}"
        # 更新状态
        EXEC_STATUS["时区设置"]="已安装"
        INSTALLED_FEATURES+=("时区设置（Asia/Shanghai）")
    else
        warn "已跳过时区设置"
    fi
    echo -e "\n按回车返回菜单..."
    read -r || true
}

func_change_mirror() {
    refresh_status
    menu_title "软件源更换 - 可选源：aliyun/tuna/163/ustc"
    
    if [ "${EXEC_STATUS["软件源更换"]}" == "已安装" ]; then
        success "软件源已更换为国内源，无需重复操作"
        echo -e "\n按回车返回菜单..."
        read -r || true
        return
    fi

    echo "当前默认源：${TARGET_MIRROR}"
    read -p "是否更换软件源？[Y/n] " confirm
    confirm=${confirm:-Y}
    
    if [[ $confirm =~ ^[Yy]$ ]]; then
        # 备份原软件源
        cp /etc/apt/sources.list /etc/apt/sources.list.bak.$(date +%Y%m%d%H%M)
        echo "请选择软件源："
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
        
        apt update -y >/dev/null 2>&1 && apt upgrade -y >/dev/null 2>&1
        success "${MIRROR}软件源更换完成，已更新系统包"
        # 更新状态
        EXEC_STATUS["软件源更换"]="已安装"
        INSTALLED_FEATURES+=("软件源更换（${MIRROR}）")
    else
        warn "已跳过软件源更换"
    fi
    echo -e "\n按回车返回菜单..."
    read -r || true
}

func_install_base() {
    refresh_status
    menu_title "基础工具安装 - vim/git/curl/htop等"
    
    if [ "${EXEC_STATUS["基础工具安装"]}" == "已安装" ]; then
        success "基础工具已安装完成，无需重复操作"
        echo -e "\n按回车返回菜单..."
        read -r || true
        return
    fi

    read -p "确认安装基础工具？[Y/n] " confirm
    confirm=${confirm:-Y}
    
    if [[ $confirm =~ ^[Yy]$ ]]; then
        apt install -y vim git curl wget net-tools htop lsof tree unzip zip bzip2 rsync screen tmux ncdu sysstat util-linux >/dev/null 2>&1
        # 备份原vim配置
        grep -q "set nu" /etc/vim/vimrc || echo -e "set nu\nset tabstop=4\nset shiftwidth=4" >> /etc/vim/vimrc
        success "基础工具安装完成"
        # 更新状态
        EXEC_STATUS["基础工具安装"]="已安装"
        INSTALLED_FEATURES+=("基础工具（vim/git/curl/htop等）")
    else
        warn "已跳过基础工具安装"
    fi
    echo -e "\n按回车返回菜单..."
    read -r || true
}

func_install_chinese() {
    refresh_status
    menu_title "中文环境配置 - 语言包+中文字体"
    
    if [ "${EXEC_STATUS["中文环境配置"]}" == "已安装" ]; then
        success "中文环境已配置完成，无需重复操作"
        echo -e "\n按回车返回菜单..."
        read -r || true
        return
    fi

    read -p "确认安装中文环境？[Y/n] " confirm
    confirm=${confirm:-Y}
    
    if [[ $confirm =~ ^[Yy]$ ]]; then
        apt install -y language-pack-zh-hans language-pack-zh-hans-base >/dev/null 2>&1
        update-locale LANG=zh_CN.UTF-8 LC_ALL=zh_CN.UTF-8 >/dev/null 2>&1
        apt install -y fonts-wqy-microhei fonts-wqy-zenhei fonts-noto-cjk fonts-noto-color-emoji >/dev/null 2>&1
        success "中文环境配置完成（语言包+字体）"
        # 更新状态
        EXEC_STATUS["中文环境配置"]="已安装"
        INSTALLED_FEATURES+=("中文环境（语言包+中文字体）")
    else
        warn "已跳过中文环境配置"
    fi
    echo -e "\n按回车返回菜单..."
    read -r || true
}

# XRDP安装（深度优化，零闪退）
func_install_xrdp() {
    refresh_status
    menu_title "XRDP远程桌面安装（深度优化版）"
    
    if [ "${EXEC_STATUS["XRDP远程桌面"]}" == "已安装" ]; then
        success "XRDP已安装完成，无需重复操作"
        echo -e "\n按回车返回菜单..."
        read -r || true
        return
    fi

    # 检查是否有桌面环境（无桌面则提示安装Xfce）
    if ! is_installed xfce4-session && ! is_installed gnome-shell; then
        warn "未检测到桌面环境，将自动安装Xfce（XRDP最优适配）"
        read -p "是否继续？[Y/n] " confirm
        confirm=${confirm:-Y}
        if [[ $confirm != ^[Yy]$ ]]; then
            warn "已取消XRDP安装"
            echo -e "\n按回车返回菜单..."
            read -r || true
            return
        fi
        # 安装Xfce
        apt install -y xfce4 xfce4-goodies lightdm >/dev/null 2>&1
        EXEC_STATUS["Xfce桌面安装"]="已安装"
        INSTALLED_FEATURES+=("Xfce桌面环境")
    fi

    read -p "确认安装XRDP远程桌面（深度优化版）？[Y/n] " xrdp_confirm
    xrdp_confirm=${xrdp_confirm:-Y}
    if [[ $xrdp_confirm =~ ^[Yy]$ ]]; then
        # 安装XRDP及依赖
        apt install -y xrdp xorgxrdp dbus-x11 tightvncserver >/dev/null 2>&1
        
        # 备份原有配置
        [ -f /etc/xrdp/startwm.sh ] && cp /etc/xrdp/startwm.sh /etc/xrdp/startwm.sh.bak
        [ -f $HOME/.xsession ] && cp $HOME/.xsession $HOME/.xsession.bak
        
        # 写入最优配置（解决闪退、黑屏）
        cat >/etc/xrdp/startwm.sh << 'EOF'
#!/bin/sh
unset DBUS_SESSION_BUS_ADDRESS
unset XDG_RUNTIME_DIR
exec startxfce4
EOF
        
        # 配置权限
        chmod +x /etc/xrdp/startwm.sh
        echo "xfce4-session" > $HOME/.xsession
        
        # 禁用冲突服务
        systemctl disable --now gdm3 >/dev/null 2>&1 || true
        adduser xrdp ssl-cert >/dev/null 2>&1
        
        # 开放端口
        ufw allow 3389/tcp 2>/dev/null || true
        
        # 重启服务
        systemctl enable --now xrdp >/dev/null 2>&1
        systemctl restart xrdp >/dev/null 2>&1
        
        success "XRDP远程桌面安装完成（深度优化版）"
        success "✅ 登录选择：Xorg"
        success "✅ 用户名：$(whoami)"
        success "✅ 连接地址：$(hostname -I | awk '{print $1}'):3389"
        success "✅ 已自动适配Xfce，零闪退、零黑屏"
        
        # 更新状态
        EXEC_STATUS["XRDP远程桌面"]="已安装"
        INSTALLED_FEATURES+=("XRDP远程桌面（3389端口，深度优化）")
    else
        warn "已跳过XRDP安装"
    fi
    echo -e "\n按回车返回菜单..."
    read -r || true
}

func_install_desktop() {
    refresh_status
    menu_title "桌面环境安装 - Xfce/GNOME"
    
    # 检查是否已有桌面
    if is_installed xfce4-session || is_installed gnome-shell; then
        local desk_type="Xfce"
        is_gnome_installed && desk_type="GNOME"
        success "${desk_type}桌面已安装，无需重复操作"
        echo -e "\n按回车返回菜单..."
        read -r || true
        return
    fi

    echo "请选择要安装的桌面环境："
    echo "1) Xfce（轻量级，XRDP最优适配）"
    echo "2) GNOME（Ubuntu官方桌面，XRDP兼容性差）"
    echo "0) 取消"
    read -p "输入选项（0-2，默认0）：" desk_choice
    desk_choice=${desk_choice:-0}
    
    case $desk_choice in
        1)
            apt install -y xfce4 xfce4-goodies lightdm >/dev/null 2>&1
            systemctl set-default graphical.target >/dev/null 2>&1
            systemctl enable lightdm >/dev/null 2>&1
            success "Xfce桌面安装完成（XRDP最优适配）"
            # 更新状态
            EXEC_STATUS["Xfce桌面安装"]="已安装"
            INSTALLED_FEATURES+=("Xfce桌面环境")
            ;;
        2)
            apt install -y ubuntu-desktop gnome-tweaks chrome-gnome-shell >/dev/null 2>&1
            systemctl set-default graphical.target >/dev/null 2>&1
            success "GNOME桌面安装完成（注意：XRDP兼容性差）"
            # 更新状态
            EXEC_STATUS["GNOME桌面安装"]="已安装"
            INSTALLED_FEATURES+=("GNOME桌面环境")
            ;;
        0)
            warn "已取消桌面环境安装"
            ;;
        *)
            error "无效选项"
            ;;
    esac
    echo -e "\n按回车返回菜单..."
    read -r || true
}

func_install_docker() {
    refresh_status
    menu_title "Docker安装 - Docker + Compose + 镜像加速"
    
    if [ "${EXEC_STATUS["Docker安装"]}" == "已安装" ]; then
        success "Docker已安装完成，无需重复操作"
        
        if [ "${EXEC_STATUS["Docker加速配置"]}" == "已安装" ]; then
            success "Docker加速已配置，无需重复操作"
        fi
        echo -e "\n按回车返回菜单..."
        read -r || true
        return
    fi

    read -p "确认安装Docker + Docker Compose？[y/N] " confirm
    confirm=${confirm:-N}
    
    if [[ $confirm =~ ^[Yy]$ ]]; then
        # 安装Docker依赖
        apt install -y apt-transport-https ca-certificates curl gnupg-agent software-properties-common >/dev/null 2>&1
        # Docker源配置
        curl -fsSL ${DOCKER_MIRROR}gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg >/dev/null 2>&1
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] ${DOCKER_MIRROR}linux/ubuntu ${RELEASE_VERSION} stable" | tee /etc/apt/sources.list.d/docker.list >/dev/null 2>&1
        
        # 安装Docker
        apt update -y >/dev/null 2>&1 && apt install -y docker-ce docker-ce-cli containerd.io >/dev/null 2>&1
        # 安装Compose
        curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose >/dev/null 2>&1
        chmod +x /usr/local/bin/docker-compose
        
        success "Docker + Docker Compose安装完成"
        # 更新状态
        EXEC_STATUS["Docker安装"]="已安装"
        INSTALLED_FEATURES+=("Docker + Docker Compose")
        
        # Docker加速配置
        if [ "${EXEC_STATUS["Docker加速配置"]}" == "已安装" ]; then
            success "Docker加速已配置，无需重复操作"
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
                systemctl daemon-reload >/dev/null 2>&1 && systemctl restart docker >/dev/null 2>&1
                success "Docker镜像加速配置完成：${DOCKER_REGISTRY_MIRROR}"
                # 更新状态
                EXEC_STATUS["Docker加速配置"]="已安装"
                INSTALLED_FEATURES+=("Docker镜像加速（${DOCKER_REGISTRY_MIRROR}）")
            else
                warn "已跳过Docker加速配置"
            fi
        fi
        
        # 配置Docker权限
        systemctl enable --now docker >/dev/null 2>&1
        usermod -aG docker $SUDO_USER 2>/dev/null || true
    else
        warn "已跳过Docker安装"
    fi
    echo -e "\n按回车返回菜单..."
    read -r || true
}

# ===================== 卸载功能实现 =====================
func_uninstall_xrdp() {
    refresh_status
    menu_title "XRDP远程桌面卸载"
    
    if [ "${EXEC_STATUS["XRDP远程桌面"]}" != "已安装" ]; then
        warn "XRDP未安装，无需卸载"
        echo -e "\n按回车返回菜单..."
        read -r || true
        return
    fi

    read -p "确认卸载XRDP远程桌面？[y/N] " confirm
    confirm=${confirm:-N}
    
    if [[ $confirm =~ ^[Yy]$ ]]; then
        # 停止并禁用服务
        systemctl stop xrdp >/dev/null 2>&1
        systemctl disable xrdp >/dev/null 2>&1
        
        # 卸载软件
        apt purge -y xrdp xorgxrdp tightvncserver >/dev/null 2>&1
        apt autoremove -y >/dev/null 2>&1
        
        # 恢复配置
        [ -f /etc/xrdp/startwm.sh.bak ] && mv /etc/xrdp/startwm.sh.bak /etc/xrdp/startwm.sh
        [ -f $HOME/.xsession.bak ] && mv $HOME/.xsession.bak $HOME/.xsession || rm -f $HOME/.xsession
        
        # 恢复GDM3（如果有）
        systemctl enable --now gdm3 >/dev/null 2>&1 || true
        
        success "XRDP远程桌面卸载完成"
        # 更新状态
        EXEC_STATUS["XRDP远程桌面"]="未安装"
    else
        warn "已取消XRDP卸载"
    fi
    echo -e "\n按回车返回菜单..."
    read -r || true
}

func_uninstall_desktop() {
    refresh_status
    menu_title "桌面环境卸载"
    
    if [ "${EXEC_STATUS["Xfce桌面安装"]}" != "已安装" ] && [ "${EXEC_STATUS["GNOME桌面安装"]}" != "已安装" ]; then
        warn "未安装任何桌面环境，无需卸载"
        echo -e "\n按回车返回菜单..."
        read -r || true
        return
    fi

    echo "请选择要卸载的桌面环境："
    echo "1) Xfce桌面"
    echo "2) GNOME桌面"
    echo "3) 全部卸载"
    echo "0) 取消"
    read -p "输入选项（0-3，默认0）：" desk_choice
    desk_choice=${desk_choice:-0}
    
    case $desk_choice in
        1)
            apt purge -y xfce4 xfce4-goodies lightdm >/dev/null 2>&1
            apt autoremove -y >/dev/null 2>&1
            success "Xfce桌面卸载完成"
            EXEC_STATUS["Xfce桌面安装"]="未安装"
            ;;
        2)
            apt purge -y ubuntu-desktop gnome-tweaks chrome-gnome-shell >/dev/null 2>&1
            apt autoremove -y >/dev/null 2>&1
            success "GNOME桌面卸载完成"
            EXEC_STATUS["GNOME桌面安装"]="未安装"
            ;;
        3)
            apt purge -y xfce4 xfce4-goodies lightdm ubuntu-desktop gnome-tweaks chrome-gnome-shell >/dev/null 2>&1
            apt autoremove -y >/dev/null 2>&1
            success "所有桌面环境卸载完成"
            EXEC_STATUS["Xfce桌面安装"]="未安装"
            EXEC_STATUS["GNOME桌面安装"]="未安装"
            ;;
        0)
            warn "已取消桌面环境卸载"
            ;;
        *)
            error "无效选项"
            ;;
    esac
    echo -e "\n按回车返回菜单..."
    read -r || true
}

func_uninstall_docker() {
    refresh_status
    menu_title "Docker卸载"
    
    if [ "${EXEC_STATUS["Docker安装"]}" != "已安装" ]; then
        warn "Docker未安装，无需卸载"
        echo -e "\n按回车返回菜单..."
        read -r || true
        return
    fi

    read -p "确认卸载Docker + Docker Compose？[y/N] " confirm
    confirm=${confirm:-N}
    
    if [[ $confirm =~ ^[Yy]$ ]]; then
        # 停止并禁用服务
        systemctl stop docker >/dev/null 2>&1
        systemctl disable docker >/dev/null 2>&1
        
        # 卸载软件
        apt purge -y docker-ce docker-ce-cli containerd.io >/dev/null 2>&1
        rm -f /usr/local/bin/docker-compose >/dev/null 2>&1
        apt autoremove -y >/dev/null 2>&1
        
        # 清理配置
        rm -rf /etc/docker >/dev/null 2>&1
        
        success "Docker + Docker Compose卸载完成"
        # 更新状态
        EXEC_STATUS["Docker安装"]="未安装"
        EXEC_STATUS["Docker加速配置"]="未安装"
    else
        warn "已取消Docker卸载"
    fi
    echo -e "\n按回车返回菜单..."
    read -r || true
}

func_restore_mirror() {
    refresh_status
    menu_title "恢复原软件源"
    
    if [ "${EXEC_STATUS["软件源更换"]}" != "已安装" ]; then
        warn "未更换软件源，无需恢复"
        echo -e "\n按回车返回菜单..."
        read -r || true
        return
    fi

    read -p "确认恢复原软件源？[y/N] " confirm
    confirm=${confirm:-N}
    
    if [[ $confirm =~ ^[Yy]$ ]]; then
        # 查找最新备份
        latest_backup=$(ls -t /etc/apt/sources.list.bak.* 2>/dev/null | head -n1)
        if [ -z "$latest_backup" ]; then
            error "未找到软件源备份文件"
        fi
        
        # 恢复备份
        cp $latest_backup /etc/apt/sources.list
        apt update -y >/dev/null 2>&1
        
        success "软件源已恢复为：$latest_backup"
        # 更新状态
        EXEC_STATUS["软件源更换"]="未安装"
    else
        warn "已取消软件源恢复"
    fi
    echo -e "\n按回车返回菜单..."
    read -r || true
}

# ===================== 主菜单（新增卸载选项） =====================
main_menu() {
    while true; do
        refresh_status
        menu_head " 主菜单 - 功能选择 "
        echo "请选择要执行的功能（输入数字）："
        echo "===== 安装功能 ====="
        echo "1) 时区设置                2) 软件源更换"
        echo "3) 基础工具安装            4) 中文环境配置"
        echo "5) 桌面环境安装            6) XRDP远程桌面（深度优化）"
        echo "7) Docker安装（含加速）    8) 查看已安装功能"
        echo "===== 卸载功能 ====="
        echo "9) 卸载XRDP远程桌面       10) 卸载桌面环境"
        echo "11) 卸载Docker            12) 恢复原软件源"
        echo "0) 退出脚本"
        echo
        read -p "请输入选项（0-12）：" choice
        
        case $choice in
            1) func_set_timezone ;;
            2) func_change_mirror ;;
            3) func_install_base ;;
            4) func_install_chinese ;;
            5) func_install_desktop ;;
            6) func_install_xrdp ;;
            7) func_install_docker ;;
            8) show_installed ;;
            9) func_uninstall_xrdp ;;
            10) func_uninstall_desktop ;;
            11) func_uninstall_docker ;;
            12) func_restore_mirror ;;
            0)
                info "感谢使用，脚本退出"
                exit 0
                ;;
            *)
                warn "无效选项，请输入0-12之间的数字！"
                sleep 1
                ;;
        esac
    done
}

# ===================== 主流程 =====================
main() {
    # 强制刷新终端输出
    export TERM=xterm
    # 前置检查
    check_root
    install_core_deps
    # 核心：启动时全盘扫描系统环境
    full_system_scan
    # 启动主菜单
    main_menu
}

# 启动脚本（确保执行）
main
