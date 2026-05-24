#!/bin/bash

# SSH隧道管理脚本
# 使用方法: ./ssh_tunnel.sh [start|stop|status|restart]

# 远程主机列表 - 支持多个IP
REMOTE_HOSTS=(
    #"zxw@101.126.143.26"
    "zxw@123.56.64.5"
    #"zxw@104.225.151.25"
    #"root@192.168.1.99 -p 922"
    #"zxw@192.168.1.99 -p 922"
)
LOCAL_PORT="7890"
REMOTE_PORT="7890"
SSH_PID_DIR="/tmp/ssh_tunnels"
mkdir -p "$SSH_PID_DIR"

# 启动SSH隧道
start_tunnel() {
    echo "🚀 启动SSH隧道到多个主机..."

    # 清理孤儿 autossh/ssh 隧道进程
    local all_pids=$(pgrep -f "autossh.*${REMOTE_PORT}" 2>/dev/null)
    if [ -n "$all_pids" ]; then
        local tracked_pids=""
        for pid_file in "$SSH_PID_DIR"/*.pid; do
            [ -f "$pid_file" ] && tracked_pids="$tracked_pids $(cat "$pid_file")"
        done
        for pid in $all_pids; do
            if ! echo "$tracked_pids" | grep -qw "$pid"; then
                kill "$pid" 2>/dev/null
                echo "   🧹 清理孤儿进程 (PID: $pid)"
            fi
        done
    fi

    local configured_hosts=0
    for host in "${REMOTE_HOSTS[@]}"; do
        [[ ! "$host" =~ ^[[:space:]]*# ]] && ((configured_hosts++))
    done
    echo "📋 配置的主机数量: $configured_hosts"

    local success_count=0
    local skip_count=0

    for host in "${REMOTE_HOSTS[@]}"; do
        [[ "$host" =~ ^[[:space:]]*# ]] && continue

        local host_safe=$(echo "$host" | sed 's/[@: ]/_/g')
        local pid_file="${SSH_PID_DIR}/ssh_tunnel_${host_safe}.pid"

        # 检查是否已运行
        local existing_pid=""
        if [ -f "$pid_file" ]; then
            local file_pid=$(cat "$pid_file")
            if kill -0 "$file_pid" 2>/dev/null && ps -p "$file_pid" -o command= | grep -q "autossh"; then
                existing_pid="$file_pid"
            else
                rm -f "$pid_file"
            fi
        fi
        if [ -z "$existing_pid" ]; then
            existing_pid=$(pgrep -f "autossh.*$(echo "$host" | awk '{print $1}')")
        fi

        if [ -n "$existing_pid" ]; then
            echo "⚠️  到 $host 的隧道已在运行中 (PID: $existing_pid) - 跳过"
            [ ! -f "$pid_file" ] && echo "$existing_pid" > "$pid_file"
            ((skip_count++))
            continue
        fi

        echo "   连接到 $host..."
        local bind_addr="localhost"
        [[ "$host" == "zxw@104.225.151.25"* ]] && bind_addr="172.17.0.1"

        AUTOSSH_GATETIME=0 /opt/homebrew/bin/autossh -M 0 -N \
            -R ${bind_addr}:${REMOTE_PORT}:localhost:${LOCAL_PORT} \
            -o ServerAliveInterval=60 \
            -o ServerAliveCountMax=3 \
            -o ExitOnForwardFailure=no \
            -o ConnectTimeout=10 \
            $host &
        local pid=$!

        sleep 2
        if kill -0 "$pid" 2>/dev/null; then
            echo "$pid" > "$pid_file"
            echo "   ✅ 到 $host 的隧道启动成功 (PID: $pid)"
            ((success_count++))
        else
            echo "   ❌ 启动失败: $host"
        fi
    done

    echo ""
    echo "📊 隧道启动总结:"
    echo "   新建连接: $success_count"
    echo "   已存在跳过: $skip_count"
    echo "   总活跃连接: $((success_count + skip_count))"
    echo "   本地端口: ${LOCAL_PORT} -> 远程端口: ${REMOTE_PORT}"

    [ $((success_count + skip_count)) -eq 0 ] && echo "❌ 没有任何活跃的隧道连接" && return 1
    return 0
}

# 停止SSH隧道
stop_tunnel() {
    echo "🛑 停止所有SSH隧道..."
    local stopped_count=0

    for pid_file in "$SSH_PID_DIR"/*.pid; do
        if [ -f "$pid_file" ]; then
            PID=$(cat "$pid_file")
            local host_info=$(basename "$pid_file" .pid | sed 's/ssh_tunnel_//')
            if kill -0 "$PID" 2>/dev/null; then
                kill "$PID"
                for i in $(seq 1 10); do
                    kill -0 "$PID" 2>/dev/null || break
                    sleep 0.5
                done
                echo "   ✅ 已停止到 $host_info 的隧道 (PID: $PID)"
                ((stopped_count++))
            else
                echo "   ⚠️  到 $host_info 的隧道进程不存在，清理PID文件"
            fi
            rm -f "$pid_file"
        fi
    done

    # 清理残留的 autossh/ssh 进程
    local remaining_pids=$(pgrep -f "autossh.*${REMOTE_PORT}" 2>/dev/null)
    if [ -n "$remaining_pids" ]; then
        echo "   🔍 发现额外的autossh进程，正在清理..."
        for pid in $remaining_pids; do
            kill "$pid" 2>/dev/null
            echo "   ✅ 已清理额外进程 (PID: $pid)"
            ((stopped_count++))
        done
    fi

    [ $stopped_count -eq 0 ] && echo "⚠️  未找到运行中的SSH隧道" || echo "📊 已停止 $stopped_count 个SSH隧道连接"
}

# 检查隧道状态
check_status() {
    echo "=== SSH隧道状态 ==="
    echo "配置信息:"
    echo "   本地端口: ${LOCAL_PORT}"
    echo "   远程端口: ${REMOTE_PORT}"
    echo "   目标主机数量: ${#REMOTE_HOSTS[@]}"
    echo ""

    local running_count=0
    local total_configured=0

    for host in "${REMOTE_HOSTS[@]}"; do
        [[ "$host" =~ ^[[:space:]]*# ]] && continue
        ((total_configured++))

        local host_safe=$(echo "$host" | sed 's/[@: ]/_/g')
        local pid_file="${SSH_PID_DIR}/ssh_tunnel_${host_safe}.pid"

        echo "主机: $host"
        if [ -f "$pid_file" ]; then
            PID=$(cat "$pid_file")
            if kill -0 "$PID" 2>/dev/null; then
                echo "   ✅ 隧道运行中 (PID: $PID)"
                ((running_count++))
            else
                echo "   ❌ 隧道未运行 (PID文件存在但进程已死)"
                rm -f "$pid_file"
            fi
        else
            local host_addr=$(echo "$host" | awk '{print $1}')
            local found_pid=$(pgrep -f "autossh.*${host_addr}")
            if [ -n "$found_pid" ]; then
                echo "   ⚠️  隧道运行中但无PID文件 (PID: $found_pid)"
                echo "$found_pid" > "$pid_file"
                ((running_count++))
            else
                echo "   ❌ 隧道未运行"
            fi
        fi
    done

    echo ""
    echo "📊 总览: $running_count/$total_configured 个隧道正在运行"
}

# 重启隧道
restart_tunnel() {
    echo "🔄 重启所有SSH隧道..."
    stop_tunnel
    echo "等待进程完全停止..."
    sleep 3
    start_tunnel
}

case "$1" in
    "start"|"on")    start_tunnel ;;
    "stop"|"off")    stop_tunnel ;;
    "status"|"check") check_status ;;
    "restart"|"reload") restart_tunnel ;;
    *)
        echo "使用方法: $0 [start|stop|status|restart]"
        echo "  start/on       - 启动SSH隧道到所有配置的主机"
        echo "  stop/off       - 停止所有SSH隧道"
        echo "  status/check   - 查看所有隧道状态"
        echo "  restart/reload - 重启所有隧道"
        echo ""
        check_status
        ;;
esac
