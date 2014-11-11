require 'thor'
require 'childprocess'
require 'fileutils'
require 'pathname'
require 'colorize'

module Dots
  class DotsError < StandardError
  end
end

# TODO: Commands should fail if repo does not exist (e.g. dots commit, dots add, ...)
module Dots
  class CommandLine < Thor
    desc 'init <git repo URL>', 'Initialize or copy a dots repo.'
    def init(git_repo_url)
      run do
        dots_dir = File.join(Dir.home, '.dots')
        git_repo_url = Dots::GitRepo.absolute_url(git_repo_url)

        if repo_exists? git_repo_url
          Dots::Repo.clone(dots_dir, git_repo_url)
          puts ok("Repo initialized at #{Path.shorten dots_dir} from #{git_repo_url}.")
        else
          Dots::Repo.create(dots_dir, git_repo_url)
          puts ok("Repo initialized at #{Path.shorten dots_dir}.")
        end
      end
    end

    desc 'add <file>', 'Add file to the dots repo.'
    def add(path)
      # TODO: Error if repo does not exist.
      run do
        dots_dir = File.join(Dir.home, '.dots')
        repo = Dots::Repo.new(dots_dir)
        repo.add(path)

        puts ok("Added #{Path.shorten path} to repo.")
      end
    end

    desc 'commit', 'Commit changes to repo.'
    def commit
      # TODO: Error if repo does not exist.
      run do
        dots_dir = File.join(Dir.home, '.dots')
        repo = Dots::Repo.new(dots_dir)
        repo.commit

        puts ok("Committed changes to repo.")
      end
    end

    desc '-v|--version', 'Print version.'
    option :version, type: :boolean, aliases: :v
    def version
      if options[:version]
        puts "dots #{Dots::VERSION}"
      else
        help
      end
    end

    default_task :version

    private

    def run
      begin
        yield
        exit 0
      rescue Dots::DotsError => e
        $stderr.puts err(e)
        exit 1
      end
    end

    def err(message)
      "[#{'ERR'.red}] #{message}"
    end

    def ok(message)
      "[#{'OK'.green}] #{message}"
    end

    def repo_exists?(repo_url)
      git = Programs.git.create('ls-remote', repo_url)
      git.start
      git.wait
      git.exit_code == 0
    end
  end
end

module Dots
  class Program
    def initialize(executable_name)
      @path = find_path(executable_name)
      if !@path
        raise DotsError, "Could not find #{executable_name} on PATH."
      end
    end

    def create(*args)
      ChildProcess.build(@path, *args)
    end

    def run(*args)
      process = create(*args)
      yield process if block_given?
      process.start
      process.wait
      code = process.exit_code
      if code != 0
        raise DotsError, "Process did not exit cleanly (exit code #{code})."
      end
    end

    private

    def find_path(executable_name)
      dirs = (ENV['PATH'] || '').split(File::PATH_SEPARATOR)
      dirs.each do |dir|
        path = File.join(dir, executable_name) 
        if File.exist? path
          return path
        end
      end

      # TODO: Try executable_name + '.exe' on Windows.

      nil
    end 
  end

  class Programs
    def self.git
      @@git
    end

    @@git = Program.new('git')
  end
end

module Dots
  class Path
    def self.shorten(path)
      # TODO: Should compute home-relative path first.
      path.sub(Dir.home, '~')
    end
  end
end

module Dots
  class Asset
    def initialize(file_name)
      @path = File.absolute_path(File.join(File.dirname(__FILE__), 'assets', file_name))
      if !File.exist? @path
        raise DotsError, "Could not find #{@path}."
      end
    end

    def to_s
      @path
    end
  end

  class Assets
    def self.config_rb
      @@config_rb.to_s
    end

    @@config_rb = Asset.new('config.rb')
  end
end

module Dots
  class Action
  end

  class CreateDir < Action
    def initialize(dir)
      @dir = File.absolute_path(dir)
    end

    def preview
      "mkdir #{Path.shorten @dir}"
    end

    def run
      begin
        Dir.mkdir(@dir)
      rescue Errno::EEXIST
        raise DotsError, "#{Path.shorten @dir} already exists."
      end
    end

    def undo
      if Dir.exist? @dir
        FileUtils.rmdir @dir
      end
    end
  end

  class GitInit < Action
    def initialize(dir)
      @dir = dir
    end

    def preview
      'git init .'
    end

    def run
      Dir.chdir(@dir) do
        Programs.git.run('init', '.')
      end
    end

    def undo
      git_dir = File.join(@dir, '.git')
      begin
        FileUtils.remove_entry_secure(git_dir)
      rescue Errno::ENOENT
        # Ignore.
      end
    end
  end

  class GitAddRemote
    def initialize(dir, remote_name, remote_url)
      @dir = dir
      @remote_name = remote_name
      @remote_url = remote_url
    end

    def preview
      "git remote add #{@remote_name} #{@remote_url}"
    end

    def run
      Dir.chdir(@dir) do
        Programs.git.run('remote', 'add', @remote_name, @remote_url)
      end
    end

    def undo
      Dir.chdir(@dir) do
        Programs.git.run('remote', 'rm', @remote_name)
      end
    end
  end

  class CopyTree < Action
    def initialize(from_path, to_path)
      @from_path = File.absolute_path(from_path)
      @to_path = File.absolute_path(to_path)
    end

    def preview
      "cp -R #{Path.shorten @from_path} #{Path.shorten @to_path}"
    end

    def run
      FileUtils.copy(@from_path, @to_path)
    end

    def undo
      begin
        FileUtils.remove_entry_secure(@to_path)
      rescue Errno::ENOENT
        # Ignore.
      end
    end
  end

  class RemoveTree < Action
    def initialize(path)
      @path = path
    end

    def preview
      "rm -rf #{Path.shorten @path}"
    end

    def run
      FileUtils.remove_entry_secure(@path)
    end

    def undo
      # Nothing to undo.
    end
  end

  class Symlink < Action
    def initialize(src, dest)
      @src = src
      @dest = dest
    end

    def preview
      "ln -s #{Path.shorten @src} #{Path.shorten @dest}"
    end

    def run
      FileUtils.ln_sf(@src, @dest)
    end

    def undo
      FileUtils.safe_unlink(@dest)
    end
  end

  class GitAdd < Action
    def initialize(dir, path)
      @dir = dir
      @path = path
    end

    def preview
      # TODO: Path should be relative to @dir.
      "git add #{Path.shorten @path}"
    end

    def run
      Dir.chdir(@dir) do
        Programs.git.run('add', @path)
      end
    end
    
    def undo
      Dir.chdir(@dir) do
        Programs.git.run('rm', '-rf', '--cached', @path)
      end
    end
  end

  class GitCommit < Action
    def initialize(dir)
      @dir = dir
    end

    def preview
      'git commit'
    end

    def run
      Dir.chdir(@dir) do
        Programs.git.run('commit') do |process|
          process.io.inherit!
        end
      end
    end

    def undo
      # Cannot undo.
    end
  end

  class GitStatus < Action
    def initialize(dir)
      @dir = dir
    end

    def preview
      'git status -s'
    end

    def run
      Dir.chdir(@dir) do
        Programs.git.run('status', '-s') do |process|
          process.io.inherit!
        end
      end
    end

    def undo
      # Nothing to undo.
    end
  end

  class GitClone < Action
    def initialize(dir, repo_url)
      @dir = dir
      @repo_url = repo_url
    end

    def preview
      "git clone #{@repo_url} #{Path.shorten @dir}"
    end

    def run
      # TODO: What if @dir already exists?
      Programs.git.run('clone', @repo_url, @dir)
    end

    def undo
      # TODO: Delete @dir.
    end
  end

  class Runner
    def initialize
    end

    def run(actions)
      actions.each do |action|
        puts '>> '.blue + action.preview
        action.run
      end
    end
  end
end

module Dots
  class Repo
    def initialize(dir)
      @dir = dir
    end

    def exists?
      Dir.exist? @dir
    end

    def add(path)
      ensure_exists

      if !path || path.strip.empty?
        raise DotsError, 'Specify a path.'
      end

      path = File.absolute_path(path)
      short = Path.shorten(path)

      type = File.file?(path) ? 'file' : 'directory'

      # TODO: Test on Windows.
      if File.symlink? path
        raise DotsError, "Cannot add #{short} to repo. #{type.capitalize} is a symlink."
      end

      if !File.exist? path
        raise DotsError, "Cannot add #{short} to repo. Path does not exist."
      end

      # TODO: Correct for case-sensitivity, fwd/back slashes on Windows.
      if !path.start_with? Dir.home
        raise DotsError, "Cannot add #{short} to repo. #{type.capitalize} is not under home directory #{Dir.home}."
      end

      # TODO: Correct for case-sensitivity, fwd/back slashes on Windows.
      if path.start_with? @dir
        raise DotsError, "Cannot add #{short} to repo. Cannot add a #{type} already under the dots repo directory."
      end

      src = Pathname.new(path)
      relative = src.relative_path_from(Pathname.new(Dir.home)).cleanpath.to_s
      dest = File.join(@dir, relative)

      if File.exist? dest
        raise DotsError, "Cannot add #{short} to repo. #{type.capitalize} would overwrite #{Path.shorten dest}."
      end

      actions = [
        CopyTree.new(path, @dir),
        RemoveTree.new(src),
        Symlink.new(dest, src),
        GitAdd.new(@dir, dest),
        GitStatus.new(@dir)
      ]

      Runner.new.run(actions)
    end

    def commit
      actions = [
        GitCommit.new(@dir)
      ]

      Runner.new.run(actions)
    end

    def self.create(dir, git_repo_url)
      if !dir || dir.strip.empty?
        raise DotsError, 'Specify a directory.'
      end

      repo_dir = File.absolute_path(dir)

      actions = [
        CreateDir.new(repo_dir),
        GitInit.new(repo_dir),
        GitAddRemote.new(repo_dir, 'origin', git_repo_url),
        CopyTree.new(Assets.config_rb, repo_dir),
        GitAdd.new(dir, File.join(repo_dir, File.basename(Assets.config_rb)))
        # CopyTree.new(Assets.post_merge_hook, repo_dir...)
      ]

      Runner.new.run(actions)
    end

    def self.clone(dir, git_repo_url)
      if !dir || dir.strip.empty?
        raise DotsError, 'Specify a directory.'
      end

      repo_dir = File.absolute_path(dir)

      actions = [
        GitClone.new(repo_dir, git_repo_url)
      ]

      Runner.new.run(actions)
    end

    private

    def ensure_exists
      if !exists?
        raise DotsError, "Dots repo does not exist at #{Path.shorten @dir}."
        # TODO: Error message should give instruction about initializing new repo.
      end
    end
  end
end

module Dots
  class GitRepo
    def self.absolute_url(value)
      value = value.strip
      if value =~ /^([^\/]*)\/([^\/]*)$/
        @url = "git@github.com:#{value}"
      else
        @url = value
      end
    end
  end
end
