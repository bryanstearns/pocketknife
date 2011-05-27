require 'archive/tar/minitar'

class TarWriter
  # Wrapper for Archive::Tar::Minitar::Writer that handles symlinks
  attr_accessor :verbose

  def self.create(io)
    tar_writer = TarWriter.new(io)
    yield tar_writer
    tar_writer.close
  end

  def initialize(io)
    @tar = Archive::Tar::Minitar::Writer.open(io)
  end

  def close
    @tar.close
  end

  def add(local_path, tar_path=nil)
    tar_path ||= File.basename(local_path)
    if File.directory?(local_path)
      add_directory_tree(local_path, tar_path)
    else
      add_entry(local_path, tar_path)
    end
  end

  def add_entry(local_path, tar_path)
    puts "add entry: #{local_path} [#{kind(local_path)}] -> #{tar_path}" if verbose
    case kind(local_path)
    when :symlink
      target = follow_symlink(local_path)
      if File.directory?(target)
        add_directory_tree(target, tar_path)
      else
        add_entry(target, tar_path)
      end
    when :directory
      add_directory(local_path, tar_path)
    else
      add_file(local_path, tar_path)
    end
  end

  def add_directory_tree(local_path, tar_path)
    puts "add directory tree: #{local_path} -> #{tar_path}" if verbose
    add_directory(local_path, tar_path)
    Dir["#{local_path}/**/*"].each do |local_child|
      if local_child != local_path
        tar_child = local_child.sub(%r/^#{local_path}/, tar_path)
        puts "child: #{local_child} -> #{tar_child}" if verbose
        add_entry(local_child, tar_child)
      end
    end
  end

  def add_directory(local_path, tar_path)
    puts "add directory: #{local_path} -> #{tar_path}" if verbose
    stat = File.stat(local_path)
    @tar.mkdir(tar_path,
               :mtime => stat.mtime.to_i,
               :mode => stat.mode)
  end

  def add_file(local_path, tar_path)
    puts "add file: #{local_path} -> #{tar_path}" if verbose
    stat = File.stat(local_path)
    @tar.add_file_simple(tar_path,
                         :size => stat.size,
                         :mtime => stat.mtime.to_i,
                         :mode => stat.mode) do |io|
      io.write File.open(local_path, "rb") { |f| f.read }
    end
  end

  def follow_symlink(path)
    target = File.readlink(path)
    target = File.join(File.dirname(path), target) \
      unless target.start_with?('/')
    target
  end

  def kind(path)
    return :symlink if File.symlink?(path)
    return :directory if File.directory?(path)
    return :file if File.exist?(path)
    :nonexistant
  end
end
