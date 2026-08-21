# frozen_string_literal: true

require "digest"
require "find"

module PMind
  module WorkspaceTree
    class UnsafeTreeError < StandardError; end

    module_function

    def digest(root)
      absolute_root = validated_root(root)
      digest = Digest::SHA256.new

      files(absolute_root).each do |file|
        digest.update(relative(file, absolute_root))
        digest.update("\0")
        digest.update(File.binread(file))
        digest.update("\0")
      end
      digest.hexdigest
    end

    def files(root)
      scan(root).fetch(:files)
    end

    def directories(root)
      scan(root).fetch(:directories)
    end

    def relative(path, root)
      path.delete_prefix("#{File.expand_path(root)}/")
    end

    def scan(root)
      absolute_root = validated_root(root)
      result = { files: [], directories: [] }

      Find.find(absolute_root) do |entry|
        next if entry == absolute_root

        if File.symlink?(entry)
          raise UnsafeTreeError, "symbolic link is forbidden: #{relative(entry, absolute_root)}"
        elsif File.directory?(entry)
          result[:directories] << entry
        elsif File.file?(entry)
          result[:files] << entry
        else
          raise UnsafeTreeError, "special filesystem entry is forbidden: #{relative(entry, absolute_root)}"
        end
      end

      result.each_value(&:sort!)
      result
    end
    private_class_method :scan

    def validated_root(root)
      absolute_root = File.expand_path(root)
      raise UnsafeTreeError, "tree root is missing: #{absolute_root}" unless File.directory?(absolute_root)
      raise UnsafeTreeError, "tree root cannot be a symbolic link: #{absolute_root}" if File.symlink?(absolute_root)

      absolute_root
    end
    private_class_method :validated_root
  end
end
