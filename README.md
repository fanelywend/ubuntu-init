# Ubuntu 一键初始化脚本

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

一个用于 Ubuntu 系统新装后快速初始化的一键脚本，集成时区配置、源更换、中文环境、桌面安装、常用工具部署等功能，告别重复的手动配置操作。

## 🚀 功能特性

| 功能项 | 详情 |
|--------|------|
| 时区配置 | 自动设置为亚洲/上海时区（可自定义） |
| 软件源更换 | 支持阿里云/清华/163/中科大源（默认阿里云） |
| 基础工具安装 | vim/git/curl/wget/htop 等常用命令行工具 |
| 中文环境配置 | 安装中文语言包 + 中文字体，解决乱码问题 |
| 桌面环境可选 | 支持 Xfce（轻量）/ GNOME（官方）双桌面，也可选择不安装 |
| Docker 安装 | 可选安装 Docker + Docker Compose，配置国内源 |
| 交互友好 | 所有操作可交互式选择，带默认值，避免误操作 |
| 安全可靠 | 关键配置自动备份，异常时友好提示 |

## 📋 适用系统

- Ubuntu 20.04 LTS (Focal Fossa)
- Ubuntu 22.04 LTS (Jammy Jellyfish)
- Ubuntu 24.04 LTS (Noble Numbat)
- 其他 Debian/Ubuntu 衍生发行版（基本兼容）

## 🛠️ 使用方法

### 1. 下载脚本
```bash
# 方式1：直接从 GitHub 克隆（推荐）
git clone https://github.com/fanelywend/ubuntu-init-script.git
cd ubuntu-init-script

# 方式2：直接下载脚本文件
curl -O https://raw.githubusercontent.com/fanelywend/ubuntu-init-script/main/ubuntu-init.sh
