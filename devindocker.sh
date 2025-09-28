#!/bin/bash
set -e

# Default values
REBUILD=false
PORT=""
WORKDIR=""
LANG=""
IMAGE_NAME="dev-nvim-$LANG"

# Argument parsing
for arg in "$@"; do
  case $arg in
    --rebuild)
      REBUILD=true
      shift
      ;;
    --port=*)
      PORT="${arg#*=}"
      shift
      ;;
    *)
      if [[ -z "$WORKDIR" ]]; then
        WORKDIR=$arg
      elif [[ -z "$LANG" ]]; then
        LANG=$arg
      fi
      ;;
  esac
done

# Validate required arguments
if [[ -z "$WORKDIR" || -z "$LANG" ]]; then
  echo "Usage: $0 <local-working-dir> <language> [--port=PORT] [--rebuild]"
  echo "Supported languages: c, go, rust, zig, dotnet, python"
  exit 1
fi

# สร้างโฟลเดอร์ config neovim ชั่วคราวสำหรับ container
NVIM_CONFIG_DIR=$(mktemp -d)

mkdir -p "$NVIM_CONFIG_DIR/lua"

# สร้าง init.lua ที่เหมาะกับแต่ละภาษา
cat > "$NVIM_CONFIG_DIR/init.lua" <<EOF
vim.cmd [[packadd packer.nvim]]

require('packer').startup(function(use)
  use 'wbthomason/packer.nvim'
  use {
    'nvim-treesitter/nvim-treesitter',
    run = ':TSUpdate'
  }
  use 'neovim/nvim-lspconfig'
  use 'hrsh7th/nvim-cmp'
  use 'hrsh7th/cmp-nvim-lsp'
end)

require'nvim-treesitter.configs'.setup {
  highlight = { enable = true }
}

local lspconfig = require('lspconfig')
EOF

# เพิ่ม config LSP ตามภาษา
case "$LANG" in
  c)
    cat >> "$NVIM_CONFIG_DIR/init.lua" <<EOF
lspconfig.clangd.setup{}
EOF
    BASE_IMAGE="gcc:latest"
    INSTALL_CMDS="apt-get update && apt-get install -y neovim git curl python3-pip lua5.1 luarocks clangd && pip3 install pynvim && git clone --depth 1 https://github.com/wbthomason/packer.nvim /root/.local/share/nvim/site/pack/packer/start/packer.nvim"
    ;;
  go)
    cat >> "$NVIM_CONFIG_DIR/init.lua" <<EOF
lspconfig.gopls.setup{}
EOF
    BASE_IMAGE="golang:latest"
    INSTALL_CMDS="apt-get update && apt-get install -y neovim git curl python3-pip lua5.1 luarocks && pip3 install pynvim && git clone --depth 1 https://github.com/wbthomason/packer.nvim /root/.local/share/nvim/site/pack/packer/start/packer.nvim"
    ;;
  rust)
    cat >> "$NVIM_CONFIG_DIR/init.lua" <<EOF
lspconfig.rust_analyzer.setup{}
EOF
    BASE_IMAGE="rust:latest"
    INSTALL_CMDS="apt-get update && apt-get install -y neovim git curl python3-pip lua5.1 luarocks && pip3 install pynvim && git clone --depth 1 https://github.com/wbthomason/packer.nvim /root/.local/share/nvim/site/pack/packer/start/packer.nvim"
    ;;
  zig)
    cat >> "$NVIM_CONFIG_DIR/init.lua" <<EOF
lspconfig.zls.setup{}
EOF
    BASE_IMAGE="ziglang/zig:latest"
    # zig image ใช้ apk
    INSTALL_CMDS="apk add --no-cache neovim git curl python3 py3-pip lua5.1 luarocks clang clang-dev clang-tools-extra llvm-dev llvm && pip3 install pynvim && git clone --depth 1 https://github.com/wbthomason/packer.nvim /root/.local/share/nvim/site/pack/packer/start/packer.nvim"
    ;;
  dotnet)
    cat >> "$NVIM_CONFIG_DIR/init.lua" <<EOF
lspconfig.omnisharp.setup{
  cmd = { "/omnisharp/OmniSharp", "--languageserver" , "--hostPID", tostring(vim.fn.getpid()) },
}
EOF
    BASE_IMAGE="mcr.microsoft.com/dotnet/sdk:7.0"
    INSTALL_CMDS="apt-get update && apt-get install -y neovim git curl python3-pip lua5.1 luarocks tar && pip3 install pynvim && git clone --depth 1 https://github.com/wbthomason/packer.nvim /root/.local/share/nvim/site/pack/packer/start/packer.nvim && mkdir -p /omnisharp && curl -L https://github.com/OmniSharp/omnisharp-roslyn/releases/latest/download/omnisharp-linux-x64.tar.gz | tar -zx -C /omnisharp && export PATH=\"/omnisharp:\$PATH\""
    ;;
  python)
    cat >> "$NVIM_CONFIG_DIR/init.lua" <<EOF
lspconfig.pyright.setup{}
EOF
    BASE_IMAGE="python:3.11"
    INSTALL_CMDS="apt-get update && apt-get install -y neovim git curl lua5.1 luarocks && pip3 install pynvim pyright && git clone --depth 1 https://github.com/wbthomason/packer.nvim /root/.local/share/nvim/site/pack/packer/start/packer.nvim"
    ;;
  *)
    echo "Unsupported language: $LANG"
    exit 1
    ;;
esac

# สร้าง Dockerfile ชั่วคราว
TMP_DOCKERFILE=$(mktemp)

echo "FROM $BASE_IMAGE" > $TMP_DOCKERFILE
echo "RUN $INSTALL_CMDS" >> $TMP_DOCKERFILE

# copy config เข้า container
echo "COPY nvim-config /root/.config/nvim" >> $TMP_DOCKERFILE

echo "WORKDIR /workspace" >> $TMP_DOCKERFILE
echo 'CMD ["nvim"]' >> $TMP_DOCKERFILE

# สร้าง folder ชั่วคราว เพื่อใส่ config
TMP_BUILD_DIR=$(mktemp -d)
mkdir -p "$TMP_BUILD_DIR/nvim-config"
cp "$NVIM_CONFIG_DIR/init.lua" "$TMP_BUILD_DIR/nvim-config/init.lua"

# สร้าง image
docker build -t "$IMAGE_NAME" -f $TMP_DOCKERFILE "$TMP_BUILD_DIR"

# ลบไฟล์ชั่วคราว
rm -rf "$NVIM_CONFIG_DIR"
rm -f "$TMP_DOCKERFILE"

# รัน container พร้อมแมปโฟลเดอร์โค้ด
if [[ -n "$PORT" ]]; then
  docker run --rm -it -v "$WORKDIR":/workspace -p "$PORT:$PORT" ""
else
  docker run --rm -it -v "$WORKDIR":/workspace "$IMAGE_NAME"
fi
