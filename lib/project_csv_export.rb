include ProjectXmlSyncHelper

class ProjectCsvExport
  
  def self.generate_simple_csv(project)
    initValues(project)

    columnbymethod = {
        :id => "id",
        :tracker => "tracker",
        :subject => "subject",
        :description => "description",
        :start_date => "start_date",
        :due_date => "due_date",
        :estimated_hours => "estimated_hours",
        :done_ratio => "done_ratio",
        :assigned_to => "assigned_to_id",
        :fixed_version => "fixed_version",
        :category => "category",
        :status => "status",
        :priority => "priority",
        :parent_id => "parent_id",
        :is_private => "is_private",
        :entryhour => "extend.EntryHour",
        :outlinelevel => "extend.OutlineLevel",
        :outlinenumber => "extend.OutlineNumber"
      }
    
    flatissues = RedmineIssueTree.getFlatIssuesFromProject(@project)

    #csv buffer clear
    csvdata = ""

    first = true
    columnbymethod.keys.each do |key|
      if first
        first = false
      else
        csvdata += ","
      end
      csvdata += key.to_s
    end
    csvdata += "\n"

    flatissues.each do |exissue|
      csvline = ""

      first = true
      columnbymethod.keys.each do |key|
        if first
          first = false
        else
          csvline += ","
        end
        begin
          callmethod = columnbymethod[key].to_s
          if callmethod.start_with?("extend.")
            callmethod = callmethod[7,callmethod.length-7]
            value = exissue.send(callmethod)
          else
            value = exissue.issue.send(callmethod)
          end
          if value.nil?
            value = ""
          end
        rescue
          value = ""
        end
        csvline += """"
        csvline += value.to_s
        csvline += """"
      end

      csvline += "\n"
      csvdata += csvline
    end

    filename = "#{@project.name}-#{Time.now.strftime("%Y-%m-%d-%H-%M")}.csv"
    return csvdata, filename
  end

  def self.message
    return @message
  end
  
private
  def self.initValues(project)
    @project = project

    @settings ||= Setting.plugin_redmine_project_xml_sync
    @ignore_fields = @settings[:export][:ignore_fields].select { |attr, val| val == '1' }.keys

    @message = {:notice => nil, :warning => nil, :error => nil}
  end
end