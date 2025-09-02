param(
  [Parameter(Mandatory=$true)] [string]$ServerUser,
  [Parameter(Mandatory=$true)] [string]$ServerHost,
  [Parameter(Mandatory=$true)] [string]$ServerPath,
  [string]$TarName = "nvim-plugins.tar.gz",
  [switch]$SkipTransfer
)

$work = Join-Path $env:USERPROFILE "Downloads\nvim-offline-pack"
$repos = @(
  # QoL
  "https://github.com/tpope/vim-surround.git",
  "https://github.com/tpope/vim-commentary.git",
  "https://github.com/tpope/vim-repeat.git",
  "https://github.com/junegunn/vim-easy-align.git",
  "https://github.com/jiangmiao/auto-pairs.git",
  "https://github.com/andymass/vim-matchup.git",
  # Files / Nav
  "https://github.com/preservim/ctrlp.vim.git",
  "https://github.com/preservim/nerdtree.git",
  # Git
  "https://github.com/tpope/vim-fugitive.git",
  "https://github.com/airblade/vim-gitgutter.git",
  # Statusline
  "https://github.com/vim-airline/vim-airline.git",
  "https://github.com/vim-airline/vim-airline-themes.git",
  # Syntax / Data
  "https://github.com/daeyun/vim-matlab.git",
  "https://github.com/chrisbra/csv.vim.git",
  "https://github.com/plasticboy/vim-markdown.git",
  "https://github.com/godlygeek/tabular.git",
  # LSP + Completion
  "https://github.com/neovim/nvim-lspconfig.git",
  "https://github.com/hrsh7th/nvim-cmp.git",
  "https://github.com/hrsh7th/cmp-nvim-lsp.git",
  "https://github.com/hrsh7th/cmp-buffer.git",
  "https://github.com/hrsh7th/cmp-path.git",
  "https://github.com/L3MON4D3/LuaSnip.git",
  "https://github.com/saadparwaiz1/cmp_luasnip.git"
)

# Ensure Git
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
  Write-Host "[*] Installing Git via winget..."
  winget install --id Git.Git -e --source winget
}

# Ensure tar (usually present as bsdtar) and scp (OpenSSH Client)
if (-not (Get-Command tar -ErrorAction SilentlyContinue)) {
  Write-Error "'tar' not found. Install a tar tool (e.g., Git for Windows includes one)."
  exit 1
}
if (-not $SkipTransfer -and -not (Get-Command scp -ErrorAction SilentlyContinue)) {
  Write-Host "[!] 'scp' not found. Install OpenSSH Client: Settings → Apps → Optional Features → Add a feature → OpenSSH Client"
  exit 1
}

# Prepare working dirs
New-Item -ItemType Directory -Path $work -Force | Out-Null
$src = Join-Path $work "src"
$bundle = Join-Path $work "bundle"
New-Item -ItemType Directory -Path $src -Force | Out-Null
New-Item -ItemType Directory -Path $bundle -Force | Out-Null

# Clone/update repos
foreach ($repo in $repos) {
  $name = ($repo.Split('/') | Select-Object -Last 1).Replace(".git","")
  $dst = Join-Path $src $name
  if (Test-Path $dst) {
    Write-Host "[*] Updating $name..."
    git -C $dst pull --ff-only
  } else {
    Write-Host "[*] Cloning $name..."
    git clone --depth 1 $repo $dst
  }
}

# Copy to clean bundle and strip VCS junk
Get-ChildItem $src | ForEach-Object {
  $dst = Join-Path $bundle $_.Name
  if (Test-Path $dst) { Remove-Item -Recurse -Force $dst }
  Copy-Item $_.FullName $dst -Recurse
  Get-ChildItem -Path $dst -Filter ".git" -Recurse -Force -Directory | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
  Get-ChildItem -Path $dst -Filter ".github" -Recurse -Force -Directory | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}

# Create tar.gz
Push-Location $bundle
if (Test-Path $TarName) { Remove-Item $TarName -Force }
Write-Host "[*] Creating $TarName ..."
tar -czf $TarName *
Pop-Location

# Transfer
if (-not $SkipTransfer) {
  $localTar = Join-Path $bundle $TarName
  Write-Host "[*] Copying to $ServerUser@$ServerHost:$ServerPath ..."
  scp "$localTar" "$ServerUser@$ServerHost:`"$ServerPath`""
  Write-Host "[✓] Transfer complete."
  Write-Host "On the server, run:"
  Write-Host "  bash setup_neovim_offline.sh --plugins-tar $ServerPath/$TarName --matlab-bin /usr/local/MATLAB/R2024b/bin"
} else {
  Write-Host "[i] SkipTransfer set. Tarball at: $(Join-Path $bundle $TarName)"
}
