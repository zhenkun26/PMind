# frozen_string_literal: true

require "open3"
require "rake"
require "rbconfig"
require "uri"
require "yaml"

ROOT = File.expand_path(__dir__)
RUBY = RbConfig.ruby

def run_live(*command)
  success = system(*command, chdir: ROOT)
  return if success

  status = $?
  abort "Command failed with exit #{status.exitstatus}: #{command.join(" ")}"
end

desc "Compile every Ruby file with warnings enabled and reject warning output"
task :compile do
  files = [File.join(ROOT, "Rakefile")] + Dir.glob(File.join(ROOT, "**/*.rb"), File::FNM_DOTMATCH).reject do |path|
    path.start_with?(File.join(ROOT, ".git/"))
  end.sort
  failures = []
  files.each do |path|
    stdout, stderr, status = Open3.capture3(RUBY, "-wc", path, chdir: ROOT)
    next if status.success? && stderr.empty? && stdout == "Syntax OK\n"

    failures << [path.delete_prefix("#{ROOT}/"), stdout, stderr, status.exitstatus]
  end
  unless failures.empty?
    failures.each do |path, stdout, stderr, status|
      warn "RUBY_WARNING_COMPILE_FAIL file=#{path} exit=#{status}"
      warn stdout unless stdout.empty?
      warn stderr unless stderr.empty?
    end
    abort "PMIND_RUBY_WARNING_COMPILATION_FAIL files=#{failures.length}"
  end
  puts "PMIND_RUBY_WARNING_COMPILATION_PASS files=#{files.length}"
end

desc "Run the complete Minitest suite in one process"
task :test do
  runner = 'Dir[File.join(Dir.pwd, "test/**/*_test.rb")].sort.each { |path| require path }'
  run_live(RUBY, "-Itest", "-e", runner)
end

desc "Validate Eval schemas, fixtures, profiles, and calibration manifests"
task :evals do
  run_live(RUBY, "scripts/validate_evals.rb")
end

desc "Safely parse every repository YAML file with aliases disabled"
task :yaml do
  paths = Dir.glob(File.join(ROOT, "**/*.{yaml,yml}"), File::FNM_DOTMATCH).reject do |path|
    path.start_with?(File.join(ROOT, ".git/"))
  end.sort
  errors = []
  paths.each do |path|
    YAML.safe_load(
      File.binread(path),
      permitted_classes: [],
      permitted_symbols: [],
      aliases: false
    )
  rescue Psych::Exception, SystemCallError => e
    errors << "#{path.delete_prefix("#{ROOT}/")}: #{e.message.lines.first.strip}"
  end
  abort "PMIND_SAFE_YAML_FAIL\n#{errors.join("\n")}" unless errors.empty?

  puts "PMIND_SAFE_YAML_PASS files=#{paths.length}"
end

desc "Verify repository-local Markdown links"
task :links do
  files = Dir.glob(File.join(ROOT, "**/*.md"), File::FNM_DOTMATCH).reject do |path|
    path.start_with?(File.join(ROOT, ".git/"))
  end.sort
  broken = []
  files.each do |path|
    File.binread(path).scan(/\[[^\]]+\]\(([^)]+)\)/).flatten.each do |raw_target|
      target = raw_target.strip
      next if target.empty? || target.match?(/\A(?:https?:|mailto:|#)/)

      target = target[/\A<([^>]+)>/, 1] || target.split(/[ \t]+/, 2).first
      target = target.split("#", 2).first
      next if target.empty?

      begin
        target = URI.decode_www_form_component(target)
      rescue ArgumentError
        nil
      end
      candidate = File.expand_path(target, File.dirname(path))
      broken << "#{path.delete_prefix("#{ROOT}/")}: #{target}" unless File.exist?(candidate)
    end
  end
  abort "PMIND_MARKDOWN_LINK_FAIL\n#{broken.join("\n")}" unless broken.empty?

  puts "PMIND_MARKDOWN_LINK_PASS files=#{files.length}"
end

desc "Run all deterministic, dependency-free local repository gates"
task verify: [:compile, :yaml, :links, :test, :evals] do
  puts "PMIND_LOCAL_DETERMINISTIC_VERIFICATION_PASS"
end

desc "Run the real calibration readiness gate and preserve exit 2 when blocked"
task :calibration do
  system(RUBY, "scripts/calibration_preflight.rb", chdir: ROOT)
  status = $?
  exit status.exitstatus if [0, 2].include?(status.exitstatus)

  abort "PMIND_CALIBRATION_TASK_ERROR exit=#{status.exitstatus}"
end

desc "Run local verification, then the calibration readiness gate"
task status: [:verify, :calibration]

task default: :status
