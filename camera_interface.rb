require 'fileutils'

class CameraInterface
  def retrieve_photos(destination)
    in_directory(destination) do
      kill_existing_processes!

      existing_files = Dir.glob(File.join(destination, "*")).map {|file| File.basename(file)}.sort

      indices = new_photo_indices(existing_files)

      `gphoto2 --get-file=#{indices}`
    end
  end

  def photos_on_camera
    kill_existing_processes!
    output = `gphoto2 --list-files`

    raise "No camera found" if $?.exitstatus != 0

    parse output
  end

  def parse(output)
    output.each_line.grep(/^#\d/).inject(Hash.new) do |acc, line|
      parsed_line = parse_line(line)

      acc[parsed_line[:num]] = parsed_line[:title]
      acc
    end
  end

  def new_photo_indices(existing_files, camera_output: :read_from_camera)
    file_list = if camera_output == :read_from_camera
                  photos_on_camera
                else
                  parse(camera_output)
                end

    index, _ = file_list.detect do |key, value|
      !existing_files.include?(value)
    end

    raise "No new photos" unless index

    "#{index}-#{file_list.length}"
  end

  private

  def parse_line(line)
    columns = line.split(" ")

    num, title, _ = columns

    {
      num: num[1..-1].to_i,
      title: title
    }
  end

  def kill_existing_processes!
    `killall gvfs-gphoto2-volume-monitor`
    `killall gvfsd-gphoto2`
  end

  def in_directory(directory)
    current_dir = Dir.pwd

    FileUtils.cd(directory)

    yield
  ensure
    FileUtils.cd(current_dir)
  end
end
