#!/usr/bin/env ruby
require "json"
require "yaml"

workflow_files = Dir.glob(".github/workflows/*.{yml,yaml}").sort
failures = []
config_count = 0

walk = lambda do |value, file|
  case value
  when Hash
    if value.key?("DOCKER_AUTH_ENTRIES_JSON")
      config_count += 1
      raw = value["DOCKER_AUTH_ENTRIES_JSON"]
      begin
        entries = JSON.parse(raw)
        unless entries.is_a?(Array) && !entries.empty?
          failures << "#{file}: expected a non-empty JSON array"
        end
        Array(entries).each_with_index do |entry, index|
          unless entry.is_a?(Hash) && %w[registry usernameEnv passwordEnv].all? { |key| entry[key].is_a?(String) && !entry[key].empty? }
            failures << "#{file}: auth entry #{index} must include non-empty registry, usernameEnv, and passwordEnv strings"
          end
        end
      rescue JSON::ParserError, TypeError => error
        failures << "#{file}: invalid DOCKER_AUTH_ENTRIES_JSON: #{error.message}"
      end
    end
    value.each_value { |child| walk.call(child, file) }
  when Array
    value.each { |child| walk.call(child, file) }
  end
end

workflow_files.each do |file|
  begin
    walk.call(YAML.load_file(file), file)
  rescue Psych::Exception => error
    failures << "#{file}: invalid YAML: #{error.message}"
  end
end

failures.each { |failure| warn failure }
abort "Docker registry auth workflow validation failed" unless failures.empty?
abort "No Docker auth workflow configuration was found" if config_count.zero?
puts "Validated #{config_count} Docker registry auth configuration(s) in #{workflow_files.length} workflow file(s)."
