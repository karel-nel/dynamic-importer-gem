module TabularImporter
  module ApplicationHelper
    def import_status_label(status)
      status.to_s.tr("_", " ").humanize
    end

    def render_summary_value(value)
      case value
      when Hash
        content_tag(:dl, class: "ti-summary") do
          safe_join(value.map do |key, child|
            content_tag(:div, class: "ti-summary__row") do
              content_tag(:dt, key.to_s.humanize) + content_tag(:dd, render_summary_value(child))
            end
          end)
        end
      when Array
        return content_tag(:span, "None", class: "ti-muted") if value.empty?
        content_tag(:ol, safe_join(value.map { |child| content_tag(:li, render_summary_value(child)) }))
      when true then "Yes"
      when false then "No"
      when nil then content_tag(:span, "—", class: "ti-muted")
      else value.to_s
      end
    end
  end
end
