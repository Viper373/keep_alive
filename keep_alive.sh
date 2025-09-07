#!/bin/bash
#===============================================================================
# Universal Sing-box & Argo Keep-Alive Script
# 万能 Sing-box 和 Argo 保活脚本
# 支持系统: Debian, Ubuntu, Alpine, CentOS, FreeBSD, OpenWrt, etc.
# 作者: Viper373
# 仓库: https://github.com/Viper373/keep_alive
# 版本: 2.0
#===============================================================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
GRAY='\033[0;37m'
NC='\033[0m' # No Color

# 配置变量
SCRIPT_NAME="sing-box-keeper"
INSTALL_DIR="/usr/local/bin"
LOG_DIR="/var/log"
SERVICE_DIR="/etc/systemd/system"
INIT_DIR="/etc/init.d"
CONFIG_FILE="/etc/${SCRIPT_NAME}.conf"

# 检测系统类型
detect_system() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
    elif command -v lsb_release >/dev/null 2>&1; then
        OS=$(lsb_release -si | tr '[:upper:]' '[:lower:]')
        OS_VERSION=$(lsb_release -sr)
    elif [ -f /etc/redhat-release ]; then
        OS="centos"
    elif [ -f /etc/alpine-release ]; then
        OS="alpine"
    elif uname -s | grep -qi "freebsd"; then
        OS="freebsd"
    elif [ -f /etc/openwrt_release ]; then
        OS="openwrt"
    else
        OS="unknown"
    fi
    
    ARCH=$(uname -m)
}

# 彩色日志输出函数
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        "INFO")
            echo -e "${GRAY}[$timestamp]${NC} ${GREEN}[INFO]${NC} $message" ;;
        "WARN")
            echo -e "${GRAY}[$timestamp]${NC} ${YELLOW}[WARN]${NC} $message" ;;
        "ERROR")
            echo -e "${GRAY}[$timestamp]${NC} ${RED}[ERROR]${NC} $message" ;;
        "SUCCESS")
            echo -e "${GRAY}[$timestamp]${NC} ${GREEN}[SUCCESS]${NC} $message" ;;
        "DEBUG")
            echo -e "${GRAY}[$timestamp]${NC} ${PURPLE}[DEBUG]${NC} $message" ;;
        *)
            echo -e "${GRAY}[$timestamp]${NC} ${WHITE}[LOG]${NC} $message" ;;
    esac
}

# 检查命令是否存在
check_command() {
    local cmd=$1
    local alternatives=("$@")
    
    for alt in "${alternatives[@]}"; do
        if command -v "$alt" >/dev/null 2>&1; then
            echo "$alt"
            return 0
        fi
    done
    return 1
}

# 系统兼容性检查
system_compatibility_check() {
    log "INFO" "检测系统环境..."
    log "INFO" "操作系统: ${CYAN}$OS${NC}"
    log "INFO" "系统版本: ${CYAN}$OS_VERSION${NC}"
    log "INFO" "系统架构: ${CYAN}$ARCH${NC}"
    
    # 检查必要的命令
    local missing_commands=()
    
    if ! PGREP_CMD=$(check_command pgrep); then
        missing_commands+=("pgrep")
    fi
    if ! PKILL_CMD=$(check_command pkill); then
        missing_commands+=("pkill")
    fi
    if ! NOHUP_CMD=$(check_command nohup); then
        missing_commands+=("nohup")
    fi
    if ! SHELL_CMD=$(check_command bash sh ash); then
        missing_commands+=("shell")
    fi
    
    if [ ${#missing_commands[@]} -gt 0 ]; then
        log "ERROR" "缺少必要命令: ${missing_commands[*]}"
        log "INFO" "尝试安装缺失的包..."
        install_dependencies
    else
        log "SUCCESS" "系统兼容性检查通过"
    fi
}

# 安装依赖
install_dependencies() {
    log "INFO" "正在安装依赖包..."
    case $OS in
        "debian"|"ubuntu")
            apt-get update && apt-get install -y procps coreutils ;;
        "alpine")
            apk add --no-cache procps coreutils bash ;;
        "centos"|"rhel"|"fedora")
            if command -v dnf >/dev/null 2>&1; then
                dnf install -y procps-ng coreutils
            else
                yum install -y procps-ng coreutils
            fi ;;
        "arch")
            pacman -S --noconfirm procps-ng coreutils ;;
        "freebsd")
            pkg install -y bash ;;
        "openwrt")
            opkg update && opkg install procps-ng coreutils ;;
        *)
            log "WARN" "未知系统，请手动安装: procps, coreutils" ;;
    esac
}

# 创建配置文件
create_config() {
    cat > "$CONFIG_FILE" << EOF
# Sing-box Keep-Alive Configuration
# 保活脚本配置文件

# 检查间隔 (秒)
CHECK_INTERVAL=5

# 重启延迟 (秒)
RESTART_DELAY=2

# 日志级别 (INFO, WARN, ERROR, DEBUG)
LOG_LEVEL=INFO

# 最大重启尝试次数
MAX_RESTART_ATTEMPTS=5

# Sing-box 进程匹配模式
SINGBOX_PATTERN="/etc/sing-box/sing-box run -c /etc/sing-box/config.json"

# Argo 进程匹配模式
ARGO_PATTERN="/etc/sing-box/argo tunnel --url http://localhost:8001"

# 启动命令
SINGBOX_START_CMD="nohup /etc/sing-box/sing-box run -c /etc/sing-box/config.json > /dev/null 2>&1 &"
ARGO_START_CMD="nohup /etc/sing-box/argo tunnel --url http://localhost:8001 --no-autoupdate --edge-ip-version auto --protocol http2 > /dev/null 2>&1 &"
EOF
    log "SUCCESS" "配置文件已创建: $CONFIG_FILE"
}

# ... 省略中间未改动的部分（守护进程/安装/卸载等逻辑与之前一致） ...

# 主程序入口
main() {
    if [ "$(id -u)" != "0" ]; then
        log "ERROR" "请使用 root 权限运行此脚本"
        exit 1
    fi
    
    detect_system
    mkdir -p "$LOG_DIR"
    mkdir -p "$(dirname $CONFIG_FILE)"
    
    if [ $# -gt 0 ]; then
        case $1 in
            install) create_config; create_keepalive_script ;;
            service) create_config; create_keepalive_script; install_as_service ;;
            uninstall) uninstall ;;
            check) system_compatibility_check ;;
            *) log "ERROR" "未知参数: $1"; echo "用法: $0 [install|service|uninstall|check]"; exit 1 ;;
        esac
    else
        interactive_menu
    fi
}

main "$@"
