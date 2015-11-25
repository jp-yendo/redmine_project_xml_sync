include ProjectXmlSyncHelper

class ProjectCsvExport
  attr_accessor :message

  def self.generate_simple_csv(project, export_subproject)
    initValues(project)
    
    if export_subproject == true
      projectids = RedmineIssueTree.getProjectIds(@project.id, nil)

      #csv buffer clear
      csvdata = ""

      first = true
      projectids.each do |projectid|
        project = Project.find_by_id(projectid)
        csvdata = csvdata + generate_project_csv(project, export_subproject, first)
        if first == true
          first = false
        end
      end
    else
      csvdata = generate_project_csv(@project, export_subproject, true)
    end

    filename = "#{@project.identifier}-#{Time.now.strftime("%Y-%m-%d-%H-%M")}.csv"
    return csvdata, filename
  end

  def self.message
    return @message
  end
  
private
  def self.initValues(project)
    @project = project

    @settings = Setting.plugin_redmine_project_xml_sync
    @settings_export = @settings[:export]

    @message = {:notice => nil, :warning => nil, :error => nil}
  end

  def self.generate_project_csv(project, export_subproject, export_header)
    columnbymethod = {
        :id => "id",
        :tracker => "tracker",
        :project_id => "project_id",
        :project_identifier => "get.project_identifier",
        :project_name => "get.project_name",
        :subject => "subject",
        :description => "description",
        :start_date => "start_date",
        :due_date => "due_date",
        :estimated_hours => "estimated_hours",
        :done_ratio => "done_ratio",
        :assigned_to => "assigned_to",
        :fixed_version => "fixed_version",
        :category => "category",
        :status => "status",
        :priority => "priority",
        :parent_issue => "parent_id",
        :is_private => "is_private",
        :actual_time => "calc.ActualTime",
        :actual_first_date => "calc.ActualFirstDate",
        :actual_last_date => "calc.ActualLastDate",
        :actual_progress => "calc.ActualProgress",
        :days_early => "calc.DaysEarly",
        :days_delay => "calc.DaysDelay",
        :count_total_issue => "calc.CountTotalIssue",
        :count_closed_issue => "calc.CountClosedIssue",
        :days_max_early => "calc.DaysMaxEarly",
        :days_max_delay => "calc.DaysMaxDelay",
        :isScheduled => "calc.isScheduled",
        :children_count => "extend.ChildrenCount",
        :outlinelevel => "extend.OutlineLevel",
        :outlinenumber => "extend.OutlineNumber"
      }

    #csv buffer clear
    csvdata = ""
    
    if export_header == true
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
    end

    flatissues = RedmineIssueTree.getFlatIssuesFromProject(project)
    project_identifier = project.identifier
    project_name = project.name
    
    flatissues.each do |exissue|
      csvline = ""

      issue_progress = getIssueProgress(exissue.issue)
      
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
            if export_subproject == true && callmethod == "OutlineNumber"
              value = exissue.issue.project_id.to_s + "." + value
            end
          elsif callmethod.start_with?("get.")
            getname = callmethod[4,callmethod.length-4]
            case getname
            when "project_identifier"
              value = project_identifier
            when "project_name"
              value = project_name
            end
          elsif callmethod.start_with?("calc.")
            calcname = callmethod[5,callmethod.length-5]
            case calcname
            when "ActualTime"
              value = TimeEntry.where(:issue_id => exissue.issue.id).sum(:hours).to_f
            when "ActualFirstDate"
              value = TimeEntry.where(:issue_id => exissue.issue.id).minimum(:spent_on)
            when "ActualLastDate"
              value = TimeEntry.where(:issue_id => exissue.issue.id).maximum(:spent_on)
            when "ActualProgress"
              value = issue_progress.actual_progress
            when "DaysEarly"
              value = issue_progress.days_early
            when "DaysDelay"
              value = issue_progress.days_delay
            when "CountTotalIssue"
              value = issue_progress.count_total_issue
            when "CountClosedIssue"
              value = issue_progress.count_closed_issue
            when "DaysMaxEarly"
              value = issue_progress.days_max_early
            when "DaysMaxDelay"
              value = issue_progress.days_max_delay
            when "isScheduled"
              value = issue_progress.isScheduled
            end
          else
            value = exissue.issue.send(callmethod)
          end
          if value.nil?
            value = ""
          end
        rescue Exception => ex
          Rails.logger.info("Get value error: key:#{key.to_s} message:#{ex.message}")
          value = ""
        end
        csvline += "\""
        csvline += value.to_s.gsub(/"/,"'")
        csvline += "\""
      end

      csvline += "\n"
      csvdata += csvline
    end

    return csvdata
  end
  
  def self.getIssueProgress(issue)
    result  = IssueInfo::new

    if issue.start_date.nil? && issue.due_date.nil?
      result.isScheduled = false
    else
      result.isScheduled = true
    end

    #TODO:再帰呼出しでの分類対応
    #　　　子がある場合は自分を無視して子供のみ集計する
    if issue.children.count > 0
      result.count_total_issue = 0
      result.count_closed_issue = 0
      result.progress = 0
      result.actual_progress = 0
      result.days_early = 0
      result.days_delay = 0
      result.days_max_early = 0
      result.days_max_delay = 0

      total_count = 0
      total_progress = 0
      total_actual_progress = 0
      issue.children.each do |subissue|
        info = getIssueProgress(subissue)

        result.count_total_issue += info.count_total_issue
        result.count_closed_issue += info.count_closed_issue
        result.days_early += info.days_early
        result.days_delay += info.days_delay

        if result.days_max_early < info.days_max_early
          result.days_max_early = info.days_max_early
        end
        if result.days_max_delay < info.days_max_delay
          result.days_max_delay = info.days_max_delay
        end
        
        total_progress += info.progress
        total_actual_progress += info.actual_progress

        total_count += 1
      end

      if total_count > 0
        result.progress = total_progress / total_count
        result.actual_progress = total_actual_progress / total_count
      end
    else
      result.count_total_issue = 1
      if issue.status.is_closed == true
        result.count_closed_issue = 1
      else
        result.count_closed_issue = 0
      end
      result.progress = issue.done_ratio

      if issue.status.is_closed == true || issue.done_ratio == 100 || result.isScheduled == false
        if issue.status.is_closed == true
          result.progress = 100
        end
        result.actual_progress = result.progress
        result.days_early = 0
        result.days_delay = 0
      else
        #Calc
        #TODO: 日毎のデフォルト時間を設定にだす？
        default_hour = 8.0
        if issue.estimated_hours.nil?
          total_hour = 0
        else
          total_hour = issue.estimated_hours
        end
        if issue.start_date.nil?
          start_date = DayInfo.calcProvisionalStartDate(issue.due_date, total_hour, default_hour)
        else        
          start_date = issue.start_date
        end
        if issue.due_date.nil?
          end_date = DayInfo.calcProvisionalEndDate(issue.start_date, total_hour, default_hour)
        else        
          end_date = issue.due_date
        end

        working_days = DayInfo.getWorkdays(start_date, end_date)
        if working_days < 1
          working_days = (end_date - start_date) + 1
        end

        today = Date.today
        if end_date < today
          result.actual_progress = 100
        elsif start_date > today
          result.actual_progress = 0
        else
          temp_working_days = DayInfo.getWorkdays(start_date, today)
          result.actual_progress = temp_working_days * 100 / working_days
        end

        if result.progress > result.actual_progress
          result.days_early = working_days * (result.progress - result.actual_progress) / 100
          result.days_early = result.days_early.floor
          result.days_delay = 0
        elsif result.progress < result.actual_progress
          result.days_early = 0
          result.days_delay = working_days * (result.actual_progress - result.progress) / 100
          result.days_delay = result.days_delay.floor
        else
          result.days_early = 0
          result.days_delay = 0
        end
      end

      result.days_max_early = result.days_early
      result.days_max_delay = result.days_delay
    end

    return result
  end
end