include ProjectXmlSyncHelper

class ProjectXmlImport
  require 'rexml/document'
  require 'date'

  def self.analyze(project, upload_path)
    initValues(project, upload_path)
    analyze_xml
    return @title, @usermapping, @assignments, @tasks
  end

  def self.import(project, upload_path)
    initValues(project, upload_path)
    analyze_xml
    insert
    return @title, @usermapping, @assignments, @tasks, @root_ids
  end

  def self.message
    return @message
  end

private
  def self.initValues(project, upload_path)
    @project = project
    @upload_path = upload_path

    @settings = Setting.plugin_redmine_project_xml_sync
    @settings_import = @settings[:import]
    @ignore_fields = @settings_import[:ignore_fields].select { |attr, val| val == '1' }.keys

    @resources = []
    @required_custom_fields = []

    @message = {:notice => nil, :alert => nil, :warning => nil, :error => nil}

    @usermapping = []
    @assignments = []
    @tasks       = []
    @root_ids = []
  end

  def self.ignore_field?(field)
    field.to_s.in?(@ignore_fields)
  end
  
  def self.analyze_xml
    content = File.read(@upload_path)

    doc = REXML::Document.new(content)

    root = doc.root

    prefix = "Project Xml Sync(#{Date.today}): "

    doc.elements.each('Project') do |ele|
      tmp_title = ele.elements['Title'].text if ele.elements['Title']
      if tmp_title.nil?
        @title = "ProjectXmlSync_#{User.current}:#{Date.today}"
        @message[:alert] = "No Titel in XML found. I use #{@title} instead!"
      else
        @title = prefix + tmp_title
      end

      ele.each_element('//Resource') do |child|
        if child.elements["UID"] && child.elements["UID"].text.to_i > 0
          @resources.push(xml_resources child)
        end
      end

      resource_uids = []
      ele.each_element('//Assignment') do |child|
        assign = ProjectAssignment.new(child)
        if assign.resource_uid > 0
          resource_uids.push(assign.resource_uid)
          @assignments.push(assign)
        end
      end

      member_uids = @project.members.map { |x| x.user_id}

      resource_uids.uniq.each do |resource_uid|
        resource = @resources.select { |res| res.uid == resource_uid }.first

        unless resource.nil?
          user = resource.map_user(member_uids)
          Rails.logger.info("Name: #{resource.name} Res_ID #{resource_uid} USER: #{user}")
          Rails.logger.info("\n -----------INFO: #{resource.info} Status: #{resource.status}")
          @usermapping.push([resource_uid,resource.name, user, resource.status])
        end

        no_mapping_found = @usermapping.select { |id, name, user_obj, status| status.to_i > 2}.count
        unless no_mapping_found == 0
          @message[:warning] = "Error: #{no_mapping_found} Users missing or not in project! Please resolve manually."
        end
      end

      # check for required custom_fields
      @project.all_issue_custom_fields.each do |custom_field|
        if custom_field.is_required
          @message[:warning] = "Required custom field #{custom_field.name} found. We will set them to 'n.a'"
          @required_custom_fields.push([custom_field.name,'n.a.'])
        end
      end

      ele.each_element('//Task') do |child|
        @tasks.push(xml_tasks child)
      end
    end

    @message[:notice] = "Project successful parsed" if @message.empty?
  end
  
  def self.insert
    Rails.logger.info "Start insert..."

    last_task_id = 0
    parent_id = 0
    last_outline_level = 0
    parent_stack = Array.new #contains a LIFO-stack of parent task

    custom_field_names = []
    @project.all_issue_custom_fields.each do |custom_field|
      custom_field_names.push(custom_field.name)
    end
    
    @tasks.each do |task|
      begin
        unless task.redmine_id.nil? || task.redmine_id.blank?
          issue = Issue.find_by_id(task.redmine_id)
          if issue.nil?
            issue = Issue.new(
              :author   => User.current,
              :project  => @project
              )
            issue.id = task.redmine_id
          end
        else
          issue = Issue.new(
            :author   => User.current,
            :project  => @project
            )
        end

        unless task.tracker.nil? || task.tracker.blank?
          issue.tracker = Tracker.find_by_name(task.tracker)
          if issue.tracker.nil? then raise ActiveRecord::RecordNotFound, "No tracker named #{task.tracker}" end
        else          
          issue.tracker_id = @settings_import[:tracker_id]
        end
        unless task.redmine_status.nil? || task.redmine_status.blank?
          issue.status = IssueStatus.find_by_name(task.redmine_status)
          if issue.status.nil? then raise ActiveRecord::RecordNotFound, "No status named #{task.redmine_status}" end
        else          
          issue.status_id = @settings_import[:issue_status_id]
        end
        unless task.redmine_version.nil? || task.redmine_version.blank?
          issue.fixed_version = Version.find_by_project_id_and_name(@project.id, task.redmine_version)
          if issue.fixed_version.nil? then raise ActiveRecord::RecordNotFound, "No version named #{task.redmine_version}" end
        else
          issue.fixed_version = nil
        end
        unless task.redmine_category.nil? || task.redmine_category.blank?
          issue.category = IssueCategory.find_by_project_id_and_name(@project.id, task.redmine_category)
          if issue.category.nil? then raise ActiveRecord::RecordNotFound, "No category named #{task.redmine_category}" end
        else
          issue.category = nil
        end

        if task.task_id > 0
          issue.subject = task.name
          assign = @assignments.select{|as| as.task_uid == task.task_id}.first
          unless assign.nil?
            Rails.logger.info("Assign: #{assign}")
            mapped_user = @usermapping.select { |id, name, user_obj, status| id == assign.resource_uid and status < 3}.first
            Rails.logger.info("Mapped User: #{mapped_user}")
            issue.assigned_to_id = mapped_user[2].id unless mapped_user.nil?
          else
            issue.assigned_to = nil
          end
        else
          issue.subject = @title
        end

        issue.start_date = task.start_date
        issue.due_date = task.finish_date
        issue.updated_on = task.create_date
        issue.created_on = task.create_date
        issue.estimated_hours = task.duration
        issue.priority_id = task.priority_id
        issue.done_ratio = task.done_ratio
        issue.description = task.notes

        # subtask?
        if task.outline_level > 0
          if task.outline_level > last_outline_level # new subtask
            parent_id = last_task_id
            parent_stack.push(parent_id)
          end

          if task.outline_level < last_outline_level # step back in hierachy
            steps = last_outline_level - task.outline_level
            parent_stack.pop(steps)
            parent_id = parent_stack.last
          end

          if !parent_id.nil? && parent_id > 0
            issue.parent_id = parent_id
          else
            issue.parent_id = nil
          end
        end
        last_outline_level = task.outline_level

        # required custom fields:
        update_custom_fields(issue, @required_custom_fields)

        # set custom field
        if task.redmine_custom_field.length
          task.redmine_custom_field.each_with_index do |value,index|
            custom_field_name = custom_field_names[index]
            if !custom_field_name.blank?
Rails.logger.info("==> " + custom_field_name + value.to_s)
              custom_field = issue.custom_field_values.detect {|c| c.custom_field.name == custom_field_name}
              custom_field.value = value if custom_field
            end
          end
        end
        
        if issue.save
          last_task_id = issue.id
          if issue.parent_id.nil?
            @root_ids.push(issue.id)
          end
          Rails.logger.info "New issue #{task.name} in Project: #{@project} created! id:#{issue.id}, root_id:#{issue.root_id}"
          @message[:notice] = "Project successful inserted!"
        else
          iss_error = issue.errors.full_messages
          Rails.logger.info "Issue #{task.name} in Project: #{@project} gives Error: #{iss_error} root_id:#{issue.root_id}"
          @message[:error] = "Error: #{iss_error}"
          return
        end
      rescue Exception => ex
        @message[:error] = "Error: #{ex.to_s}"
        return
      end
    end
  end
end