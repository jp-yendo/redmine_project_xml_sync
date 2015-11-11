require 'redmine'

ActionDispatch::Callbacks.to_prepare do
  SettingsHelper.__send__(:include, SettingsHelperPatch)
end

Redmine::Plugin.register :redmine_project_xml_sync do
  name 'Redmine Project Xml Sync plugin'
  author 'Yuichiro Endo'
  description 'Sync OpenSource ProjectManagement software for Redmine'
  version '0.0.1'
  url 'https://github.com/jp-yendo/redmine_project_xml_sync.git'

  requires_redmine version_or_higher: '3.0.0'

  settings default: {
    export: {
	    sync_versions: false,
      ignore_fields: {
        description: false,
        priority: false,
        done_ratio: false,
        estimated_hours: false,
        spent_hours: false
      }
    },
    import: {
	    is_private_by_default: false,
	    instant_import_tasks: 10,
	    sync_versions: false,
	    tracker_alias: 'TRACKER',
      redmine_id_alias: 'RID',
      redmine_status_alias: 'RSTATUS',
      ignore_fields: {
        description: false,
        priority: false,
        done_ratio: false,
        estimated_hours: false,
        spent_hours: false
      }
    },
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