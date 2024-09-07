#!/bin/bash

clear

get_next_container_number() {
    local max_number=0
    for container in $(docker ps -a --format "{{.Names}}" | grep -E '^ubuntu-[0-9]{2}$'); do
        number=${container#ubuntu-}
        if [ "$number" -gt "$max_number" ]; then
            max_number=$number
        fi
    done
    echo $((max_number + 1))
}

get_next_available_port() {
    local highest_port=$(docker ps -a --format "{{.Ports}}" | grep -oE '0.0.0.0:[0-9]+' | cut -d':' -f2 | sort -rn | head -n1)
    if [ -n "$highest_port" ]; then
        echo $((highest_port + 1))
    else
        echo 20001  # 默认起始端口
    fi
}

create_docker_containers() {
    local count=$1
    local memory=$2
    local cpu_limit=$3
    local created_containers=()
    local start_number=$(get_next_container_number)
    local start_port=$(get_next_available_port)

    for ((i=0; i<count; i++)); do
        local port=$((start_port + i))
        local container_number=$((start_number + i))
        local name=$(printf "ubuntu-%02d" $container_number)
        echo "正在创建容器 '$name' 在端口 $port ..."

        local command="docker run -d --name $name -p ${port}:22 --cpus $cpu_limit --memory $memory --restart always ubuntu-ssh-server"
        echo "执行命令: $command"
        
        result=$(eval $command 2>&1)
        if [ $? -eq 0 ]; then
            echo "容器 '$name' 已成功创建。Container ID: $result"
            created_containers+=("$name")
        else
            echo "创建容器 '$name' 时出错"
            echo "错误信息: $result"
        fi
    done

    echo "${created_containers[@]}"
}

check_docker_containers() {
    local containers=("$@")
    for name in "${containers[@]}"; do
        echo "检查容器 '$name' 状态..."
        container_status=$(docker inspect -f '{{.State.Status}}' "$name" 2>/dev/null)
        if [ $? -eq 0 ]; then
            if [ "$container_status" = "running" ]; then
                echo "容器 '$name' 状态: 运行中"
            else
                echo "容器 '$name' 状态: 已停止"
                echo "容器 '$name' 日志:"
                docker logs "$name"
            fi
        else
            echo "无法获取容器 '$name' 的状态"
        fi
    done
}

echo "Docker 容器批量启动菜单"
echo "1. 批量创建容器并检查状态"
echo "2. 退出"
echo ""

while true; do
    echo "请输入你的选择:"
    read -p "选项 [1-2]: " choice

    case $choice in
        1)
            read -p "请输入要创建的容器数量: " count
            read -p "请输入内存限制 (例如: 2g): " memory
            read -p "请输入 CPU 限制 (例如: 2): " cpu_limit

            if ! [[ "$count" =~ ^[0-9]+$ ]]; then
                echo "请输入有效的数字."
                continue
            fi

            IFS=' ' read -ra created_containers <<< $(create_docker_containers "$count" "$memory" "$cpu_limit")
            check_docker_containers "${created_containers[@]}"
            ;;
        2)
            echo "退出中..."
            break
            ;;
        *)
            echo "无效的输入，请重新输入."
            ;;
    esac
done

echo "程序已结束."