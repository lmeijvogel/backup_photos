#!/usr/bin/env ruby

require 'fileutils'
require 'date'
require 'ruby-progressbar'
require 'dotenv'

require_relative './camera_interface.rb'

Dotenv.load

SOURCE_LOCATION = ENV['SOURCE_LOCATION']

NEF_OUTPUT_DIR = ENV['NEF_OUTPUT_DIR']
JPG_OUTPUT_DIR = ENV['JPG_OUTPUT_DIR']

VERACRYPT_REPOSITORY_PATH = ENV['VERACRYPT_REPOSITORY_PATH']
VERACRYPT_MOUNT_PATH = ENV['VERACRYPT_MOUNT_PATH']
VERACRYPT_PHOTOS_PATH = ENV['VERACRYPT_PHOTOS_PATH']
VERACRYPT_KEYFILE_PATH = ENV['VERACRYPT_KEYFILE_PATH']

PREVIEW_DIR = ENV['PREVIEW_DIR']
IMAGE_PREVIEW_SIZE=ENV['IMAGE_PREVIEW_SIZE']
IMAGE_VIEWER=ENV['IMAGE_VIEWER']

CONVERT_COMMAND = ['convert', '-scale', IMAGE_PREVIEW_SIZE]

SOURCE_GLOB = File.join(SOURCE_LOCATION, '/**/*%s')

VERACRYPT_MOUNT_CMD=['sudo', '/usr/bin/veracrypt', '--text', '--non-interactive', '--keyfiles', VERACRYPT_KEYFILE_PATH, '--mount', VERACRYPT_REPOSITORY_PATH, VERACRYPT_MOUNT_PATH]
VERACRYPT_UMOUNT_CMD=['sudo', '/usr/bin/veracrypt', '--text', '--non-interactive', '-d', VERACRYPT_MOUNT_PATH]

def main
  begin
    puts "Retrieving pictures from camera"
    CameraInterface.new.retrieve_photos(SOURCE_LOCATION)
  rescue StandardError => e
    puts e.message
  end

  if File.exist?(SOURCE_LOCATION)
    perform_backup(
      (SOURCE_GLOB % ['{NEF,MOV}']) => NEF_OUTPUT_DIR,
      (SOURCE_GLOB % ['JPG']) => JPG_OUTPUT_DIR
    )

    puts "Backup done"

    system("umount", SOURCE_LOCATION)

    puts "Unmounted #{SOURCE_LOCATION}"
  else
    puts "#{SOURCE_LOCATION} not mounted, not backing up"
  end

  with_usb_output_dir do
    perform_backup("#{NEF_OUTPUT_DIR}/*" => VERACRYPT_PHOTOS_PATH)
  end

  create_previews
end

def perform_backup(mapping)
  mapping.each do |source_glob, output_dir|
    FileUtils.mkdir_p(output_dir)

    puts "Copying #{source_glob} to #{output_dir}"

    new_files = Dir.glob(source_glob).reject do |file|
      output_path = File.join(output_dir, File.basename(file))
      File.exist?(output_path)
    end

    progress_bar = ProgressBar.create(total: new_files.count, format: "|%w>%i| %c/%C (%e)")

    new_files.each do |file|
      output_path = File.join(output_dir, File.basename(file))
      FileUtils.cp(file, output_path)
      progress_bar.increment
    end
  end
end

def with_usb_output_dir
  return unless File.exist?(VERACRYPT_REPOSITORY_PATH)

  begin
    if usb_container_mounted?
      puts "Veracrypt directory already mounted"
    else
      puts "Mounting #{VERACRYPT_MOUNT_PATH}"
      system(*VERACRYPT_MOUNT_CMD)
    end

    yield
  ensure
    wait_and_unmount(VERACRYPT_MOUNT_PATH, VERACRYPT_UMOUNT_CMD)
  end
end

def usb_container_mounted?
  `mount`.each_line.grep(/#{VERACRYPT_MOUNT_PATH}/).any?
end

def files_without_preview
  @files_without_preview ||= Dir.glob(File.join(JPG_OUTPUT_DIR, "*.JPG")).select do |file|
    output_file = File.join(PREVIEW_DIR, File.basename(file))

    !File.exist?(output_file)
  end
end

def create_previews
  FileUtils.mkdir_p(PREVIEW_DIR)

  puts "Creating preview images"
  progress_bar = ProgressBar.create(total: files_without_preview.count, format: "|%w>%i| %c/%C (%e)")

  first_output_file = nil

  files_without_preview.sort.each do |file|
    progress_bar.increment
    output_file = File.join(PREVIEW_DIR, File.basename(file))

    first_output_file ||= output_file
    command = CONVERT_COMMAND + [file, output_file]
    system(*command)
  end

  if first_output_file
    puts "First new file: #{first_output_file}"
    puts "Open? [Yn]"

    if (gets.strip.downcase != 'n')
      system(IMAGE_VIEWER, first_output_file)
    end

    preview_init_script_filename = Date.today.strftime("%Y-%m-%d.sh")

    unless File.exist?(preview_init_script_filename)
      File.open(preview_init_script_filename, "w") do |file|
        file.puts "#{IMAGE_VIEWER} \"#{first_output_file}\""
      end
    end
  end
end

def wait_and_unmount(dir, unmount_command, attempts: 20)
  attempts.times do |i|
    if fs_in_use?(dir)
      puts "Files locked (#{i+1}/#{attempts})"
      sleep 2
      next
    end

    puts "Unmounting #{dir}"
    success = system(*unmount_command)

    return if success
  end
end

def fs_in_use?(mount_point)
  # if `fuser` finds the file system in use, it returns
  # status 0 (which Kernel#system will evaluate to true).
  # Otherwise, it returns a status >0, which will evaluate to false.
  system('fuser', '-m', mount_point, [:out, :err] => '/dev/null')
end

def help
  # Note: The [1..-1] selection on the mount commands below is to strip out the `sudo` prefix
  puts <<~HELP
    Requirements for this tool:
    - ImageMagick (for creating thumbnails - this is desirable on my slow netbook,
    - Veracrypt (for added privacy when copying files onto a USB stick)
    - Sudo rights to mount and unmount the Veracrypt volume.

    Veracrypt configuration:
    Create a Veracrypt container on the USB stick and secure it with a keyfile (no password,
    since I don't want to have to type in the password every time. Make sure that the
    keyfile is on the laptop, not on the same volume as the Veracrypt container. Also make
    sure that the keyfile is backed up somewhere, otherwise losing the laptop also makes
    the Veracrypt backup useless.

    Sudoers configuration:
    In my case, I don't want a sudo password prompt when the Veracrypt volume is mounted,
    so for this, add the following to the sudo-config (visudo):

    # Cmnd alias specification
    # Cmnd_Alias VERACRYPT = #{VERACRYPT_MOUNT_CMD[1..-1].join(" ")},\\
                             #{VERACRYPT_UMOUNT_CMD[1..-1].join(" ")}

    #{`whoami`.strip} ALL=NOPASSWD: VERACRYPT
  HELP

end

if ARGV[0] == '--help'
  puts help
else
  main
end
