# frozen_string_literal: true

require "cgi"

module PMind
  module MarkdownSafety
    module_function

    def inline(value)
      single_line = value.to_s.gsub(/[[:space:]]+/, " ").strip
      CGI.escapeHTML(single_line).gsub(/[\\`*_{}\[\]#+!|~]/) { |character| "\\#{character}" }
    end
  end
end
