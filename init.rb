require 'redmine'

ActionDispatch::Callbacks.to_prepare do
  SettingsHelper.__send__(:include, SettingsHelperPatch)
end

Redmine::Plugin.register :redmine_project_xml_sync do
  name 'Redmine Project Xml Sync plugin'
  author 'Yuichiro Endo'
  description 'Sync OpenSource ProjectManagement software for Redmine'
  version '0.2.2'
  url 'https://github.com/jp-yendo/redmine_project_xml_sync.git'

  requires_redmine version_or_higher: '3.0.0'

  settings default: {
    tracker_alias: 'R_TRACKER',
    redmine_id_alias: 'R_ID',
    redmine_status_alias: 'R_STATUS',
    redmine_version_alias: 'R_VERSION',
    redmine_category_alias: 'R_CATEGORY',
    import: {
      tracker_id: 2,
      issue_status_id: 1,
      ignore_fields: {
        estimated_hours: false,
        priority: false,
        description: false,
        done_ratio: false,
        version: false,
        category: false
      }
    },
    export: {
      ignore_fields: {
        estimated_hours: false,
        priority: false,
        description: false,
        done_ratio: false
      }
    },
    csv_encoding: 'U'
  }, partial: 'settings/project_xml_sync_settings'

  project_module :project_xml_sync do
    permission :import_issues_from_xml, project_xml_sync: [:index, :analyze, :import_results, :csv_import_match, :csv_import_results]
    permission :export_issues_to_xml, project_xml_sync: [:index, :export, :csv_export]
  end

  menu :project_menu, :project_xml_sync, { controller: :project_xml_sync, action: :index },
    caption: :menu_caption #, after: :new_issue

  Time::DATE_FORMATS.merge!(
    :project_xml => lambda{ |time| time.strftime("%Y-%m-%dT%H:%M:%S") }
  )
end