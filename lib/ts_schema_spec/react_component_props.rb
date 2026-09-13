# frozen_string_literal: true

require "json"
require "nokogiri"

require_relative "../ts_schema_spec"

module TsSchemaSpec
  # Pulls props out of react-rails mount points in rendered HTML, so an HTML
  # action's props can be schema-checked the same way a JSON payload is.
  # Needs `render_views`.
  module ReactComponentProps
    def react_component_props(component_name, html = nil)
      html ||= response.body

      Nokogiri::HTML(html).css("[data-react-class]").filter_map do |node|
        next unless react_class_matches?(node["data-react-class"], component_name)

        parse_props(node, component_name)
      end
    end

    private

    # react-rails namespaces a component either way: "admin/SidebarNav" from
    # the asset path, "Admin.SidebarNav" from the global its UJS resolves.
    NAMESPACE_SEPARATOR = %r{[./]}

    def react_class_matches?(react_class, component_name)
      react_class == component_name ||
        react_class.to_s.split(NAMESPACE_SEPARATOR).last == component_name
    end

    def parse_props(node, component_name)
      raw = node["data-react-props"]
      raise Error, "the #{component_name} mount has no data-react-props attribute" if raw.nil?

      JSON.parse(raw)
    rescue JSON::ParserError => e
      raise Error, "could not parse data-react-props for #{component_name}: #{e.message}"
    end
  end
end
