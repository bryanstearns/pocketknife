require File.expand_path(File.dirname(__FILE__) + '/spec_helper')
require 'fileutils'
require 'ruby-debug'
require 'open3'

def generate
  # Yields with an empty tmp directory as current; create stuff
  # in it, then add to the yielded TarWriter
  buffer = StringIO.new

  # mktmpdircd do |dir|
  FileUtils.rm_rf("/tmp/pk.in")
  Dir.mkdir("/tmp/pk.in")
  Dir.chdir("/tmp/pk.in") do |dir|
    TarWriter.create(buffer) do |tw|
      # tw.verbose = true
      yield tw # write things, then tell the writer to add them'
    end
  end
  buffer.rewind
  buffer.read
end

def extract(data)
  # Expands this in-memory tarball to an empty temp directory,
  # then yields with it as the cwd; examine the temp directory
  # to see if it's right.
  # mktmpdircd do |dir|
  FileUtils.rm_rf("/tmp/pk.out")
  Dir.mkdir("/tmp/pk.out")
  Dir.chdir("/tmp/pk.out") do |dir|
    Open3.popen3("tar x") do |stdin, stdout|
      stdin.write(data)
      stdin.close
    end
    sleep(0.2)
    yield dir # look at the dir to check what's there
  end
end

def write(path, content)
  dir = File.dirname(path)
  FileUtils.mkdir_p(dir) unless dir == "."
  File.open(path, 'w') {|f| f.write(content) }
end

describe "TarWriter" do
  describe "::create" do
    it "should instantiate a TarWriter, yield, and close it" do
      io = mock
      writer = mock
      TarWriter.should_receive(:new).once.with(io).and_return(writer)
      writer.should_receive(:close).once
      TarWriter.create(io) do |x|
        x.should == writer
      end
    end
  end
  
  describe "::new" do
    it "should create a Minitar writer" do
      io = mock
      Archive::Tar::Minitar::Writer.should_receive(:open)\
                                   .with(io)
      TarWriter.new(io)
    end
  end

  describe "adding" do
    it "should handle a single file" do
      content = "This is a test"
      mtime = nil
      data = generate do |tw|
        write("a_subdir/a_file", content)
        mtime = File.stat("a_subdir/a_file").mtime
        tw.add("a_subdir/a_file")
      end

      extract(data) do
        File.exist?("a_file").should be_true
        File.read("a_file").should == content
        File.stat("a_file").mtime.should == mtime
      end
    end

    it "should handle a file with a custom name" do
      content = "This is another test"
      mtime = nil
      data = generate do |tw|
        write("a_subdir/original_name", content)
        mtime = File.stat("a_subdir/original_name").mtime
        tw.add("a_subdir/original_name", "fancy_name")
      end

      extract(data) do
        File.exist?("fancy_name").should be_true
        File.read("fancy_name").should == content
        File.stat("fancy_name").mtime.should == mtime
      end
    end

    it "should handle a symlink to a file" do
      mtime = File.stat(__FILE__).mtime
      data = generate do |tw|
        File.symlink(__FILE__, "a_symlink")
        tw.add("a_symlink", "targeted_file")
      end

      extract(data) do
        File.symlink?("targeted_file").should be_false
        File.exist?("targeted_file").should be_true
        File.read("targeted_file").should == File.read(__FILE__)
        File.stat("targeted_file").mtime.should == mtime
      end
    end

    it "should handle a symlink to a directory" do
      mtime = nil
      data = generate do |tw|
        FileUtils.mkdir_p("sis/boom/baa")
        File.symlink(File.expand_path("sis/boom"), "boomer")
        mtime = File.stat("sis/boom/baa")
        tw.add("boomer", "nested/boomer")
      end

      extract(data) do
        File.directory?("nested").should be_true
        File.directory?("nested/boomer").should be_true
        File.directory?("nested/boomer/baa").should be_true
        File.symlink?("nested/boomer").should be_false
        File.stat("nested/boomer/baa").mtime == mtime
      end
    end

    it "should handle a directory tree" do
      english = "This is a test"
      french = "Ce n'est pas un critère"
      spanish = "Esta es una prueba"
      original_dir_mtime = another_dir_mtime = nil
      english_mtime = french_mtime = spanish_mtime = nil
      data = generate do |tw|
        write("another_dir/english", english)
        write("another_dir/sub_dir/spanish", spanish)
        write("original_dir/french", french)
        Dir.chdir("original_dir") do
          File.symlink("../another_dir", "symlinked_dir")
        end
        original_dir_mtime = File.stat("original_dir").mtime
        another_dir_mtime = File.stat("another_dir").mtime
        french_mtime = File.stat("original_dir/french").mtime
        english_mtime = File.stat("another_dir/english").mtime
        spanish_mtime = File.stat("another_dir/sub_dir/spanish").mtime
        tw.add("original_dir", "tar_dir")
      end

      extract(data) do
        File.directory?("tar_dir").should be_true
        File.stat("tar_dir").mtime.should == original_dir_mtime

        File.exist?("tar_dir/french").should be_true
        File.stat("tar_dir/french").mtime.should == french_mtime
        File.read("tar_dir/french").should == french

        File.directory?("tar_dir/symlinked_dir").should be_true
        File.stat("tar_dir/symlinked_dir").mtime.should == another_dir_mtime

        File.exist?("tar_dir/symlinked_dir/english").should be_true
        File.stat("tar_dir/symlinked_dir/english").mtime.should \
          == english_mtime
        File.read("tar_dir/symlinked_dir/english").should == english

        File.exist?("tar_dir/symlinked_dir/sub_dir/spanish").should be_true
        File.stat("tar_dir/symlinked_dir/sub_dir/spanish").mtime.should \
          == spanish_mtime
        File.read("tar_dir/symlinked_dir/sub_dir/spanish").should == spanish
      end
    end
  end

  describe "adding" do
    it "should handle a single file" do
      content = "This is a test"
      data = generate do |tw|
        write("a_file", content)
        tw.add("a_file")
      end
      extract(data) do
        File.exist?("a_file").should be_true
        File.stat("a_file").size.should == content.length
      end
    end

    it "should handle a single symlink" do
      data = generate do |tw|
        File.symlink(__FILE__, "a_symlink")
        tw.add("a_symlink")
      end
      extract(data) do
        File.symlink?("a_symlink").should be_false
        File.stat("a_symlink").size.should == File.stat(__FILE__).size
      end
    end

    it "should handle a directory hierarchy" do
      standalone_file_content = "Quick zephyrs blow, vexing daft Jim"
      separate_file_content = "The quick brown fox jumped over the lazy dog"
      normal_file_content = "Jackdaws love my big sphinx of quartz"

      data = generate do |tw|
        # Write a standalone file that we'll symlink to (twice!)
        write("standalone_file", standalone_file_content)

        # Write a small hierarchy that we'll symlink to
        # include a symlink to the standalone file
        FileUtils.mkdir_p("separate/another_dir/another_subdir")
        write("separate/another_file",
              separate_file_content)
        File.symlink("../../../standalone_file",
                     "separate/another_dir/another_subdir/a_symlink_to_file")

        # Write the hierarchy we'll actually pack up; include
        # symlinks to the small hierarchy and to the standalone file.
        FileUtils.mkdir_p("main/a_dir/a_subdir")
        write("main/a_dir/a_subdir/a_file",
              normal_file_content)
        Dir.chdir("main/a_dir/a_subdir") do
          File.symlink("../../../separate",
                       "a_symlink_to_dir")
        end
        Dir.chdir("main/a_dir") do
          File.symlink("../../standalone_file",
                       "a_symlink_to_file")
        end

        # Pack the hierarchy, which should include the other stuff
        Dir.chdir("main") do
          tw.add("a_dir")
        end
      end
      extract(data) do
        files = []
        Find.find(".") {|x| files << x }
        files.should == [
          ".",
          "./a_dir",
          "./a_dir/a_subdir",
          "./a_dir/a_subdir/a_file",
          "./a_dir/a_subdir/a_symlink_to_dir",
          "./a_dir/a_subdir/a_symlink_to_dir/another_file",
          "./a_dir/a_subdir/a_symlink_to_dir/another_dir",
          "./a_dir/a_subdir/a_symlink_to_dir/another_dir/another_subdir",
          "./a_dir/a_subdir/a_symlink_to_dir/another_dir/another_subdir/a_symlink_to_file",
          "./a_dir/a_symlink_to_file"
        ]
        File.stat("a_dir/a_symlink_to_file").size.should == standalone_file_content.length
      end
    end
  end
end
