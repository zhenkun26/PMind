#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "optparse"
require "tmpdir"
require "time"
require "yaml"
require_relative "validate_evals"

module PMind
  class CalibrationWorkspacePreparer
    ARMS = %w[baseline pmind].freeze
    MANIFEST_NAME = "workspace-set.yaml"
    WAVE_MANIFEST = "evals/calibration/wave-01.yaml"
    WORKSPACE_SET_SCHEMA = "evals/schema/workspace-set-v0.yaml"

    class PreparationError < StandardError; end

    def initialize(root)
      @root = File.realpath(root)
    end

    def prepare(output:, prepared_at: Time.now.utc.iso8601)
      validate_repository!
      target = resolve_new_output(output)
      parent = File.dirname(target)
      temporary = Dir.mktmpdir(".#{File.basename(target)}-", parent)
      reserved_target = false
      reserved_identity = nil
      published = false

      begin
        manifest = build_workspace_set(temporary, prepared_at)
        write_manifest(temporary, manifest)
        verify(temporary)

        Dir.mkdir(target)
        reserved_target = true
        reserved_identity = File.stat(target)
        File.rename(File.join(temporary, "cases"), File.join(target, "cases"))
        File.rename(File.join(temporary, MANIFEST_NAME), File.join(target, MANIFEST_NAME))
        Dir.rmdir(temporary)
        temporary = nil

        verify(target)
        published = true
        target
      ensure
        FileUtils.remove_entry(temporary) if temporary && File.exist?(temporary)
        if reserved_target && !published && same_directory_identity?(target, reserved_identity)
          FileUtils.remove_entry(target)
        end
      end
    rescue Errno::EEXIST
      raise PreparationError, "output already exists; refusing to overwrite: #{target || output}"
    rescue WorkspaceTree::UnsafeTreeError => e
      raise PreparationError, e.message
    end

    def verify(output)
      validate_repository!
      root = resolve_existing_output(output)
      manifest = load_yaml_file(File.join(root, MANIFEST_NAME))
      validate_manifest_schema!(manifest)
      validate_generated_layout!(root, manifest)
      true
    rescue WorkspaceTree::UnsafeTreeError => e
      raise PreparationError, e.message
    end

    private

    def build_workspace_set(output, prepared_at)
      wave = load_repository_yaml(WAVE_MANIFEST)
      fixtures = fixture_map(wave)
      cases = wave.fetch("cases").map do |case_entry|
        case_id = case_entry.fetch("case_id")
        fixture = fixtures.fetch(case_id)
        source = File.expand_path(fixture.dig("paths", "workspace"), @root)
        expected_digest = fixture.dig("workspace_revision", "digest")
        actual_digest = WorkspaceTree.digest(source)
        unless actual_digest == expected_digest &&
               case_entry.dig("fixture", "workspace_base_revision") == expected_digest
          raise PreparationError, "#{case_id} source revision does not match its frozen Fixture and Wave"
        end

        arms = ARMS.each_with_object({}) do |arm, result|
          relative_path = "cases/#{case_id}/#{arm}"
          destination = File.join(output, relative_path)
          copy_tree(source, destination)
          prepared_digest = WorkspaceTree.digest(destination)
          unless prepared_digest == expected_digest && same_layout?(source, destination)
            raise PreparationError, "#{case_id}/#{arm} copy does not match its frozen source"
          end
          result[arm] = {
            "path" => relative_path,
            "source_revision" => expected_digest,
            "prepared_revision" => prepared_digest
          }
        end

        {
          "case_id" => case_id,
          "fixture_id" => fixture.fetch("fixture_id"),
          "arms" => arms
        }
      end

      {
        "schema_version" => "0.1.0",
        "wave_id" => wave.fetch("wave_id"),
        "status" => "ready",
        "prepared_at" => prepared_at,
        "source_wave_manifest" => WAVE_MANIFEST,
        "oracle_included" => false,
        "cases" => cases
      }
    end

    def validate_generated_layout!(root, manifest)
      unless Dir.children(root).sort == ["cases", MANIFEST_NAME]
        raise PreparationError, "workspace set root contains undeclared entries"
      end

      wave = load_repository_yaml(WAVE_MANIFEST)
      fixtures = fixture_map(wave)
      unless manifest.fetch("wave_id") == wave.fetch("wave_id")
        raise PreparationError, "workspace set wave_id does not match its source Wave"
      end
      expected_case_ids = wave.fetch("cases").map { |entry| entry.fetch("case_id") }
      manifest_cases = manifest.fetch("cases")
      unless manifest_cases.map { |entry| entry.fetch("case_id") } == expected_case_ids
        raise PreparationError, "workspace set cases do not match Wave order"
      end

      cases_root = File.join(root, "cases")
      assert_real_directory!(cases_root, "cases root")
      unless Dir.children(cases_root).sort == expected_case_ids.sort
        raise PreparationError, "workspace set contains undeclared or missing case directories"
      end

      manifest_cases.each do |case_entry|
        case_id = case_entry.fetch("case_id")
        fixture = fixtures.fetch(case_id)
        unless case_entry.fetch("fixture_id") == fixture.fetch("fixture_id")
          raise PreparationError, "#{case_id} fixture_id does not match its source Fixture"
        end
        source = File.expand_path(fixture.dig("paths", "workspace"), @root)
        expected_digest = fixture.dig("workspace_revision", "digest")
        case_root = File.join(cases_root, case_id)
        assert_real_directory!(case_root, case_id)
        unless Dir.children(case_root).sort == ARMS.sort
          raise PreparationError, "#{case_id} must contain only baseline and pmind arms"
        end

        ARMS.each do |arm|
          arm_manifest = case_entry.fetch("arms").fetch(arm)
          expected_path = "cases/#{case_id}/#{arm}"
          unless arm_manifest.fetch("path") == expected_path
            raise PreparationError, "#{case_id}/#{arm} path does not match its arm"
          end
          destination = safe_generated_path(root, expected_path)
          actual_digest = WorkspaceTree.digest(destination)
          revisions = [
            arm_manifest.fetch("source_revision"),
            arm_manifest.fetch("prepared_revision"),
            expected_digest,
            actual_digest
          ]
          unless revisions.uniq.length == 1 && same_layout?(source, destination)
            raise PreparationError, "#{case_id}/#{arm} has drifted from its frozen source"
          end
        end
      end
    end

    def validate_repository!
      validator = EvalValidator.new(@root)
      return if validator.validate_repository

      raise PreparationError, "repository validation failed:\n#{validator.errors.join("\n")}"
    end

    def validate_manifest_schema!(manifest)
      validator = EvalValidator.new(@root)
      schema = validator.load_yaml(WORKSPACE_SET_SCHEMA)
      validator.validate_document(schema, manifest, MANIFEST_NAME, schema)
      return if validator.errors.empty?

      raise PreparationError, "workspace set manifest is invalid:\n#{validator.errors.join("\n")}"
    end

    def fixture_map(wave)
      wave.fetch("cases").each_with_object({}) do |entry, result|
        case_id = entry.fetch("case_id")
        result[case_id] = load_repository_yaml("evals/fixtures/#{case_id}/fixture.yaml")
      end
    end

    def copy_tree(source, destination)
      FileUtils.mkdir_p(destination)
      Dir.children(source).sort.each do |entry|
        FileUtils.cp_r(File.join(source, entry), destination)
      end
    end

    def same_layout?(left, right)
      relative_files(left) == relative_files(right) &&
        relative_directories(left) == relative_directories(right)
    end

    def relative_files(root)
      WorkspaceTree.files(root).map { |path| WorkspaceTree.relative(path, root) }
    end

    def relative_directories(root)
      WorkspaceTree.directories(root).map { |path| WorkspaceTree.relative(path, root) }
    end

    def write_manifest(root, manifest)
      File.open(File.join(root, MANIFEST_NAME), "wb") { |file| file.write(YAML.dump(manifest)) }
    end

    def load_repository_yaml(path)
      load_yaml_file(File.expand_path(path, @root))
    end

    def load_yaml_file(path)
      YAML.safe_load(
        File.read(path),
        permitted_classes: [],
        permitted_symbols: [],
        aliases: false
      )
    rescue Errno::ENOENT, Psych::Exception => e
      raise PreparationError, "cannot load #{path}: #{e.message}"
    end

    def resolve_new_output(output)
      target = resolve_output_parent(output)
      if File.exist?(target) || File.symlink?(target)
        raise PreparationError, "output already exists; refusing to overwrite: #{target}"
      end
      target
    end

    def resolve_existing_output(output)
      expanded = absolute_output(output)
      raise PreparationError, "workspace set root cannot be a symbolic link" if File.symlink?(expanded)
      raise PreparationError, "workspace set root is missing: #{expanded}" unless File.directory?(expanded)

      real = File.realpath(expanded)
      assert_outside_repository!(real)
      real
    end

    def resolve_output_parent(output)
      expanded = absolute_output(output)
      raise PreparationError, "output cannot be a filesystem root" if expanded == File.dirname(expanded)

      parent = File.dirname(expanded)
      raise PreparationError, "output parent must already exist: #{parent}" unless File.directory?(parent)

      real_parent = File.realpath(parent)
      target = File.join(real_parent, File.basename(expanded))
      assert_outside_repository!(target)
      target
    end

    def absolute_output(output)
      unless output.is_a?(String) && output.start_with?(File::SEPARATOR)
        raise PreparationError, "output must be an absolute path"
      end
      File.expand_path(output)
    end

    def assert_outside_repository!(path)
      if nested_path?(path, @root)
        raise PreparationError, "output must be outside the PMind repository"
      end
    end

    def assert_real_directory!(path, label)
      if File.symlink?(path) || !File.directory?(path)
        raise PreparationError, "#{label} must be a real directory"
      end
    end

    def safe_generated_path(root, relative_path)
      path = File.expand_path(relative_path, root)
      unless nested_path?(path, root)
        raise PreparationError, "generated path escapes workspace set: #{relative_path}"
      end
      assert_real_directory!(path, relative_path)
      path
    end

    def nested_path?(candidate, root)
      candidate == root || candidate.start_with?("#{root}/")
    end

    def same_directory_identity?(path, expected)
      return false unless expected && !File.symlink?(path)

      current = File.stat(path)
      current.directory? && current.dev == expected.dev && current.ino == expected.ino
    rescue Errno::ENOENT
      false
    end
  end
end

if $PROGRAM_NAME == __FILE__
  options = {}
  parser = OptionParser.new do |config|
    config.banner = "Usage: ruby scripts/prepare_calibration_workspaces.rb (--output PATH | --verify PATH)"
    config.on("--output PATH", "Prepare a new isolated workspace set outside the repository") do |path|
      options[:output] = path
    end
    config.on("--verify PATH", "Verify an untouched prepared workspace set") do |path|
      options[:verify] = path
    end
    config.on("--prepared-at TIME", "Override the ISO-8601 receipt time") do |value|
      options[:prepared_at] = value
    end
  end

  begin
    parser.parse!
    selected_modes = options.values_at(:output, :verify).compact
    raise OptionParser::InvalidOption, "choose exactly one of --output or --verify" unless selected_modes.length == 1
    if options[:verify] && options[:prepared_at]
      raise OptionParser::InvalidOption, "--prepared-at is only valid with --output"
    end

    project_root = File.expand_path("..", __dir__)
    preparer = PMind::CalibrationWorkspacePreparer.new(project_root)
    if options[:output]
      prepared = preparer.prepare(
        output: options[:output],
        prepared_at: options.fetch(:prepared_at, Time.now.utc.iso8601)
      )
      puts "PMIND_WORKSPACES_PREPARED output=#{prepared} cases=3 arms=6"
    else
      preparer.verify(options[:verify])
      puts "PMIND_WORKSPACES_VALIDATION_PASS output=#{File.realpath(options[:verify])} cases=3 arms=6"
    end
  rescue OptionParser::ParseError, PMind::CalibrationWorkspacePreparer::PreparationError, SystemCallError => e
    warn "PMIND_WORKSPACES_ERROR #{e.message}"
    warn parser
    exit 1
  end
end
