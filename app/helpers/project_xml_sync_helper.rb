module ProjectXmlSyncHelper
  def issue_deep(issue)
	  @cnt_deep=0
	  if issue.parent_id.nil?
		   return @cnt_deep
		else
		 parent=Issue.find(issue.parent_id)
		 @cnt_deep=1 + issue_deep(parent)
	  end
  end

  def xml_resources resources
      resource = ProjectResource.new
      id = resources.elements['UID']
      resource.uid = id.text.to_i if id
      name = resources.elements['Name']
      resource.name = name.text if name
      return resource    
  end
  
  def create_custom_fields
    IssueCustomField.create(:name => "MS Project WDS", :field_format => 'string') #Beispiel    
  end
  
  def update_custom_fields(issue, fields)
    f_id = Hash.new { |hash, key| hash[key] = nil }
    issue.available_custom_fields.each_with_index.map { |f,indx| f_id[f.name] = f.id }
    field_list = []
    fields.each do |name, value|
      field_id = f_id[name].to_s
      field_list << Hash[field_id, value]
    end
    issue.custom_field_values = field_list.reduce({},:merge)

  end

  def xml_tasks tasks
    task = ProjectTask.new
    task.task_id = tasks.elements['UID'].text.to_i if tasks.elements['UID']
    task.wbs = tasks.elements['WBS'].text if tasks.elements['WBS']
    task.outline_level = tasks.elements['OutlineLevel'].text.to_i if tasks.elements['OutlineLevel']

    name = tasks.elements['Name']
    task.name = name.text if name

    start_date = tasks.elements['Start']
    task.start_date = start_date.text.split('T')[0] if start_date

    finish_date = tasks.elements['Finish']
    task.finish_date = finish_date.text.split('T')[0] if finish_date

    create_date = tasks.elements['CreateDate']
    date_time = create_date.text.split('T') if create_date
    task.create_date = date_time[0] + ' ' + date_time[1] if date_time

    duration_arr = tasks.elements["Duration"].text.split("H") if tasks.elements['Duration']
    task.duration = duration_arr[0][2..duration_arr[0].size-1] if duration_arr       

    task.done_ratio = tasks.elements["PercentComplete"].text if tasks.elements["PercentComplete"]
	task.outline_level = tasks.elements["OutlineLevel"].text.to_i if tasks.elements['OutlineLevel']

    priority = tasks.elements["Priority"].text if tasks.elements["Priority"]
    if priority.nil? || priority == ""
      task.priority_id = 2  #normal
    else
      case priority.to_i
      when 0..300
        task.priority_id = 1  #Low
      when 301..699
        task.priority_id = 2  #Normal
      when 700..799
        task.priority_id = 3  #High
      when 800..899
        task.priority_id = 4  #Urgent
      else
        task.priority_id = 5  #Immediate
      end
    end
    task.notes=tasks.elements["Notes"].text if tasks.elements["Notes"]

    tasks.each_element("ExtendedAttribute") do |node|
      task.redmine_custom_field = []

      unless node.elements["Value"].nil?
        case node.elements["FieldID"].text
        when "188744000"
          task.tracker = node.elements["Value"].text
        when "188744001"
          task.redmine_id = node.elements["Value"].text
        when "188744002"
          task.redmine_status = node.elements["Value"].text
        when "188744003"
          task.redmine_version = node.elements["Value"].text
        when "188744004"
          task.redmine_category = node.elements["Value"].text
        when "188744007","188744008","188744009","188744010","188744011","188744012","188744013","188744014","188744015","188744016"
          idnum = node.elements["FieldID"].text.to_i
          index = idnum - 188744007
          if index >= 0
            task.redmine_custom_field[index] = node.elements["Value"].text
          end
        end
      end
    end
    
    return task
  end rescue raise 'parse error'

  def matched_attrs(column)
    matched = ''
    @attrs.each do |k,v|
      if v.to_s.casecmp(column.to_s.sub(" ") {|sp| "_" }) == 0 \
        || k.to_s.casecmp(column.to_s) == 0

        matched = v
      end
    end
    matched
  end

  def force_utf8(str)
    str.unpack("U*").pack('U*')
  end
  
private
  def has_task name, issues
    issues.each do |issue|
      return true if issue.subject == name
    end
    false
  end
end