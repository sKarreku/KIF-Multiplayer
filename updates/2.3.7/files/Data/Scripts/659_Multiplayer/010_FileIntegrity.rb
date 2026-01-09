# ===========================================
# File: 010_FileIntegrity.rb
# Purpose: File Integrity Checker
# ===========================================
# Calculates hash of all .rb files in folder
# Used to verify client/server have identical files
# Prevents version mismatches and desyncs
# ===========================================

module FileIntegrity
  module_function

  # Calculate integrity hash for a folder
  # Scans all .rb files, hashes contents, combines into master hash
  # @param folder_path [String] Path to folder to scan
  # @return [String] 32-character hex hash, or error string
  def calculate_hash(folder_path)
    begin
      # Find all .rb files in folder (not subdirectories)
      rb_files = Dir.glob(File.join(folder_path, "*.rb")).sort

      # Handle empty folder
      if rb_files.empty?
        return "empty_folder"
      end

      # Calculate hash for each file's content
      file_hashes = []
      rb_files.each do |file_path|
        begin
          # Read file content with binary encoding to handle any content
          content = File.binread(file_path)

          # Hash the content (not the filename)
          content_hash = PureMD5.hexdigest(content)
          file_hashes << content_hash
        rescue => e
          # If any file fails to read, return error
          return "error_reading_#{File.basename(file_path)}"
        end
      end

      # Combine all file hashes into master hash
      # Sorted order ensures consistency
      # Force to binary encoding to avoid encoding compatibility errors
      combined = file_hashes.join.force_encoding('ASCII-8BIT')
      master_hash = PureMD5.hexdigest(combined)
      return master_hash

    rescue => e
      # Handle folder access errors
      return "error_folder_access"
    end
  end

  # Calculate hash for the multiplayer scripts folder (client-side)
  # @return [String] 32-character hex hash, or error string
  def calculate_client_hash
    # Get the path to the 659_Multiplayer folder
    # Client runs from game directory structure
    scripts_path = "Data/Scripts/659_Multiplayer"

    # Check if folder exists
    unless Dir.exist?(scripts_path)
      return "error_folder_not_found"
    end

    calculate_hash(scripts_path)
  end

  # Calculate hash for the multiplayer scripts folder (server-side)
  # @return [String] 32-character hex hash, or error string
  def calculate_server_hash
    # Get the path to the 659_Multiplayer folder
    # Server may run from different working directory

    # Try multiple potential paths
    possible_paths = [
      "Data/Scripts/659_Multiplayer",           # Relative from game root
      "./Data/Scripts/659_Multiplayer",         # Explicit relative
      "../Data/Scripts/659_Multiplayer"         # One level up (if running from KIFM folder)
    ]

    # Try each path until we find one that exists
    scripts_path = nil
    possible_paths.each do |path|
      if Dir.exist?(path)
        scripts_path = path
        break
      end
    end

    # If no path found, return error
    if scripts_path.nil?
      return "error_folder_not_found"
    end

    calculate_hash(scripts_path)
  end

  # Get detailed file list (for debugging)
  # @param folder_path [String] Path to folder to scan
  # @return [Array<Hash>] Array of {name: filename, hash: file_hash}
  def get_file_list(folder_path)
    begin
      rb_files = Dir.glob(File.join(folder_path, "*.rb")).sort

      file_list = []
      rb_files.each do |file_path|
        begin
          content = File.read(file_path)
          content_hash = PureMD5.hexdigest(content)
          file_list << {
            name: File.basename(file_path),
            hash: content_hash[0..7]  # Truncated for readability
          }
        rescue => e
          file_list << {
            name: File.basename(file_path),
            hash: "error"
          }
        end
      end

      return file_list
    rescue => e
      return []
    end
  end

  # Compare two folder hashes and explain difference (for debugging)
  # @param folder_path_1 [String] First folder path
  # @param folder_path_2 [String] Second folder path
  # @return [Hash] {match: bool, differences: array}
  def compare_folders(folder_path_1, folder_path_2)
    list1 = get_file_list(folder_path_1)
    list2 = get_file_list(folder_path_2)

    # Check for matching file count
    if list1.length != list2.length
      return {
        match: false,
        reason: "File count mismatch (#{list1.length} vs #{list2.length})"
      }
    end
    # Check each file
    differences = []
    list1.each_with_index do |file1, i|
      file2 = list2[i]

      if file1[:name] != file2[:name]
        differences << "File name mismatch: #{file1[:name]} vs #{file2[:name]}"
      elsif file1[:hash] != file2[:hash]
        differences << "Content mismatch: #{file1[:name]}"
      end
    end

    if differences.empty?
      return { match: true, reason: "All files match" }
    else
      return { match: false, reason: differences.join(", ") }
    end
  end
end

# Debug/Test (only runs if this file is executed directly)
if __FILE__ == $0
  puts "FileIntegrity Test Suite"
  puts "=" * 40

  # Test 1: Calculate hash for current folder
  current_folder = File.dirname(__FILE__)
  puts "Test 1: Current folder"
  puts "  Path: #{current_folder}"

  hash = FileIntegrity.calculate_hash(current_folder)
  puts "  Hash: #{hash}"
  puts "  Valid: #{hash.length == 32 && !hash.start_with?('error')}"

  # Test 2: Get file list
  puts "\nTest 2: File list"
  files = FileIntegrity.get_file_list(current_folder)
  puts "  Files found: #{files.length}"
  files.first(5).each do |file|
    puts "    #{file[:name]}: #{file[:hash]}..."
  end

  # Test 3: Calculate client hash
  puts "\nTest 3: Client hash"
  client_hash = FileIntegrity.calculate_client_hash
  puts "  Hash: #{client_hash}"

  puts "=" * 40
  puts "FileIntegrity module loaded successfully!"
end
