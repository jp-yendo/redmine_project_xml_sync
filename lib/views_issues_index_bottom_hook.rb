class Hooks < Redmine::Hook::ViewListener
  render_on :view_issues_index_bottom,
            :partial => "project_xml_sync/other_formats_builder"
end
