host 'nexus' do |f|
  f.exclude /\.zsh.*/
  f.exclude '.gconf'
end

host /ags-dev/i do |f|
  f.include '.vimrc'
end

# Create new repo/dots
# 
# 
# Import existing repo/dots
# 
# 
# Adding a file to repo
# 
# 
