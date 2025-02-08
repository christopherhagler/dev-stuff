#!/usr/bin/env bash
# Provision script for new MacBooks (Apple Silicon) and optional Linux support.
# This script backs up existing configs, installs Homebrew (or apt on Linux),
# and sets up a development environment with essential tools.

set -euo pipefail

######################################
# 1. Helper Functions
######################################

# Check if Homebrew is installed (available in $PATH).
is_brew_available() {
  command -v brew &>/dev/null
}

# Check if a given formula or cask is installed via Homebrew.
is_brew_installed() {
  brew list --cask "$1" &>/dev/null || brew list "$1" &>/dev/null
}

# Check if an application (.app bundle) is manually installed (macOS only).
is_manually_installed() {
  # mdfind can fail if indexing is off or if the app is installed elsewhere.
  mdfind "kMDItemContentType == 'com.apple.application-bundle' && kMDItemFSName == '$1.app'" &>/dev/null
}

######################################
# 2. Backup Existing Configs
######################################
backup_configs() {
  echo "Backing up existing configurations..."
  timestamp=$(date +%Y%m%d%H%M%S)
  backup_dir=~/backup_configs_$timestamp
  mkdir -p "$backup_dir"

  # List of configurations to back up
  configs=(
    ".zshrc"
    ".oh-my-zsh"
    ".config/nvim"
    ".bashrc"
    ".gitconfig"
    ".tmux.conf"
  )

  for config in "${configs[@]}"; do
    if [ -e "$HOME/$config" ]; then
      echo "  Moving ~/$config -> $backup_dir/"
      mv "$HOME/$config" "$backup_dir/"
    fi
  done

  # Schedule the backup directory for deletion in 30 days (if 'at' is available).
  echo "Scheduling backup directory ($backup_dir) for deletion in 30 days (if 'at' is available)..."
  if command -v at &>/dev/null; then
    echo "rm -rf $backup_dir" | at now + 30 days
  else
    echo "  'at' command not found; please remember to remove $backup_dir manually later."
  fi
}

######################################
# 3. Homebrew Installation (macOS)
######################################
install_homebrew() {
  if [[ $(uname -s) == "Darwin" ]]; then
    if ! is_brew_available; then
      echo "Installing Homebrew..."
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

      # If Apple Silicon (arm64), ensure /opt/homebrew is in your PATH.
      if [[ $(uname -m) == "arm64" ]]; then
        echo "Detected Apple Silicon (arm64). Adding Homebrew to PATH..."
        # Append to ~/.zprofile so it is evaluated for login shells
        echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> "$HOME/.zprofile"
        # Evaluate now for the current session
        eval "$(/opt/homebrew/bin/brew shellenv)"
      else
        # Intel fallback
        echo "Detected Intel CPU (x86_64). Ensuring /usr/local/bin/brew is in PATH..."
        echo 'eval "$(/usr/local/bin/brew shellenv)"' >> "$HOME/.zprofile"
        eval "$(/usr/local/bin/brew shellenv)"
      fi
    else
      echo "Homebrew is already installed."
    fi
  fi
}

######################################
# 4. Install Essential Tools
######################################
install_tools() {
  if [[ $(uname -s) == "Darwin" ]]; then
    brew_apps=(
      "gcc-arm-none-eabi"
      "openocd"
      "qemu"
      "git"
      "gdb"
      "cmake"
      "neovim"
      "python"
      "tmux"
      "zsh"
      "fzf"
      "htop"
    )

    cask_apps=(
      "iterm2"
      "docker"
    )

    for app in "${brew_apps[@]}"; do
      if ! is_brew_installed "$app"; then
        echo "Installing $app via Homebrew..."
        brew install "$app"
      else
        echo "$app is already installed."
      fi
    done

    for app in "${cask_apps[@]}"; do
      if ! is_brew_installed "$app" && ! is_manually_installed "$app"; then
        echo "Installing $app via Homebrew Cask..."
        brew install --cask "$app"
      else
        echo "$app is already installed (via Brew or manually)."
      fi
    done

  elif [[ $(uname -s) == "Linux" ]]; then
    sudo apt update
    sudo apt install -y \
      gcc-arm-none-eabi \
      openocd \
      qemu \
      git \
      gdb \
      cmake \
      neovim \
      python3 \
      tmux \
      zsh \
      fzf \
      htop
  fi
}

######################################
# 5. Python Environment
######################################
setup_python() {
  if [[ $(uname -s) == "Darwin" ]]; then
    # Homebrew python is part of brew_apps; double-check here:
    if ! is_brew_installed "python"; then
      echo "Installing Python via Homebrew..."
      brew install python
    else
      echo "Python is already installed via Homebrew."
    fi
  elif [[ $(uname -s) == "Linux" ]]; then
    sudo apt install -y python3-pip
  fi

  echo "Installing common Python packages (system-wide)..."
  pip3 install --upgrade pip
  pip3 install numpy scipy matplotlib pandas jupyterlab
}

######################################
# 6. Zsh + Oh My Zsh
######################################
configure_zsh() {
  if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
    echo "Installing Oh My Zsh..."
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
    
    if [[ -n "$(command -v zsh)" ]]; then
      chsh -s "$(command -v zsh)"
    fi
  else
    echo "Oh My Zsh is already installed."
  fi

  local theme_dir="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
  if [[ ! -d "$theme_dir" ]]; then
    echo "Installing Powerlevel10k theme..."
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$theme_dir"
    
    if [[ $(uname -s) == "Darwin" ]]; then
      sed -i '' 's/^ZSH_THEME=".*"/ZSH_THEME="powerlevel10k\/powerlevel10k"/' "$HOME/.zshrc"
    else
      sed -i 's/^ZSH_THEME=".*"/ZSH_THEME="powerlevel10k\/powerlevel10k"/' "$HOME/.zshrc"
    fi
  else
    echo "Powerlevel10k theme already installed."
  fi
}

######################################
# 7. Neovim Setup
######################################
setup_neovim() {
  echo "Setting up Neovim..."
  mkdir -p "$HOME/.config/nvim"

  cat <<EOF > "$HOME/.config/nvim/init.vim"
call plug#begin('~/.config/nvim/plugged')
Plug 'tpope/vim-sensible'
Plug 'neoclide/coc.nvim', {'branch': 'release'}
Plug 'scrooloose/nerdtree'
Plug 'vim-airline/vim-airline'
Plug 'vim-airline/vim-airline-themes'
Plug 'junegunn/fzf', { 'do': { -> fzf#install() } }
Plug 'junegunn/fzf.vim'
Plug 'preservim/tagbar'
Plug 'ryanoasis/vim-devicons'
" Single ALE plugin (dense-analysis is the official one)
Plug 'dense-analysis/ale'
Plug 'ludovicchabant/vim-gutentags'
Plug 'critiqjo/lldb.nvim'
Plug 'lepture/vim-jinja'
Plug 'vim-syntastic/syntastic'
Plug 'nvim-lua/plenary.nvim'
Plug 'nvim-telescope/telescope.nvim'
Plug 'puremourning/vimspector'
Plug 'psf/black'
Plug 'nvie/vim-flake8'
Plug 'davidhalter/jedi-vim'
call plug#end()

" NERDTree config
let NERDTreeShowHidden=1
autocmd vimenter * NERDTree
autocmd StdinReadPre * let s:std_in=1
autocmd VimEnter * if !argc() && !exists('s:std_in') | NERDTree | endif
nmap <leader>n :NERDTreeToggle<CR>

" Airline
let g:airline#extensions#tabline#enabled = 1

" ALE settings
let g:ale_linters = {'c': ['gcc'], 'cpp': ['g++'], 'python': ['flake8']}
let g:ale_fixers = {'c': ['clang-format'], 'cpp': ['clang-format'], 'python': ['black']}
let g:ale_python_flake8_executable = 'flake8'
let g:ale_python_flake8_options = '--max-line-length=88'
let g:ale_python_black_executable = 'black'

" Coc settings
let g:coc_global_extensions = ['coc-json', 'coc-snippets', 'coc-pyright']

" Tagbar
nmap <F8> :TagbarToggle<CR>

" FZF
nnoremap <silent> <C-p> :Files<CR>

" Syntax
autocmd BufRead,BufNewFile *.asm set syntax=nasm
autocmd BufRead,BufNewFile *.s set syntax=nasm

" Syntastic
let g:syntastic_c_checkers = ['gcc']

" Vimspector
let g:vimspector_enable_mappings = 'HUMAN'

" Gutentags
let g:gutentags_ctags_executable = 'ctags'
let g:gutentags_project_root = ['.git', '.hg', '.svn', '.bzr', '_darcs', 'build']
let g:gutentags_add_default_project_roots = 0
let g:gutentags_generate_on_new = 1
let g:gutentags_generate_on_missing = 1
let g:gutentags_generate_on_write = 1
let g:gutentags_generate_on_empty_buffer = 1

" Basic settings
set clipboard=unnamedplus
syntax on
filetype plugin indent on
set number
set relativenumber
set expandtab
set shiftwidth=4
set tabstop=4
set softtabstop=4
set mouse=a

" Leader + some Telescope mappings
let mapleader = "\<Space>"
nnoremap <leader>ff :Telescope find_files<CR>
nnoremap <leader>fg :Telescope live_grep<CR>
nnoremap <leader>fb :Telescope buffers<CR>
nnoremap <leader>fh :Telescope help_tags<CR>

" Window navigation
nnoremap <C-h> <C-w>h
nnoremap <C-j> <C-w>j
nnoremap <C-k> <C-w>k
nnoremap <C-l> <C-w>l
EOF

  # Install vim-plug if not already present; then run PlugInstall
  if [[ ! -f "$HOME/.local/share/nvim/site/autoload/plug.vim" ]]; then
    echo "Installing vim-plug for Neovim..."
    sh -c "curl -fLo \"$HOME/.local/share/nvim/site/autoload/plug.vim\" --create-dirs \\
      https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim"
  fi

  echo "Installing Neovim plugins..."
  nvim +PlugInstall +qall || true  # Continue even if some plugins fail
}

######################################
# 8. Main Execution
######################################
main() {
  backup_configs         # Backup first to avoid overwriting user config
  install_homebrew       # On macOS, install Homebrew if missing; handle Apple Silicon path
  install_tools          # Install essential tools via Homebrew (or apt on Linux)
  setup_python           # Install Python and common packages
  configure_zsh          # Install Oh My Zsh and Powerlevel10k
  setup_neovim           # Set up Neovim configuration and plugins

  echo ""
  echo "All done! If this is your first Homebrew installation on Apple Silicon,"
  echo "open a new terminal or run 'exec zsh' to update your PATH."
}

main
