require 'redmine'

require_dependency 'string'
require_dependency 'element'
require_dependency 'views_issues_index_bottom_hook'

ActionDispatch::Callbacks.to_prepare do
  SettingsHelper.__send__(:include, SettingsHelperPatch)
  Mailer.__send__(:include, ProjectXmlSyncMailer)
  Issue.__send__(:include, IssuePatch)
  Redmine::Views::OtherFormatsBuilder.__send__(:include, ProjectXmlSyncOtherFormatsBuilder)
end

Redmine::Plugin.register :redmine_project_xml_sync do
  name 'Redmine Project Xml Sync plugin'
  author 'Yuichiro Endo'
  description 'OpenSource ProjectManagement software sync Redmine'
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
	    tracker_alias: 'Tracker',
      redmine_id_alias: 'RID',
      redmine_status_alias: 'Status',
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
    permission :import_issues_from_xml, project_xml_sync: [:new, :create]
    permission :export_issues_to_xml, project_xml_sync: :export
  end

  menu :project_menu, :project_xml_sync, { controller: :project_xml_sync, action: :new },
    caption: :menu_caption, after: :new_issue, param: :project_id

  Time::DATE_FORMATS.merge!(
    ms_xml: lambda{ |time| time.strftime("%Y-%m-%dT%H:%M:%S") }
  )
end
