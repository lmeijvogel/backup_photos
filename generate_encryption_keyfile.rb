#!/usr/bin/env ruby

require 'fileutils'
require 'securerandom'

random_string = SecureRandom.alphanumeric(160)

output_file = ARGV[0] || "keyfile.txt"

if File.exist?(output_file)
  FileUtils.mv(output_file, "#{output_file}_bak")
end

File.open(output_file, "w") do |file|
  file.write(random_string)
end

puts "Generated random string in #{File.expand_path(output_file)}"
