#!/bin/bash

# 自动化脚本菜单
WALLET_LOG="wallet_info.txt"
DOCKER_INSTALLED_FLAG="/tmp/docker_installed"
REPO_CLONED_FLAG="/tmp/repo_cloned"
NODE_RUNNING_FLAG="/tmp/node_running"

# 打印菜单选项
function print_menu() {
    echo "请选择一个选项："
    echo "1. 安装 Docker 和依赖"
    echo "2. 拉取 Git 仓库并编译"
    echo "3. 运行 Fractal 节点和 CAT 索引器"
    echo "4. 创建新钱包"
    echo "5. 执行 mint"
    echo "6. 查看 Fractal 节点运行情况"
    echo "7. 退出"
}

# 错误日志函数
function log_error() {
    echo -e "\033[31m$1\033[0m"  # 红色输出错误信息
}

# 检查 curl 是否安装
function check_curl() {
    if ! [ -x "$(command -v curl)" ]; then
        echo "curl 未安装。正在安装 curl..."
        sudo apt-get update
        sudo apt-get install -y curl
        if ! [ -x "$(command -v curl)" ]; then
            log_error "curl 安装失败。请手动安装 curl。"
            return 1
        else
            echo "curl 安装成功。"
        fi
    fi
}

# 检查 docker 和 docker-compose 是否可用
function check_docker() {
    # 检查 Docker 是否安装
    if ! [ -x "$(command -v docker)" ]; then
        log_error "Docker 未安装。请先选择 '1. 安装 Docker 和依赖' 选项。"
        return 1
    fi

    # 检查 Docker 守护进程是否正在运行
    if ! sudo systemctl is-active --quiet docker; then
        log_error "Docker 守护进程未运行。正在启动..."
        sudo systemctl start docker
        if ! sudo systemctl is-active --quiet docker; then
            log_error "无法启动 Docker 守护进程。请检查 Docker 安装。"
            return 1
        fi
        echo "Docker 守护进程已启动。"
    fi

    # 检查 docker-compose 是否安装
    if ! [ -x "$(command -v docker-compose)" ]; then
        log_error "docker-compose 未找到，正在安装 docker-compose 插件..."
        sudo apt-get update

        # 先尝试通过官方包管理器安装 docker-compose-plugin
        sudo apt-get install -y docker-compose-plugin

        # 如果 docker-compose 仍然不可用，回退到使用 curl 安装
        if ! [ -x "$(command -v docker-compose)" ]; then
            log_error "docker-compose 插件安装失败，正在尝试使用 curl 安装 docker-compose。"
            check_curl
            sudo curl -L "https://github.com/docker/compose/releases/download/v2.20.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
            sudo chmod +x /usr/local/bin/docker-compose
        fi

        if ! [ -x "$(command -v docker-compose)" ]; then
            log_error "docker-compose 安装失败。请手动检查并安装。"
            return 1
        fi
        echo "docker-compose 安装成功。"
    fi

    return 0
}

# 1. 安装 Docker 和依赖
function install_dependencies() {
    if [ -f "$DOCKER_INSTALLED_FLAG" ]; then
        echo "Docker 和依赖已安装，跳过此步骤。"
        return
    fi

    echo "安装 Docker 和依赖..."
    
    sudo apt-get update
    sudo apt-get install docker.io -y

    # 安装最新版本的 docker-compose
    check_curl
    VERSION=$(curl --silent https://api.github.com/repos/docker/compose/releases/latest | grep -Po '"tag_name": "\K.*\d')
    DESTINATION=/usr/local/bin/docker-compose
    sudo curl -L https://github.com/docker/compose/releases/download/${VERSION}/docker-compose-$(uname -s)-$(uname -m) -o $DESTINATION
    sudo chmod 755 $DESTINATION

    sudo apt-get install npm -y
    sudo npm install n -g
    sudo n stable
    sudo npm i -g yarn

    # 标记 Docker 已安装
    touch "$DOCKER_INSTALLED_FLAG"

    echo "Docker 和依赖安装完成。"
}

# 2. 拉取 Git 仓库并编译
function pull_and_build_repo() {
    if [ -f "$REPO_CLONED_FLAG" ]; then
        echo "Git 仓库已拉取并编译，跳过此步骤。"
        return
    fi

    echo "拉取 Git 仓库并编译..."
    
    git clone https://github.com/CATProtocol/cat-token-box
    cd cat-token-box || exit
    sudo yarn install
    sudo yarn build

    # 标记 Git 仓库已拉取并编译
    touch "$REPO_CLONED_FLAG"

    echo "Git 仓库拉取并编译完成。"
}

# 3. 运行 Fractal 节点和 CAT 索引器
function run_docker_containers() {
    if [ -f "$NODE_RUNNING_FLAG" ]; then
        echo "Fractal 节点和 CAT 索引器已运行，跳过此步骤。"
        return
    fi

    # 检查 Docker 和 docker-compose
    if ! check_docker; then
        return 1
    fi

    # 检查目录是否存在
    if [ ! -d "cat-token-box/packages/tracker/" ]; then
        log_error "找不到 packages/tracker/ 目录，请检查仓库是否正确克隆。"
        return 1
    fi

    echo "运行 Fractal 节点和 CAT 索引器..."

    cd ./cat-token-box/packages/tracker/ || exit
    sudo chmod 777 docker/data
    sudo chmod 777 docker/pgdata
    sudo docker-compose up -d

    cd ../../
    sudo docker build -t tracker:latest .
    sudo docker run -d \
        --name tracker \
        --add-host="host.docker.internal:host-gateway" \
        -e DATABASE_HOST="host.docker.internal" \
        -e RPC_HOST="host.docker.internal" \
        -p 3000:3000 \
        tracker:latest

    # 标记节点已运行
    touch "$NODE_RUNNING_FLAG"

    echo "Fractal 节点和 CAT 索引器已启动。"
}

# 4. 创建新钱包并捕获输出
function create_wallet() {
    echo "创建新钱包..."

    # 导航到 cli 目录
    cd /root/cat-token-box/packages/cli || { log_error "未找到 /cat-token-box/packages/cli 目录"; return 1; }

    # 检查比特币 RPC 服务是否运行
    if ! nc -z 127.0.0.1 8332; then
        log_error "无法连接到比特币节点 (127.0.0.1:8332)。请确保比特币节点已启动。"
        return 1
    fi

    # 检查并备份现有的钱包文件
    if [ -f wallet.json ]; then
        BACKUP_DIR="wallet_backups"
        mkdir -p "$BACKUP_DIR"
        TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
        mv wallet.json "$BACKUP_DIR/wallet_$TIMESTAMP.json"
        echo "已备份现有钱包文件到 $BACKUP_DIR/wallet_$TIMESTAMP.json"
    fi

    # 检查并创建 config.json 文件
    if [ ! -f config.json ]; then
        echo "config.json 文件不存在，正在创建..."
        cat > config.json <<EOL
{
  "network": "fractal-mainnet",
  "tracker": "http://127.0.0.1:3000",
  "dataDir": ".",
  "maxFeeRate": 30,
  "rpc": {
      "url": "http://127.0.0.1:8332",
      "username": "bitcoin",
      "password": "opcatAwesome"
  }
}
EOL
        echo "config.json 文件已创建。"
    else
        echo "config.json 文件已存在，跳过创建步骤。"
    fi

    # 创建新钱包
    echo "正在创建钱包，请稍候..."
    WALLET_OUTPUT=$(sudo yarn cli wallet create 2>&1)
    echo "命令输出："
    echo "$WALLET_OUTPUT"

    if [ $? -ne 0 ]; then
        log_error "创建钱包失败: $WALLET_OUTPUT"
        return 1
    fi

    # 提取并打印助记词、私钥和地址（如果存在）
    MNEMONIC=$(echo "$WALLET_OUTPUT" | grep -oP '(?<=Mnemonic: ).*')
    PRIVATE_KEY=$(echo "$WALLET_OUTPUT" | grep -oP '(?<=Private Key: ).*')
    ADDRESS=$(echo "$WALLET_OUTPUT" | grep -oP '(?<=Taproot Address: ).*')

    if [ -n "$MNEMONIC" ]; then
        echo "助记词: $MNEMONIC"
    else
        echo "助记词未提供."
    fi

    if [ -n "$PRIVATE_KEY" ]; then
        echo "私钥: $PRIVATE_KEY"
    else
        echo "私钥未提供."
    fi

    if [ -n "$ADDRESS" ]; then
        echo "地址 (Taproot格式): $ADDRESS"
    else
        echo "地址未提供."
    fi

    # 记录钱包信息到 wallet_info.txt（修改路径）
    WALLET_LOG="/root/cat-token-box/wallet_info.txt"
    {
        echo "钱包创建时间: $(date)"
        echo "助记词: $MNEMONIC"
        echo "私钥: $PRIVATE_KEY"
        echo "地址 (Taproot格式): $ADDRESS"
        echo "--------------------------"
    } >> $WALLET_LOG

    echo "钱包信息已保存到 $WALLET_LOG"
    echo "新钱包创建完成！"

    cd ../../
}

# 5. 执行 mint 操作
function execute_mint() {
    echo "执行 mint 操作..."

    # 检查钱包信息文件是否存在（修改路径）
    if [ ! -f /root/cat-token-box/wallet_info.txt ]; then
        echo "错误: 找不到钱包信息文件 wallet_info.txt。请先创建钱包。"
        return 1
    fi

    # 显示可用钱包信息（修改路径）
    echo "可用钱包:"
    cat /root/cat-token-box/wallet_info.txt

    # 提示用户选择钱包索引
    echo -n "请输入要使用的钱包索引 (例如 1): "
    read wallet_index

    # 提示用户输入交易哈希 (txid)
    echo -n "请输入交易哈希 (txid): "
    read txid

    # 提示用户输入交易索引 (index)
    echo -n "请输入交易索引 (index): "
    read tx_index

    # 提示用户输入要 mint 的数量
    echo -n "请输入要 mint 的数量: "
    read mint_amount

    # 检查是否输入了有效的交易哈希和索引
    if [[ -z "$txid" || -z "$tx_index" || -z "$mint_amount" ]]; then
        echo "错误: 交易哈希、交易索引和 mint 数量不能为空。"
        return 1
    fi

    # 构建 mint 命令
    command="yarn cli mint -i ${txid}_${tx_index} ${mint_amount}"

    # 显示即将执行的命令
    echo "执行命令: $command"

    # 执行 mint 操作
    $command
    if [ $? -ne 0 ]; then
        echo "mint 失败。请检查节点和 API 服务是否正常运行。"
        return 1
    else
        echo "mint 成功"
    fi
}

# 菜单循环
while true; do
    print_menu
    read -rp "请输入选项: " choice

    case $choice in
        1)
            install_dependencies
            ;;
        2)
            pull_and_build_repo
            ;;
        3)
            run_docker_containers
            ;;
        4)
            create_wallet
            ;;
        5)
            execute_mint
            ;;
        6)
            check_node_status
            ;;
        7)
            echo "退出脚本。"
            exit 0
            ;;
        *)
            echo "无效选项，请重试。"
            ;;
    esac
done
