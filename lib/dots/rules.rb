require 'socket'

class Filter
  def self.simplify(filter)
    case filter
    when AndFilter
      left = Filter.simplify(filter.left)
      right = Filter.simplify(filter.right)
      if left.is_a?(FalseFilter) || right.is_a?(FalseFilter)
        FalseFilter.instance
      elsif left.is_a?(TrueFilter) && right.is_a?(TrueFilter)
        TrueFilter.instance
      elsif left.is_a?(TrueFilter)
        right
      elsif right.is_a?(TrueFilter)
        left
      else
        AndFilter.new(left, right)
      end
    when OrFilter
      left = Filter.simplify(filter.left)
      right = Filter.simplify(filter.right)
      if left.is_a?(TrueFilter) || right.is_a?(TrueFilter)
        TrueFilter.instance
      elsif left.is_a?(FalseFilter) && right.is_a?(FalseFilter)
        FalseFilter.instance
      elsif left.is_a?(FalseFilter)
        right
      elsif right.is_a?(FalseFilter)
        left
      else
        OrFilter.new(left, right)
      end
    else
      filter
    end
  end
end

class HostFilter < Filter
  def initialize(host)
    @host = host
  end

  def test(ctx)
    case @host
    when String
      ctx.host.downcase == @host.downcase
    when Regexp
      ctx.host =~ @host
    end
  end

  def to_s
    case @host
    when String
      "host == #{@host.downcase}"
    when Regexp
      "host =~ #{@host}"
    end
  end
end

class UserFilter < Filter
  def initialize(user)
    @user = user
  end

  def test(ctx)
    case @user
    when String
      ctx.user.downcase == @user.downcase
    when Regexp
      ctx.user =~ @user
    end
  end

  def to_s
    case @user
    when String
      "user == #{@user.downcase}"
    when Regexp
      "user =~ #{@user}"
    end
  end
end

class EnvFilter < Filter
  def initialize(var, value)
    @var = var
    @value = value
  end

  def test(ctx)
    case @value
    when String
      ctx.env[@var] == @value
    when Regexp
      ctx.env[@var] =~ @value
    end
  end

  def to_s
    case @value
    when String
      "$#{@var} == #{@value}"
    when Regexp
      "$#{@var} =~ #{@value}"
    end
  end
end

class OsFilter < Filter
  def initialize(os)
    raise if ![:osx, :windows, :linux, :unix].include? os
    @os = os
  end

  def test(ctx)
    ctx.os == @os
  end

  def to_s
    names = {
      osx: 'OS X',
      windows: 'Windows',
      linux: 'Linux',
      unix: 'Unix'
    }

    "OS is #{names[@os]}"
  end
end

class TrueFilter < Filter
  def test(ctx)
    true
  end

  def self.instance
    @@instance ||= TrueFilter.new
  end

  def to_s
    'true'
  end
end

class FalseFilter < Filter
  def test(ctx)
    false
  end

  def self.instance
    @@instance ||= FalseFilter.new
  end

  def to_s
    'false'
  end
end

class CombineFilter < Filter
  def initialize(op, left, right)
    raise if !left || !right

    @op = op
    @left = left
    @right = right
  end

  def test(ctx)
    @op.call(@left.test(ctx), @right.test(ctx))
  end

  attr_reader :left, :right
end

class AndFilter < CombineFilter
  def initialize(left, right)
    super(-> p, q { p && q }, left, right)
  end

  def to_s
    "(#{left}) && (#{right})"
  end
end

class OrFilter < CombineFilter
  def initialize(left, right)
    super(-> p, q { p || q }, left, right)
  end

  def to_s
    "(#{left}) || (#{right})"
  end
end

class FileActions
  def initialize
    @patterns = []
  end

  def included?(file_name)
    included = true
    @patterns.each do |pattern, is_included|
      if matches?(file_name, pattern)
        included = is_included
      end
    end

    included
  end

  def include(pattern)
    @patterns << [pattern, true]
  end
  
  def exclude(pattern)
    @patterns << [pattern, false]
  end

  private

  def matches?(file_name, pattern)
    case pattern
    when Array
      pattern.any? { |p| matches?(file_name, p) }
    when String
      File.fnmatch?(pattern, file_name, File::FNM_DOTMATCH)
    when Regexp
      file_name =~ pattern
    else
      false
    end
  end
end

class Context
  def initialize
    @host = current_host
    @os = current_os
    @env = current_env
    @user = current_user
  end

  attr_accessor :host, :os, :env, :user

  private

  def current_host
    Socket.gethostname
  end

  def current_os
    host_os = RbConfig::CONFIG['host_os']
    case host_os
    when /mswin|msys|mingw|cygwin|bccwin|wince|emc/
      :windows
    when /darwin|mac os/
      :osx
    when /linux/
      :linux
    when /solaris|bsd/
      :unix
    else
      raise Error::WebDriverError, "unknown os: #{host_os.inspect}"
    end
  end

  def current_env
    ENV
  end

  def current_user
    ENV['USER'] || ENV['USERNAME']
  end
end

class Rules
  def initialize
    @rules = []
    @context = Context.new
  end

  def load(file)
    instance_eval(File.read(file), file)
  end

  def rule(host: nil, os: nil, env: nil, user: nil, &block)
    return if !block 

    actions = FileActions.new
    block.yield actions

    filters = [
      build_filter(host, HostFilter),
      build_filter(os, OsFilter),
      env_filter(env),
      build_filter(user, UserFilter)
    ]

    filter = combine_filters(filters, AndFilter)
    filter = Filter.simplify(filter)

    @rules << [filter, actions]
  end

  def included?(file_name)
    included = true
    @rules.each do |filter, actions|
      if filter.test(@context)
        included &&= actions.included?(file_name)
      end
    end

    included
  end

  private

  def env_filter(criteria)
    case criteria
    when nil
      TrueFilter.instance
    when Hash
      combine_filters(criteria.map { |k, v| EnvFilter.new(k, v) }, AndFilter)
    end
  end

  def build_filter(criteria, filter_class)
    case criteria
    when nil
      TrueFilter.instance
    when Array
      combine_filters(criteria.map { |c| filter_class.new(c) }, OrFilter)
    else
      filter_class.new(criteria)
    end
  end

  def combine_filters(filters, combine_class)
    default = if combine_class == AndFilter
      TrueFilter.instance
    else
      FalseFilter.instance
    end

    filters.reduce(default) { |acc, x| combine_class.new(acc, x) }
  end
end

r = Rules.new
r.load 'assets/config.rb'
puts r.included?('.vimrc')
