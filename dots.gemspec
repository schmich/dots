require File.expand_path('lib/dots/version.rb', File.dirname(__FILE__))

Gem::Specification.new do |s|
  s.name = 'dots'
  s.version = Dots::VERSION
  s.executables << 'dots'
  s.date = Time.now.strftime('%Y-%m-%d')
  s.summary = 'Ruby file system web server. '
  s.description = <<-END
    A simple Ruby-based file system web server for serving
    static files out of a directory.
  END
  s.authors = ['Chris Schmich']
  s.email = 'schmch@gmail.com'
  s.files = Dir['{lib}/**/*', 'bin/*', '*.md', 'LICENSE']
  s.require_path = 'lib'
  s.homepage = 'https://github.com/schmich/dots'
  s.license = 'MIT'
  s.required_ruby_version = '>= 1.9.3'
  s.add_runtime_dependency 'thor', '~> 0.19'
  s.add_runtime_dependency 'childprocess', '~> 0.5'
  s.add_runtime_dependency 'colorize', '0.7'
  s.add_development_dependency 'rake', '~> 10.3'
end
