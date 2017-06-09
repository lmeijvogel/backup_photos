require 'rspec'
require_relative '../camera_interface.rb'

describe CameraInterface do
  describe '#parse' do
    it "correctly parses the file names" do
      camera_output = File.read("spec/example_file_list.txt")

      actual = CameraInterface.new.parse(camera_output)

      expect(actual[13]).to eq("MVG_0958.JPG")
    end
  end

  describe '#new_photo_indices' do
    it "returns the range of new photos" do
      camera_output = File.read("spec/example_file_list.txt")

      existing_files = %w[
        MVG_0952.JPG
        MVG_0952.NEF
        MVG_0953.JPG
        MVG_0953.NEF
      ]

      actual = CameraInterface.new.new_photo_indices(existing_files, camera_output: camera_output)

      expect(actual).to eq("5-15")
    end

    context "when there are no new files" do
      it "raises an exception" do
        camera_output = File.read("spec/example_file_list.txt")

        all_files = CameraInterface.new.parse(camera_output).values

        expect {
          CameraInterface.new.new_photo_indices(all_files, camera_output: camera_output)
        }.to raise_exception(StandardError)
      end

    end
  end
end
