include ProjectXmlSyncHelper

class ProjectXmlExport
  def self.generate_xml(project)
    initValues(project)

    default_calendar_uid = @uid
    
    export = Nokogiri::XML::Builder.new(encoding: 'UTF-8') do |xml|
      resources = @project.assignable_users
      flatissues = RedmineIssueTree.getFlatIssuesFromProject(@project)

      xml.Project(:xmlns=>"http://schemas.microsoft.com/project") {
        xml.Title @project.name
        xml.ExtendedAttributes {
          xml.ExtendedAttribute {
            xml.FieldID 188744000
            xml.FieldName 'Text14'
            xml.Alias @settings[:tracker_alias]
          }
          xml.ExtendedAttribute {
            xml.FieldID 188744001
            xml.FieldName 'Text15'
            xml.Alias @settings[:redmine_id_alias]
          }
          xml.ExtendedAttribute {
            xml.FieldID 188744002
            xml.FieldName 'Text16'
            xml.Alias @settings[:redmine_status_alias]
          }
          xml.ExtendedAttribute {
            xml.FieldID 188744003
            xml.FieldName 'Text17'
            xml.Alias @settings[:redmine_version_alias]
          }
          xml.ExtendedAttribute {
            xml.FieldID 188744004
            xml.FieldName 'Text18'
            xml.Alias @settings[:redmine_category_alias]
          }
        }
        xml.Calendars {
          default_calendar_uid = @uid
          xml.Calendar {
            xml.UID @uid
            xml.Name 'Standard'
            xml.IsBaseCalendar 1
            xml.Weekdays {
              (1..7).each do |day|
                xml.Weekday {
                  xml.DayType day
                  if day.in?([1, 7])
                    xml.DayWorking 0
                  else
                    xml.DayWorking 1
                    xml.WorkingTimes {
                      xml.WorkingTime {
                        xml.FromTime '08:00:00'
                        xml.ToTime '12:00:00'
                      }
                      xml.WorkingTime {
                        xml.FromTime '13:00:00'
                        xml.ToTime '17:00:00'
                      }
                    }
                  end
                }
              end
            }
          }
        }

        xml.Tasks {
          flatissues.each_with_index do |extend_issue, id|
            @uid += 1
            @task_id_to_uid[extend_issue.issue.id] = @uid
            write_task(xml, extend_issue, id.next)
          end
        }

        xml.Resources {
          xml.Resource {
            xml.UID 0
            xml.ID 0
            xml.Type 1
            xml.IsNull 0
          }

          resources.each_with_index do |resource, id|
            spent_time = TimeEntry.where(:user_id => resource.id, :project_id => @project.id).sum(:hours)
            @uid += 1
            @resource_id_to_uid[resource.id] = @uid
            xml.Resource {
              xml.UID @uid
              xml.ID id.next
              xml.Name resource.name
              xml.Type 1
              xml.IsNull 0
              xml.MaxUnits 1.00
              xml.PeakUnits 1.00
              xml.IsEnterprise 1
              xml.CalendarUID default_calendar_uid
              xml.ActualWork get_scorm_time(spent_time) unless spent_time.zero?
            }
          end
        }
        xml.Assignments {
          flatissues.select { |extend_issue| extend_issue.issue.assigned_to_id? && extend_issue.issue.leaf? }.each do |extend_issue|
            issue = extend_issue.issue
            xml.Assignment {
              xml.TaskUID @task_id_to_uid[issue.id]
              xml.ResourceUID @resource_id_to_uid[issue.assigned_to_id]
              unless ignore_field?(:estimated_hours) && !issue.leaf?
                time = get_scorm_time(issue.estimated_hours)
                xml.Work time
                xml.RegularWork time
                xml.RemainingWork time
              end
              xml.PercentWorkComplete issue.done_ratio unless ignore_field?(:done_ratio)
              xml.Units 1
              unless issue.total_spent_hours.zero?
                xml.TimephasedData {
                  xml.Type 2
                  xml.Start (issue.start_date || issue.created_on).to_time.to_s(:project_xml)
                  xml.Finish ((issue.start_date || issue.created_on).to_time + (issue.total_spent_hours.to_i).hours).to_s(:project_xml)
                  xml.Unit 2
                  xml.Value get_scorm_time(issue.total_spent_hours)
                }
              end
            }
          end
        }
      }
    end

    filename = "#{@project.identifier}-#{Time.now.strftime("%Y-%m-%d-%H-%M")}.xml"
    return export.to_xml, filename
  end

private
  def self.initValues(project)
    @project = project

    @settings = Setting.plugin_redmine_project_xml_sync
    @settings_export = @settings[:export]
    @ignore_fields = @settings_export[:ignore_fields].select { |attr, val| val == '1' }.keys

    @uid = 1
    @resource_id_to_uid = {}
    @task_id_to_uid = {}
  end

  def self.ignore_field?(field)
    field.to_s.in?(@ignore_fields)
  end

  def self.get_scorm_time time
    return 'PT8H0M0S' if time.nil? || time.zero?
    time = time.to_s.split('.')
    hours = time.first.to_i
    minutes = time.last.to_i == 0 ? 0 : (60 * "0.#{time.last}".to_f).to_i
    return "PT#{hours}H#{minutes}M0S"
  end

  def self.get_priority_value(priority_name)
    value = case priority_name
            when 'Low','低め' then 300
            when 'Normal','通常' then 500
            when 'High','高め' then 700
            when 'Urgent','急いで' then 800
            when 'Immediate','今すぐ' then 900
            else 500
            end
    return value
  end

  def self.write_task(xml, extend_issue, id)
#redmine          project xml
#'description'    'notes'
#'start_date'     'start'
#'due_date'       'finish'
#'estimated_hours''duration'
#'subject'        'title'
#'done_ratio'     'percentcomplete'
    issue = extend_issue.issue
    xml.Task {
      xml.UID @uid
      xml.ID id
      xml.Name issue.subject
      xml.Notes issue.description unless ignore_field?(:description)
      xml.Active 1
      xml.IsNull 0
      xml.CreateDate issue.created_on.to_s(:project_xml)
      xml.HyperlinkAddress '' #issue_url(issue)
      xml.Priority(ignore_field?(:priority) ? 500 : get_priority_value(issue.priority.name))
      start_date = issue.next_working_date(issue.start_date || issue.created_on.to_date)
      xml.Start start_date.to_time.to_s(:project_xml)
      finish_date = if issue.due_date
                      if issue.next_working_date(issue.due_date).day == start_date.day
                        start_date.next
                      else
                        issue.next_working_date(issue.due_date)
                      end
                    else
                      start_date.next
                    end
      xml.Finish finish_date.to_time.to_s(:project_xml)
      xml.ManualStart start_date.to_time.to_s(:project_xml)
      xml.ManualFinish finish_date.to_time.to_s(:project_xml)
      xml.EarlyStart start_date.to_time.to_s(:project_xml)
      xml.EarlyFinish finish_date.to_time.to_s(:project_xml)
      xml.LateStart start_date.to_time.to_s(:project_xml)
      xml.LateFinish finish_date.to_time.to_s(:project_xml)
      time = get_scorm_time(issue.estimated_hours)
      xml.Work time
      #xml.Duration time
      #xml.ManualDuration time
      #xml.RemainingDuration time
      #xml.RemainingWork time
      #xml.DurationFormat 7
      xml.ActualWork get_scorm_time(issue.total_spent_hours)
      xml.Milestone 0
      xml.FixedCostAccrual 3
      xml.ConstraintType 2
      xml.ConstraintDate start_date.to_time.to_s(:project_xml)
      xml.IgnoreResourceCalendar 0
      parent = issue.leaf? ? 0 : 1
      xml.Summary(parent)
      #xml.Critical(parent)
      xml.Rollup(parent)
      #xml.Type(parent)
      if @export_versions && issue.fixed_version_id
        xml.PredecessorLink {
          xml.PredecessorUID @version_id_to_uid[issue.fixed_version_id]
          xml.CrossProject 0
        }
      end
      if issue.relations_to_ids.any?
        issue.relations.select { |ir| ir.relation_type == 'precedes' }.each do |relation|
          xml.PredecessorLink {
            xml.PredecessorUID @task_id_to_uid[relation.issue_from_id]
            if issue.project_id == relation.issue_from.project_id
              xml.CrossProject 0
            else
              xml.CrossProject 1
              xml.CrossProjectName relation.issue_from.project.name
            end
            xml.LinkLag (relation.delay * 4800)
            xml.LagFormat 7
          }
        end
      end
      xml.ExtendedAttribute {
        xml.FieldID 188744000
        xml.Value issue.tracker.name
      }
      xml.ExtendedAttribute {
        xml.FieldID 188744001
        xml.Value issue.id
      }
      xml.ExtendedAttribute {
        xml.FieldID 188744002
        xml.Value issue.status.name
      }
      xml.WBS(extend_issue.OutlineNumber)
      xml.OutlineNumber extend_issue.OutlineNumber
      xml.OutlineLevel extend_issue.OutlineLevel
    }
  end
end