#!/usr/bin/env bash
# setup_neovim_radar.sh
set -euo pipefail

PLUG_TAR=""
MATLAB_BIN=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --plugins-tar) PLUG_TAR="${2:-}"; shift 2 ;;
    --matlab-bin)  MATLAB_BIN="${2:-}"; shift 2 ;;
    *) echo "Unknown arg: $1" && exit 1 ;;
  esac
done

# --- detect package manager ---
if command -v dnf >/dev/null 2>&1; then
  PM=dnf
else
  PM=yum
fi

echo "[*] Installing Development Tools and packages via $PM ..."
sudo $PM -y groupinstall "Development Tools"
sudo $PM -y install neovim git ctags gdb clang clang-tools-extra python3 fftw fftw-devel

# --- plugin dir (no internet on server; we'll unpack a tarball if provided) ---
PACK_DIR="$HOME/.local/share/nvim/site/pack/vendor/start"
mkdir -p "$PACK_DIR"

if [[ -n "$PLUG_TAR" ]]; then
  echo "[*] Unpacking plugins from: $PLUG_TAR"
  tar xzf "$PLUG_TAR" -C "$PACK_DIR"
else
  echo "[*] No --plugins-tar provided. You can copy nvim-plugins.tar.gz here later and re-run with --plugins-tar."
fi

# --- nvim config ---
NVIM_DIR="$HOME/.config/nvim"
mkdir -p "$NVIM_DIR"

cat > "$NVIM_DIR/init.vim" <<'NVIMCFG'
" ===== Neovim offline IDE (C/C++/Python + MATLAB run) =====
set nocompatible
filetype plugin indent on
syntax on
set number relativenumber
set hidden
set tabstop=4 shiftwidth=4 expandtab
set smartcase ignorecase incsearch hlsearch
set mouse=a
set termguicolors
set updatetime=300
set wildmenu
set tags=./tags;,tags
let mapleader = ","

" Grep fallback without ripgrep
set grepprg=grep\ -nR\ --exclude-dir=.git\ --binary-files=without-match

" -------- ctrlp (fuzzy finder) --------
let g:ctrlp_working_path_mode = 'ra'
let g:ctrlp_show_hidden = 1
let g:ctrlp_user_command = [
      \ '.git',
      \ 'git --git-dir=%s/.git ls-files -co --exclude-standard',
      \ 'find %s -type f'
      \ ]

" -------- quick keys --------
nnoremap <leader>p :CtrlP<CR>
nnoremap <leader>b :CtrlPBuffer<CR>
nnoremap <leader>t :!ctags -R .<CR>
nnoremap <leader>r :grep! <C-R><C-W> .<CR>:copen<CR>

" -------- run helper (Neovim terminal) --------
function! RunTerm(cmd) abort
  botright 12split
  execute 'terminal bash -lc ' . shellescape(a:cmd)
endfunction

" -------- C/C++ --------
autocmd FileType c,cpp setlocal makeprg=make
autocmd FileType c,cpp nnoremap <buffer> <F5> :w<CR>:make<CR>
autocmd FileType c,cpp nnoremap <buffer> <F6> :w<CR>:call RunTerm('./a.out')<CR>

" -------- Python --------
autocmd FileType python nnoremap <buffer> <F5> :w<CR>:call RunTerm('python3 ' . shellescape(@%))<CR>

" -------- MATLAB --------
autocmd BufNewFile,BufRead *.m setlocal filetype=matlab
" R2020a+ batch (no desktop):
autocmd FileType matlab nnoremap <buffer> <F5> :w<CR>
      \ :call RunTerm('matlab -batch "run('''.expand('%:p').''')"')<CR>
" Older MATLAB fallback (uncomment if needed):
" autocmd FileType matlab nnoremap <buffer> <F5> :w<CR>
"       \ :call RunTerm('matlab -nodisplay -nosplash -r "try, run('''.expand('%:p').'''); catch e, disp(getReport(e)); end; exit"')<CR>

" -------- Built-in LSP (offline) via nvim-lspconfig --------
lua << EOF
local ok, lspconfig = pcall(require, 'lspconfig')
if ok then
  local on_attach = function(_, bufnr)
    local map = function(m, l, r) vim.keymap.set(m, l, r, {buffer=bufnr, silent=true}) end
    map('n','gd', vim.lsp.buf.definition)
    map('n','gr', vim.lsp.buf.references)
    map('n','K',  vim.lsp.buf.hover)
    map('n','<leader>rn', vim.lsp.buf.rename)
    map('n','<leader>e',  vim.diagnostic.open_float)
  end
  if vim.fn.executable('clangd') == 1 then
    lspconfig.clangd.setup{ on_attach = on_attach }
  end
end
EOF
NVIMCFG

# --- MATLAB PATH (optional) ---
if [[ -n "$MATLAB_BIN" ]]; then
  if ! command -v matlab >/dev/null 2>&1; then
    echo "[*] Adding MATLAB bin to PATH in ~/.bashrc: $MATLAB_BIN"
    echo "export PATH=\"$MATLAB_BIN:\$PATH\"" >> "$HOME/.bashrc"
  else
    echo "[*] matlab already on PATH"
  fi
else
  echo "[*] Tip: add MATLAB to PATH by re-running with --matlab-bin /path/to/MATLAB/R20xx*/bin"
fi

echo
echo "[✓] Neovim setup complete."
echo "Open with: nvim"
echo "Keys: ,p (files)  ,t (ctags)  F5 build/run  F6 run (C/C++)  F5 (MATLAB/Python)"
