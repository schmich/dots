rule os: :windows do |f|
  f.exclude '.zsh*'
end

rule host: 'nexus' do |f|
  f.exclude /\.zsh.*/
  f.exclude '.gconf'
end

rule host: /ags-dev/i do |f|
end

rule host: ['foo', 'bar'], user: 'vagrant', os: :windows do |f|
end

rule host: 'zero' do |f|
  f.exclude '.vim*'
end

# hostname, os, environment, user

# Create new repo/dots
# 
# 
# Import existing repo/dots
# 
# 
# Adding a file to repo
# 
# 
