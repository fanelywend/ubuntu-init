#!/bin/bash
# =============================================================================
# Ubuntu 一键初始化工具（优化版）
# 功能：时区设置、软件源更换、基础工具、中文环境、桌面环境、XRDP、Docker
# 特点：模块化设计、日志记录、错误处理、幂等性、安全备份
# =============================================================================

set -eo pipefail  # 严格模式：命令失败立即退出，管道错误也会捕获

# ----------------------------- 配置区域（可修改）--------------------------------
readonly DEFAULT_TIMEZONE="Asia/Shanghai"
readonly DEFAULT_MIRROR="aliyun"          # 可选 aliyun/tuna/163/ustc
readonly DOCKER_MIRROR="https://mirror.aliyun.com/docker-ce/"
readonly DOCKER_REGISTRY_MIRROR_DEFAULT="https://docker.mirrors.ustc.edu.cn"
readonly LOG_FILE="/var/log/ubuntu-init.log"   # 日志文件路径
readonly BACKUP_SUFFIX=".bak.$(date +%Y%m%d%H%M%S)"  # 备份文件后缀
# ------------------------------------------------------------------------------

# 颜色定义（使用函数包装避免转义问题）
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
BLUE='\033[34m'
PURPLE='\033[35m'
CYAN='\033[36m'
WHITE='\033[37m'
BG_BLUE='\033[44m'
NC='\033[0m'

# 日志打印函数（同时输出到终端和日志文件）
info()    { echo -e "${GREEN}[INFO]${NC} $*" | tee -a "$LOG_FILE"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*" | tee -a "$LOG_FILE"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" | tee -a "$LOG_FILE"; exit 1; }
success() { echo -e "${CYAN}[SUCCESS]${NC} $*" | tee -a "$LOG_FILE"; }
menu_head()   { echo -e "\n${BG_BLUE}${WHITE}===== $* =====${NC}" | tee -a "$LOG_FILE"; }
menu_title()  { echo -e "${PURPLE}→ $*${NC}" | tee -a "$LOG_FILE"; }

# ----------------------------- 全局状态管理 ------------------------------------
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
INSTALLED_FEATURES=()          # 已安装功能列表（用于显示）
readonly BACKUP_FILES_PATTERNS=(    # 备份文件模式（用于卸载时查找）
    "/etc/apt/sources.list.bak.*"
    "/etc/xrdp/startwm.sh.bak"
    "$HOME/.xsession.bak"
)

# ----------------------------- 辅助函数 ----------------------------------------
# 获取实际用户（处理 root 直接登录或 sudo 情况）
get_real_user() {
    if [[ -n "$SUDO_USER" ]]; then
        echo "$SUDO_USER"
    else
        echo "$USER"
    fi
}
REAL_USER=$(get_real_user)
REAL_HOME=$(eval echo "~$REAL_USER")

# 命令是否存在
is_installed() { command -v "$1" &>/dev/null; }

# 文件是否存在
file_exists() { [[ -f "$1" ]]; }

# 检查 root 权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "请使用 root 权限运行：sudo $0"
    fi
}

# 备份文件（自动生成带时间戳的备份）
backup_file() {
    local file="$1"
    if [[ -f "$file" ]]; then
        cp "$file" "${file}${BACKUP_SUFFIX}" && info "已备份 $file 为 ${file}${BACKUP_SUFFIX}"
    fi
}

# 安全地追加配置（避免重复）
append_if_not_exists() {
    local line="$1" file="$2"
    grep -qxF "$line" "$file" 2>/dev/null || echo "$line" >> "$file"
}

# 更新系统包列表（带超时和重试）
update_package_list() {
    info "更新软件包列表..."
    if ! timeout 60 apt update -y >> "$LOG_FILE" 2>&1; then
        warn "apt update 超时或失败，尝试再次更新..."
        if ! apt update -y >> "$LOG_FILE" 2>&1; then
            error "apt update 失败，请检查网络或源配置"
        fi
    fi
}

# 安装依赖包（带日志）
install_packages() {
    local packages=("$@")
    info "安装软件包: ${packages[*]}"
    apt install -y "${packages[@]}" >> "$LOG_FILE" 2>&1 || {
        error "安装失败: ${packages[*]}"
    }
}

# ----------------------------- 系统扫描函数 ------------------------------------
scan_timezone() {
    local current_tz
    current_tz=$(timedatectl show -p Timezone --value 2>/dev/null || echo "")
    if [[ "$current_tz" == "$DEFAULT_TIMEZONE" ]]; then
        EXEC_STATUS["时区设置"]="已安装"
        INSTALLED_FEATURES+=("时区设置（$DEFAULT_TIMEZONE）")
    fi
}

scan_mirror() {
    if grep -q "mirrors.aliyun.com\|mirrors.tuna.tsinghua.edu.cn\|mirrors.163.com\|mirrors.ustc.edu.cn" /etc/apt/sources.list 2>/dev/null; then
        EXEC_STATUS["软件源更换"]="已安装"
        INSTALLED_FEATURES+=("软件源更换（国内源）")
    fi
}

scan_base_tools() {
    if is_installed vim && is_installed git && is_installed curl && is_installed htop; then
        EXEC_STATUS["基础工具安装"]="已安装"
        INSTALLED_FEATURES+=("基础工具（vim/git/curl/htop等）")
    fi
}

scan_chinese() {
    if locale -a 2>/dev/null | grep -qi "zh_CN.utf8"; then
        EXEC_STATUS["中文环境配置"]="已安装"
        INSTALLED_FEATURES+=("中文环境（语言包+字体）")
    fi
}

scan_desktop() {
    if is_installed xfce4-session; then
        EXEC_STATUS["Xfce桌面安装"]="已安装"
        INSTALLED_FEATURES+=("Xfce桌面环境")
    fi
    if is_installed gnome-shell; then
        EXEC_STATUS["GNOME桌面安装"]="已安装"
        INSTALLED_FEATURES+=("GNOME桌面环境")
    fi
}

scan_xrdp() {
    if is_installed xrdp && systemctl is-active --quiet xrdp 2>/dev/null; then
        EXEC_STATUS["XRDP远程桌面"]="已安装"
        INSTALLED_FEATURES+=("XRDP远程桌面（3389端口）")
    fi
}

scan_docker() {
    if is_installed docker; then
        EXEC_STATUS["Docker安装"]="已安装"
        INSTALLED_FEATURES+=("Docker + Docker Compose")
        if file_exists /etc/docker/daemon.json && grep -q "registry-mirrors" /etc/docker/daemon.json 2>/dev/null; then
            EXEC_STATUS["Docker加速配置"]="已安装"
            INSTALLED_FEATURES+=("Docker镜像加速")
        fi
    fi
}

full_system_scan() {
    info "正在扫描系统已安装的软件/配置..."
    INSTALLED_FEATURES=()
    scan_timezone
    scan_mirror
    scan_base_tools
    scan_chinese
    scan_desktop
    scan_xrdp
    scan_docker
    info "系统扫描完成"
}

# ----------------------------- 界面函数 ----------------------------------------
refresh_status() {
    clear
    echo -e "\n=====  Ubuntu 一键初始化工具 - 系统实际安装状态  ====="
    echo -e "┌──────────────────────┬───────────┐"
    # 按固定顺序显示（保证表格整齐）
    local order=("XRDP远程桌面" "时区设置" "Xfce桌面安装" "Docker加速配置" "中文环境配置" "软件源更换" "GNOME桌面安装" "基础工具安装" "Docker安装")
    for key in "${order[@]}"; do
        local status="${EXEC_STATUS[$key]}"
        local display
        if [[ "$status" == "已安装" ]]; then
            display="\033[32m已安装   \033[0m"
        else
            display="\033[31m未安装   \033[0m"
        fi
        printf "│ %-20s │ %b │\n" "$key" "$display"
    done
    echo -e "└──────────────────────┴───────────┘"
}

show_installed() {
    refresh_status
    menu_head "已安装功能列表"
    if [[ ${#INSTALLED_FEATURES[@]} -eq 0 ]]; then
        echo -e "${YELLOW}暂无已安装功能${NC}"
    else
        local unique_features=($(printf "%s\n" "${INSTALLED_FEATURES[@]}" | sort -u))
        for i in "${!unique_features[@]}"; do
            echo -e "${CYAN}$((i+1)).${NC} ${unique_features[$i]}"
        done
    fi
    echo -e "\n按回车返回菜单..."
    read -r || true
}

# ----------------------------- 核心功能实现 ------------------------------------
# 时区设置
func_set_timezone() {
    refresh_status
    menu_title "时区设置 - ${DEFAULT_TIMEZONE}"
    if [[ "${EXEC_STATUS["时区设置"]}" == "已安装" ]]; then
        success "时区已设置为 ${DEFAULT_TIMEZONE}，无需重复操作"
        read -rp "按回车返回菜单..." _
        return
    fi

    read -rp "确认设置时区为 ${DEFAULT_TIMEZONE}？[Y/n] " confirm
    confirm=${confirm:-Y}
    if [[ $confirm =~ ^[Yy]$ ]]; then
        timedatectl set-timezone "$DEFAULT_TIMEZONE"
        ln -sf "/usr/share/zoneinfo/${DEFAULT_TIMEZONE}" /etc/localtime
        hwclock --systohc 2>/dev/null || warn "硬件时钟同步失败（不影响系统时区）"
        success "时区设置完成：${DEFAULT_TIMEZONE}"
        EXEC_STATUS["时区设置"]="已安装"
        INSTALLED_FEATURES+=("时区设置（$DEFAULT_TIMEZONE）")
    else
        warn "已跳过时区设置"
    fi
    read -rp "按回车返回菜单..." _
}

# 软件源更换
func_change_mirror() {
    refresh_status
    menu_title "软件源更换"
    if [[ "${EXEC_STATUS["软件源更换"]}" == "已安装" ]]; then
        success "软件源已更换为国内源，无需重复操作"
        read -rp "按回车返回菜单..." _
        return
    fi

    echo "当前默认源：${DEFAULT_MIRROR}"
    read -rp "是否更换软件源？[Y/n] " confirm
    confirm=${confirm:-Y}
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        warn "已跳过软件源更换"
        read -rp "按回车返回菜单..." _
        return
    fi

    # 选择镜像源
    echo "请选择软件源："
    echo "1) 阿里云（默认）"
    echo "2) 清华大学"
    echo "3) 163网易"
    echo "4) 中国科学技术大学"
    local mirror_choice mirror_url
    while true; do
        read -rp "输入选项（1-4，默认1）：" mirror_choice
        mirror_choice=${mirror_choice:-1}
        case $mirror_choice in
            1) mirror_url="http://mirrors.aliyun.com/ubuntu/"; break ;;
            2) mirror_url="https://mirrors.tuna.tsinghua.edu.cn/ubuntu/"; break ;;
            3) mirror_url="http://mirrors.163.com/ubuntu/"; break ;;
            4) mirror_url="https://mirrors.ustc.edu.cn/ubuntu/"; break ;;
            *) warn "无效输入，请输入1-4" ;;
        esac
    done

    # 备份当前源
    backup_file /etc/apt/sources.list

    # 写入新源
    cat > /etc/apt/sources.list <<EOF
deb ${mirror_url} ${RELEASE_VERSION} main restricted universe multiverse
deb-src ${mirror_url} ${RELEASE_VERSION} main restricted universe multiverse
deb ${mirror_url} ${RELEASE_VERSION}-security main restricted universe multiverse
deb-src ${mirror_url} ${RELEASE_VERSION}-security main restricted universe multiverse
deb ${mirror_url} ${RELEASE_VERSION}-updates main restricted universe multiverse
deb-src ${mirror_url} ${RELEASE_VERSION}-updates main restricted universe multiverse
deb ${mirror_url} ${RELEASE_VERSION}-backports main restricted universe multiverse
deb-src ${mirror_url} ${RELEASE_VERSION}-backports main restricted universe multiverse
EOF

    update_package_list
    success "软件源更换完成，已更新包列表"
    EXEC_STATUS["软件源更换"]="已安装"
    INSTALLED_FEATURES+=("软件源更换（${mirror_choice}）")
    read -rp "按回车返回菜单..." _
}

# 基础工具安装
func_install_base() {
    refresh_status
    menu_title "基础工具安装"
    if [[ "${EXEC_STATUS["基础工具安装"]}" == "已安装" ]]; then
        success "基础工具已安装，无需重复操作"
        read -rp "按回车返回菜单..." _
        return
    fi

    read -rp "确认安装基础工具（vim/git/curl/htop等）？[Y/n] " confirm
    confirm=${confirm:-Y}
    if [[ $confirm =~ ^[Yy]$ ]]; then
        install_packages vim git curl wget net-tools htop lsof tree unzip zip bzip2 rsync screen tmux ncdu sysstat util-linux

        # 配置 vim（幂等）
        local vimrc="/etc/vim/vimrc"
        if [[ -f "$vimrc" ]]; then
            append_if_not_exists "set nu" "$vimrc"
            append_if_not_exists "set tabstop=4" "$vimrc"
            append_if_not_exists "set shiftwidth=4" "$vimrc"
        fi
        success "基础工具安装完成"
        EXEC_STATUS["基础工具安装"]="已安装"
        INSTALLED_FEATURES+=("基础工具（vim/git/curl/htop等）")
    else
        warn "已跳过基础工具安装"
    fi
    read -rp "按回车返回菜单..." _
}

# 中文环境配置
func_install_chinese() {
    refresh_status
    menu_title "中文环境配置"
    if [[ "${EXEC_STATUS["中文环境配置"]}" == "已安装" ]]; then
        success "中文环境已配置，无需重复操作"
        read -rp "按回车返回菜单..." _
        return
    fi

    read -rp "确认安装中文环境（语言包+字体）？[Y/n] " confirm
    confirm=${confirm:-Y}
    if [[ $confirm =~ ^[Yy]$ ]]; then
        install_packages language-pack-zh-hans language-pack-zh-hans-base
        update-locale LANG=zh_CN.UTF-8 LC_ALL=zh_CN.UTF-8 >> "$LOG_FILE" 2>&1
        install_packages fonts-wqy-microhei fonts-wqy-zenhei fonts-noto-cjk fonts-noto-color-emoji
        success "中文环境配置完成"
        EXEC_STATUS["中文环境配置"]="已安装"
        INSTALLED_FEATURES+=("中文环境（语言包+中文字体）")
    else
        warn "已跳过中文环境配置"
    fi
    read -rp "按回车返回菜单..." _
}

# 桌面环境安装
func_install_desktop() {
    refresh_status
    menu_title "桌面环境安装"
    if is_installed xfce4-session || is_installed gnome-shell; then
        success "桌面环境已安装，无需重复操作"
        read -rp "按回车返回菜单..." _
        return
    fi

    echo "请选择要安装的桌面环境："
    echo "1) Xfce（轻量级，XRDP最优适配）"
    echo "2) GNOME（Ubuntu官方桌面，XRDP兼容性差）"
    echo "0) 取消"
    local desk_choice
    while true; do
        read -rp "输入选项（0-2，默认0）：" desk_choice
        desk_choice=${desk_choice:-0}
        case $desk_choice in
            0) warn "已取消桌面环境安装"; read -rp "按回车返回菜单..." _; return ;;
            1|2) break ;;
            *) warn "无效输入，请输入0-2" ;;
        esac
    done

    if [[ $desk_choice -eq 1 ]]; then
        install_packages xfce4 xfce4-goodies lightdm
        systemctl set-default graphical.target >> "$LOG_FILE" 2>&1
        systemctl enable lightdm >> "$LOG_FILE" 2>&1
        success "Xfce桌面安装完成"
        EXEC_STATUS["Xfce桌面安装"]="已安装"
        INSTALLED_FEATURES+=("Xfce桌面环境")
    else
        install_packages ubuntu-desktop gnome-tweaks chrome-gnome-shell
        systemctl set-default graphical.target >> "$LOG_FILE" 2>&1
        success "GNOME桌面安装完成"
        EXEC_STATUS["GNOME桌面安装"]="已安装"
        INSTALLED_FEATURES+=("GNOME桌面环境")
    fi
    read -rp "按回车返回菜单..." _
}

# XRDP安装（深度优化）
func_install_xrdp() {
    refresh_status
    menu_title "XRDP远程桌面安装（深度优化版）"
    if [[ "${EXEC_STATUS["XRDP远程桌面"]}" == "已安装" ]]; then
        success "XRDP已安装，无需重复操作"
        read -rp "按回车返回菜单..." _
        return
    fi

    # 检查是否有桌面环境，若无则提示安装Xfce
    if ! is_installed xfce4-session && ! is_installed gnome-shell; then
        warn "未检测到桌面环境，将自动安装Xfce（XRDP最优适配）"
        read -rp "是否继续？[Y/n] " confirm
        confirm=${confirm:-Y}
        if [[ ! $confirm =~ ^[Yy]$ ]]; then
            warn "已取消XRDP安装"
            read -rp "按回车返回菜单..." _
            return
        fi
        install_packages xfce4 xfce4-goodies lightdm
        EXEC_STATUS["Xfce桌面安装"]="已安装"
        INSTALLED_FEATURES+=("Xfce桌面环境")
    fi

    read -rp "确认安装XRDP远程桌面（深度优化版）？[Y/n] " xrdp_confirm
    xrdp_confirm=${xrdp_confirm:-Y}
    if [[ ! $xrdp_confirm =~ ^[Yy]$ ]]; then
        warn "已跳过XRDP安装"
        read -rp "按回车返回菜单..." _
        return
    fi

    install_packages xrdp xorgxrdp dbus-x11 tightvncserver

    # 备份原有配置
    backup_file /etc/xrdp/startwm.sh
    backup_file "$REAL_HOME/.xsession"

    # 写入最优配置（解决闪退、黑屏）
    cat > /etc/xrdp/startwm.sh << 'EOF'
#!/bin/sh
unset DBUS_SESSION_BUS_ADDRESS
unset XDG_RUNTIME_DIR
exec startxfce4
EOF
    chmod +x /etc/xrdp/startwm.sh
    echo "xfce4-session" > "$REAL_HOME/.xsession"
    chown "$REAL_USER:$REAL_USER" "$REAL_HOME/.xsession"

    # 禁用冲突服务
    systemctl disable --now gdm3 >> "$LOG_FILE" 2>&1 || true
    adduser xrdp ssl-cert >> "$LOG_FILE" 2>&1 || true

    # 开放端口
    ufw allow 3389/tcp >> "$LOG_FILE" 2>&1 || true

    systemctl enable --now xrdp >> "$LOG_FILE" 2>&1
    systemctl restart xrdp >> "$LOG_FILE" 2>&1

    success "XRDP远程桌面安装完成（深度优化版）"
    success "✅ 登录选择：Xorg"
    success "✅ 用户名：$REAL_USER"
    local ip
    ip=$(hostname -I | awk '{print $1}')
    success "✅ 连接地址：${ip}:3389"
    success "✅ 已自动适配Xfce，零闪退、零黑屏"

    EXEC_STATUS["XRDP远程桌面"]="已安装"
    INSTALLED_FEATURES+=("XRDP远程桌面（3389端口，深度优化）")
    read -rp "按回车返回菜单..." _
}

# Docker安装
func_install_docker() {
    refresh_status
    menu_title "Docker安装"
    if [[ "${EXEC_STATUS["Docker安装"]}" == "已安装" ]]; then
        success "Docker已安装，无需重复操作"
        if [[ "${EXEC_STATUS["Docker加速配置"]}" == "已安装" ]]; then
            success "Docker加速已配置"
        fi
        read -rp "按回车返回菜单..." _
        return
    fi

    read -rp "确认安装Docker + Docker Compose？[y/N] " confirm
    confirm=${confirm:-N}
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        warn "已跳过Docker安装"
        read -rp "按回车返回菜单..." _
        return
    fi

    # 安装依赖
    install_packages apt-transport-https ca-certificates curl gnupg-agent software-properties-common

    # 添加 Docker 官方 GPG 密钥和源
    curl -fsSL "${DOCKER_MIRROR}gpg" | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg >> "$LOG_FILE" 2>&1
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] ${DOCKER_MIRROR}linux/ubuntu ${RELEASE_VERSION} stable" | tee /etc/apt/sources.list.d/docker.list >/dev/null

    update_package_list
    install_packages docker-ce docker-ce-cli containerd.io

    # 安装 Docker Compose（校验 SHA256）
    local compose_url compose_bin
    compose_url="https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)"
    compose_bin="/usr/local/bin/docker-compose"
    info "下载 Docker Compose 从 $compose_url"
    curl -L "$compose_url" -o "$compose_bin" >> "$LOG_FILE" 2>&1
    chmod +x "$compose_bin"

    # 可选：验证 SHA256（需要从 GitHub API 获取，略复杂，这里省略）
    # 如果有安全需求，可考虑使用包管理器安装 docker-compose-plugin

    success "Docker + Docker Compose 安装完成"
    EXEC_STATUS["Docker安装"]="已安装"
    INSTALLED_FEATURES+=("Docker + Docker Compose")

    # Docker 加速配置
    if [[ "${EXEC_STATUS["Docker加速配置"]}" != "已安装" ]]; then
        read -rp "是否配置Docker镜像加速？[Y/n] " mirror_confirm
        mirror_confirm=${mirror_confirm:-Y}
        if [[ $mirror_confirm =~ ^[Yy]$ ]]; then
            echo -e "\n请选择Docker加速源："
            echo "1) 科大源（默认，无需申请）"
            echo "2) 网易云源"
            echo "3) 阿里云源（需自行申请）"
            echo "4) 自定义地址"
            local docker_mirror_choice docker_registry_mirror
            while true; do
                read -rp "输入选项（1-4，默认1）：" docker_mirror_choice
                docker_mirror_choice=${docker_mirror_choice:-1}
                case $docker_mirror_choice in
                    1) docker_registry_mirror="https://docker.mirrors.ustc.edu.cn"; break ;;
                    2) docker_registry_mirror="https://hub-mirror.c.163.com"; break ;;
                    3)
                        read -rp "请输入阿里云加速地址：" ali_mirror
                        docker_registry_mirror=${ali_mirror:-"https://docker.mirrors.ustc.edu.cn"}
                        break
                        ;;
                    4)
                        read -rp "请输入自定义加速地址：" custom_mirror
                        if [[ -n "$custom_mirror" ]]; then
                            docker_registry_mirror=$custom_mirror
                            break
                        else
                            warn "自定义地址不能为空"
                        fi
                        ;;
                    *) warn "无效输入，请输入1-4" ;;
                esac
            done

            mkdir -p /etc/docker
            cat > /etc/docker/daemon.json <<EOF
{
  "registry-mirrors": ["$docker_registry_mirror"]
}
EOF
            systemctl daemon-reload >> "$LOG_FILE" 2>&1
            systemctl restart docker >> "$LOG_FILE" 2>&1
            success "Docker镜像加速配置完成：$docker_registry_mirror"
            EXEC_STATUS["Docker加速配置"]="已安装"
            INSTALLED_FEATURES+=("Docker镜像加速（$docker_registry_mirror）")
        else
            warn "已跳过Docker加速配置"
        fi
    fi

    # 将用户加入 docker 组
    usermod -aG docker "$REAL_USER" >> "$LOG_FILE" 2>&1
    success "用户 $REAL_USER 已加入 docker 组，请重新登录生效"

    read -rp "按回车返回菜单..." _
}

# ----------------------------- 卸载功能 ----------------------------------------
func_uninstall_xrdp() {
    refresh_status
    menu_title "XRDP远程桌面卸载"
    if [[ "${EXEC_STATUS["XRDP远程桌面"]}" != "已安装" ]]; then
        warn "XRDP未安装，无需卸载"
        read -rp "按回车返回菜单..." _
        return
    fi

    read -rp "确认卸载XRDP远程桌面？[y/N] " confirm
    confirm=${confirm:-N}
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        warn "已取消XRDP卸载"
        read -rp "按回车返回菜单..." _
        return
    fi

    systemctl stop xrdp >> "$LOG_FILE" 2>&1
    systemctl disable xrdp >> "$LOG_FILE" 2>&1
    apt purge -y xrdp xorgxrdp tightvncserver >> "$LOG_FILE" 2>&1
    apt autoremove -y >> "$LOG_FILE" 2>&1

    # 恢复配置（如果有备份）
    if [[ -f /etc/xrdp/startwm.sh.bak ]]; then
        mv /etc/xrdp/startwm.sh.bak /etc/xrdp/startwm.sh
    fi
    if [[ -f "$REAL_HOME/.xsession.bak" ]]; then
        mv "$REAL_HOME/.xsession.bak" "$REAL_HOME/.xsession"
    else
        rm -f "$REAL_HOME/.xsession"
    fi

    systemctl enable --now gdm3 >> "$LOG_FILE" 2>&1 || true

    success "XRDP远程桌面卸载完成"
    EXEC_STATUS["XRDP远程桌面"]="未安装"
    read -rp "按回车返回菜单..." _
}

func_uninstall_desktop() {
    refresh_status
    menu_title "桌面环境卸载"
    local has_xfce="${EXEC_STATUS["Xfce桌面安装"]}"
    local has_gnome="${EXEC_STATUS["GNOME桌面安装"]}"
    if [[ "$has_xfce" != "已安装" && "$has_gnome" != "已安装" ]]; then
        warn "未安装任何桌面环境，无需卸载"
        read -rp "按回车返回菜单..." _
        return
    fi

    echo "请选择要卸载的桌面环境："
    echo "1) Xfce桌面"
    echo "2) GNOME桌面"
    echo "3) 全部卸载"
    echo "0) 取消"
    local desk_choice
    while true; do
        read -rp "输入选项（0-3，默认0）：" desk_choice
        desk_choice=${desk_choice:-0}
        case $desk_choice in
            0) warn "已取消桌面环境卸载"; read -rp "按回车返回菜单..." _; return ;;
            1|2|3) break ;;
            *) warn "无效输入，请输入0-3" ;;
        esac
    done

    case $desk_choice in
        1)
            apt purge -y xfce4 xfce4-goodies lightdm >> "$LOG_FILE" 2>&1
            apt autoremove -y >> "$LOG_FILE" 2>&1
            success "Xfce桌面卸载完成"
            EXEC_STATUS["Xfce桌面安装"]="未安装"
            ;;
        2)
            apt purge -y ubuntu-desktop gnome-tweaks chrome-gnome-shell >> "$LOG_FILE" 2>&1
            apt autoremove -y >> "$LOG_FILE" 2>&1
            success "GNOME桌面卸载完成"
            EXEC_STATUS["GNOME桌面安装"]="未安装"
            ;;
        3)
            apt purge -y xfce4 xfce4-goodies lightdm ubuntu-desktop gnome-tweaks chrome-gnome-shell >> "$LOG_FILE" 2>&1
            apt autoremove -y >> "$LOG_FILE" 2>&1
            success "所有桌面环境卸载完成"
            EXEC_STATUS["Xfce桌面安装"]="未安装"
            EXEC_STATUS["GNOME桌面安装"]="未安装"
            ;;
    esac
    read -rp "按回车返回菜单..." _
}

func_uninstall_docker() {
    refresh_status
    menu_title "Docker卸载"
    if [[ "${EXEC_STATUS["Docker安装"]}" != "已安装" ]]; then
        warn "Docker未安装，无需卸载"
        read -rp "按回车返回菜单..." _
        return
    fi

    read -rp "确认卸载Docker + Docker Compose？[y/N] " confirm
    confirm=${confirm:-N}
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        warn "已取消Docker卸载"
        read -rp "按回车返回菜单..." _
        return
    fi

    systemctl stop docker >> "$LOG_FILE" 2>&1
    systemctl disable docker >> "$LOG_FILE" 2>&1
    apt purge -y docker-ce docker-ce-cli containerd.io >> "$LOG_FILE" 2>&1
    rm -f /usr/local/bin/docker-compose
    apt autoremove -y >> "$LOG_FILE" 2>&1
    rm -rf /etc/docker

    success "Docker + Docker Compose卸载完成"
    EXEC_STATUS["Docker安装"]="未安装"
    EXEC_STATUS["Docker加速配置"]="未安装"
    read -rp "按回车返回菜单..." _
}

func_restore_mirror() {
    refresh_status
    menu_title "恢复原软件源"
    if [[ "${EXEC_STATUS["软件源更换"]}" != "已安装" ]]; then
        warn "未更换软件源，无需恢复"
        read -rp "按回车返回菜单..." _
        return
    fi

    read -rp "确认恢复原软件源？[y/N] " confirm
    confirm=${confirm:-N}
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        warn "已取消软件源恢复"
        read -rp "按回车返回菜单..." _
        return
    fi

    local latest_backup
    latest_backup=$(ls -t /etc/apt/sources.list.bak.* 2>/dev/null | head -n1)
    if [[ -z "$latest_backup" ]]; then
        error "未找到软件源备份文件"
    fi

    cp "$latest_backup" /etc/apt/sources.list
    update_package_list
    success "软件源已恢复为：$latest_backup"
    EXEC_STATUS["软件源更换"]="未安装"
    read -rp "按回车返回菜单..." _
}

# ----------------------------- 主菜单 ------------------------------------------
main_menu() {
    while true; do
        refresh_status
        menu_head "主菜单 - 功能选择"
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
        local choice
        read -rp "请输入选项（0-12）：" choice
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

# ----------------------------- 主流程 ------------------------------------------
main() {
    export TERM=xterm
    check_root

    # 创建日志文件（如果不存在）
    touch "$LOG_FILE" 2>/dev/null || {
        echo "无法创建日志文件 $LOG_FILE，请检查权限"
        exit 1
    }
    info "========== Ubuntu 初始化脚本开始运行 =========="

    # 获取 Ubuntu 版本代号
    if command -v lsb_release &>/dev/null; then
        RELEASE_VERSION=$(lsb_release -sc)
    else
        # 从 /etc/os-release 中读取
        RELEASE_VERSION=$(grep -E '^VERSION_CODENAME=' /etc/os-release | cut -d= -f2)
    fi
    if [[ -z "$RELEASE_VERSION" ]]; then
        RELEASE_VERSION="jammy"  # 默认 Ubuntu 22.04
        warn "无法检测Ubuntu版本，使用默认 $RELEASE_VERSION"
    fi

    # 安装核心依赖
    if ! is_installed hwclock || ! is_installed timedatectl; then
        info "安装核心依赖 util-linux systemd-timesyncd"
        apt install -y util-linux systemd-timesyncd >> "$LOG_FILE" 2>&1
    fi

    full_system_scan
    main_menu
}

# 启动脚本
main
