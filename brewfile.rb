# https://matthiasportzel.com/brewfile/
# https://docs.brew.sh/Brew-Bundle-and-Brewfile
# https://homebrew-file.readthedocs.io/en/latest/usage.html

def add_shared_deps 
  def noUpdate(&block)
    ENV['HOMEBREW_NO_AUTO_UPDATE']='1'
    block.call
    ENV.delete('HOMEBREW_NO_AUTO_UPDATE')
  end
  
  brew 'jq'
  brew 'yq'
  brew 'ripgrep'
  brew 'curl'
  brew 'ast-grep'
  brew 'gh'
  brew 'hyperfine'
  brew 'tldr'
  brew 'git'
  brew 'mas'
  brew 'nushell'
  brew 'asdf'
  
  cask 'lunar'
  cask 'gimp'
  cask 'git-credential-manager'
  cask 'proxyman'
  
  ### Self updating
  
  noUpdate do 
    cask 'iterm2'
    cask 'obsidian'
    cask 'visual-studio-code'
    cask 'google-chrome'
    cask 'spotify'
  end
end

