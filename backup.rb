#!/usr/bin/env ruby

require 'fileutils'
require 'ruby-progressbar'
require 'dotenv'

Dotenv.load

SOURCE_LOCATION = ENV['SOURCE_LOCATION']

NEF_OUTPUT_DIR = ENV['NEF_OUTPUT_DIR']
JPG_OUTPUT_DIR = ENV['JPG_OUTPUT_DIR']

VERACRYPT_REPOSITORY_PATH = ENV['VERACRYPT_REPOSITORY_PATH']
VERACRYPT_MOUNT_PATH = ENV['VERACRYPT_MOUNT_PATH']
VERACRYPT_PHOTOS_PATH = ENV['VERACRYPT_PHOTOS_PATH']
VERACRYPT_KEYFILE_PATH = ENV['VERACRYPT_KEYFILE_PATH']

PREVIEW_DIR = ENV['PREVIEW_DIR']

CONVERT_COMMAND = %w[convert -scale 1366x768]

SOURCE_GLOB = File.join(SOURCE_LOCATION, '/**/*%s')

VERACRYPT_MOUNT_CMD=['sudo', '/usr/bin/veracrypt', '--text', '--non-interactive', '--keyfiles', VERACRYPT_KEYFILE_PATH, '--mount', VERACRYPT_REPOSITORY_PATH, VERACRYPT_MOUNT_PATH]
VERACRYPT_UMOUNT_CMD=['sudo', '/usr/bin/veracrypt', '--text', '--non-interactive', '-d', VERACRYPT_MOUNT_PATH]

def main
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

  puts "First new file: #{first_output_file}"
end

def wait_and_unmount(dir, unmount_command, attempts: 20)
  attempts.times do |i|
    if fs_in_use?(dir)
      puts "Files locked (#{i+1}/#{attempts})"
      sleep 2
      next
    end

    puts "Unmounting #{dir}"
    system(*unmount_command)

    return
  end
end

def fs_in_use?(mount_point)
  # if `fuser` finds the file system in use, it returns
  # status 0 (which Kernel#system will evaluate to true).
  # Otherwise, it returns a status >0, which will evaluate to false.
  system('fuser', '-m', mount_point, [:out, :err] => '/dev/null')
end

main
