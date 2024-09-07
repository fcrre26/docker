# 使用官方 Ubuntu 22.04 镜像
FROM ubuntu

# 设置环境变量，确保 apt 不会提示交互
ENV DEBIAN_FRONTEND=noninteractive

# 更新软件包列表并安装 SSH 服务器和 Vim 编辑器
RUN apt-get update && apt-get install -y openssh-server vim && rm -rf /var/lib/apt/lists/*

# 创建 SSH 所需的目录
RUN mkdir /var/run/sshd

# 设置 root 用户的密码
RUN echo 'root:1234567890' | chpasswd

# 允许 root 用户通过 SSH 登录
RUN sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config

# 暴露 22 端口
EXPOSE 22

# 启动 SSH 服务
CMD ["/usr/sbin/sshd", "-D"]