#!/usr/bin/env bash
# setup_neovim_offline.sh
# Offline-friendly Neovim IDE for RHEL (C/C++/Python + MATLAB, LSP, completion, airline, etc.)
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

# --- pick pkg manager ---
if command -v dnf >/dev/null 2>&1; then PM=dnf; else PM=yum; fi
SUDO=""; [[ $EUID -ne 0 ]] && SUDO="sudo"

echo "[*] Installing dev tools & runtime packages via $PM ..."
$SUDO $PM -y groupinstall "Development Tools" || true
$SUDO $PM -y install neovim git ctags gdb clang clang-tools-extra python3 \
                     make cmake tar gzip which findutils || true
# Useful for radar/data work (best-effort; may not exist in your repos)
$SUDO $PM -y install fftw fftw-devel python3-numpy python3-scipy python3-matplotlib || true

# --- plugin install (offline) ---
PACK_DIR="$HOME/.local/share/nvim/site/pack/vendor/start"
mkdir -p "$PACK_DIR"
if [[ -n "$PLUG_TAR" ]]; then
  echo "[*] Unpacking plugins: $PLUG_TAR -> $PACK_DIR"
  tar xzf "$PLUG_TAR" -C "$PACK_DIR"
else
  echo "[*] Skipping plugin unpack (no --plugins-tar provided)."
fi

# --- NVIM config ---
NVIM_DIR="$HOME/.config/nvim"
mkdir -p "$NVIM_DIR"

cat > "$NVIM_DIR/init.vim" <<'NVIMCFG'
" ================== Offline Neovim IDE ==================
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

" Grep fallback (no ripgrep)
set grepprg=grep\ -nR\ --exclude-dir=.git\ --binary-files=without-match

" ---------- Airline (offline) ----------
set noshowmode
set laststatus=2
let g:airline_powerline_fonts = 1
let g:airline#extensions#tabline#enabled = 1
" If your terminal font isn't patched:
" let g:airline_symbols_ascii = 1

" ---------- Files / Nav ----------
" CtrlP (find files/buffers without ripgrep)
let g:ctrlp_working_path_mode = 'ra'
let g:ctrlp_show_hidden = 1
let g:ctrlp_user_command = [
      \ '.git',
      \ 'git --git-dir=%s/.git ls-files -co --exclude-standard',
      \ 'find %s -type f'
      \ ]
nnoremap <leader>p :CtrlP<CR>
nnoremap <leader>b :CtrlPBuffer<CR>

" NERDTree
nnoremap <leader>n :NERDTreeToggle<CR>

" Quick tags/grep helpers
nnoremap <leader>t :!ctags -R .<CR>
nnoremap <leader>r :grep! <C-R><C-W> .<CR>:copen<CR>

" ---------- Quality of life ----------
" surround/commentary/repeat/easy-align/auto-pairs/matchup just work after install

" ---------- Run helper (Neovim terminal) ----------
function! RunTerm(cmd) abort
  botright 12split
  execute 'terminal bash -lc ' . shellescape(a:cmd)
endfunction

" ---------- C/C++ ----------
autocmd FileType c,cpp setlocal makeprg=make
autocmd FileType c,cpp nnoremap <buffer> <F5> :w<CR>:make<CR>
autocmd FileType c,cpp nnoremap <buffer> <F6> :w<CR>:call RunTerm('./a.out')<CR>

" ---------- Python ----------
autocmd FileType python nnoremap <buffer> <F5> :w<CR>:call RunTerm('python3 ' . shellescape(@%))<CR>

" ---------- MATLAB ----------
autocmd BufNewFile,BufRead *.m setlocal filetype=matlab
" R2020a+ batch:
autocmd FileType matlab nnoremap <buffer> <F5> :w<CR>
      \ :call RunTerm('matlab -batch "run('''.expand('%:p').''')"')<CR>
" Older MATLAB (uncomment if needed):
" autocmd FileType matlab nnoremap <buffer> <F5> :w<CR>
"       \ :call RunTerm('matlab -nodisplay -nosplash -r "try, run('''.expand('%:p').'''); catch e, disp(getReport(e)); end; exit"')<CR>

" ---------- Built-in LSP (clangd) ----------
lua << EOF
local ok, lspconfig = pcall(require, 'lspconfig')
if ok and vim.fn.executable('clangd') == 1 then
  lspconfig.clangd.setup{
    on_attach = function(_, bufnr)
      local map = function(m, l, r) vim.keymap.set(m, l, r, {buffer=bufnr, silent=true}) end
      map('n','gd', vim.lsp.buf.definition)
      map('n','gr', vim.lsp.buf.references)
      map('n','K',  vim.lsp.buf.hover)
      map('n','<leader>rn', vim.lsp.buf.rename)
      map('n','<leader>e',  vim.diagnostic.open_float)
    end
  }
end
EOF

" ---------- Completion (nvim-cmp + LuaSnip) ----------
lua << 'EOF'
local ok_cmp, cmp = pcall(require, 'cmp')
if ok_cmp then
  local luasnip = require('luasnip')
  cmp.setup({
    snippet = { expand = function(args) luasnip.lsp_expand(args.body) end },
    mapping = cmp.mapping.preset.insert({
      ['<Tab>']   = cmp.mapping.select_next_item(),
      ['<S-Tab>'] = cmp.mapping.select_prev_item(),
      ['<CR>']    = cmp.mapping.confirm({ select = true }),
    }),
    sources = {
      { name = 'nvim_lsp' },
      { name = 'buffer' },
      { name = 'path' },
    },
  })
end
EOF

" ---------- Data/Docs ----------
" csv.vim, vim-markdown, tabular: no extra config needed
NVIMCFG

# --- record plugin manifest for sanity ---
cat > "$NVIM_DIR/OFFLINE_PLUGINS.txt" <<'MANIFEST'
Included plugins (place these under pack/vendor/start):
- vim-surround, vim-commentary, vim-repeat, vim-easy-align, auto-pairs, vim-matchup
- ctrlp.vim, NERDTree
- vim-fugitive, vim-gitgutter
- vim-airline, vim-airline-themes
- vim-matlab
- csv.vim, vim-markdown, tabular
- nvim-lspconfig
- nvim-cmp, cmp-nvim-lsp, cmp-buffer, cmp-path
- LuaSnip, cmp_luasnip
MANIFEST

# --- MATLAB PATH (optional) ---
if [[ -n "$MATLAB_BIN" ]]; then
  if ! command -v matlab >/dev/null 2>&1; then
    echo "[*] Adding MATLAB to PATH in ~/.bashrc -> $MATLAB_BIN"
    echo "export PATH=\"$MATLAB_BIN:\$PATH\"" >> "$HOME/.bashrc"
  fi
fi

echo
echo "[✓] Neovim offline IDE installed."
echo "Open with: nvim"
echo "Keys: ,p (files)  ,n (tree)  ,t (ctags)  F5 build/run  F6 run (C/C++)  F5 (MATLAB/Python)"
