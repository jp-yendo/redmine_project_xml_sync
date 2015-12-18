require 'csv'
require 'tempfile'

class ProjectCsvImport
  ISSUE_ATTRS = [:id, :subject, :assigned_to, :fixed_version,
                 :author, :description, :category, :priority, :tracker, :status,
                 :start_date, :due_date, :done_ratio, :estimated_hours,
                 :parent_issue, :watchers ]

  def self.match(targetproject, import_params)
    initValues(targetproject)

    begin
      case import_params[:csv_import_encoding]
      when "S"
        @csv_data = File.read(import_params[:csv_file_path], :encoding => Encoding::SJIS)
        @csv_data = StringEncorder.convert_sjis_to_utf8(@csv_data)
      else
        @csv_data = File.read(import_params[:csv_file_path], :encoding => Encoding::UTF_8)
      end
    rescue Exception => ex
      @message[:error] = ex.message
      return
    end
    
    validate_csv_data()
    return if @message[:error].present?

    sample_data(import_params)
    return if @message[:error].present?

    set_csv_headers(import_params)
    return if @message[:error].present?

    i18 = Object.new
    i18.extend Redmine::I18n

    # fields
    @attrs = Array.new
    ISSUE_ATTRS.each do |attr|
      @attrs.push([i18.l_or_humanize(attr, :prefix=>"field_"), attr])
    end
    @project.all_issue_custom_fields.each do |cfield|
      @attrs.push([cfield.name, cfield.name])
    end
    IssueRelation::TYPES.each_pair do |rtype, rinfo|
      @attrs.push([i18.l_or_humanize(rinfo[:name]),rtype])
    end
    @attrs.sort!
    
    return @headers, @attrs, @samples
  end

  def self.result(targetproject, import_params, params)
    initValues(targetproject)

    # Used to optimize some work that has to happen inside the loop
    unique_attr_checked = false

    begin
      case import_params[:csv_import_encoding]
      when "S"
        @csv_data = File.read(import_params[:csv_file_path], :encoding => Encoding::SJIS).encode(Encoding::UTF_8)
      else
        @csv_data = File.read(import_params[:csv_file_path], :encoding => Encoding::UTF_8)
      end
    rescue Exception => ex
      @message[:error] = ex.message
      return
    end
    
    # which options were turned on?
    update_issue = params[:update_issue]
    update_other_project = params[:update_other_project]
    send_emails = params[:send_emails]
    add_categories = params[:add_categories]
    add_versions = params[:add_versions]
    use_issue_id = params[:use_issue_id].present? ? true : false
    ignore_non_exist = params[:ignore_non_exist]

    # which fields should we use? what maps to what?
    unique_field = params[:unique_field].empty? ? nil : params[:unique_field]

    fields_map = {}
    params[:fields_map].each { |k, v| fields_map[k.unpack('U*').pack('U*')] = v }
    unique_attr = fields_map[unique_field]

    default_tracker = params[:default_tracker]
    default_status = @settings_import[:issue_status_id]
    journal_field = params[:journal_field]

    # attrs_map is fields_map's invert
    @attrs_map = fields_map.invert

    # validation!
    # if the unique_attr is blank but any of the following opts is turned on,
    if unique_attr.blank?
      i18 = Object.new
      i18.extend Redmine::I18n

      if update_issue
        @message[:error] = i18.l(:text_rmi_specify_unique_field_for_update)
      elsif @attrs_map["parent_issue"].present?
        @message[:error] = i18.l(:text_rmi_specify_unique_field_for_column,
                          :column => i18.l(:field_parent_issue))
      else IssueRelation::TYPES.each_key.any? { |t| @attrs_map[t].present? }
        IssueRelation::TYPES.each_key do |t|
          if @attrs_map[t].present?
            @message[:error] = i18.l(:text_rmi_specify_unique_field_for_column,
                              :column => i18.l("label_#{t}".to_sym))
          end
        end
      end
    end

    # validate that the id attribute has been selected
    if use_issue_id
      if @attrs_map["id"].blank?
        @message[:error] = "You must specify a column mapping for id" \
          " when importing using provided issue ids."
      end
    end

    # if error is full, NOP
    if @message[:error].present?
      return @messages, @handle_count, @affect_projects_issues, @failed_count, @headers, @failed_issues
    end

    csv_opt = {:headers=>true,
               :encoding=>import_params[:csv_import_encoding],
               :quote_char=>import_params[:csv_import_wrapper],
               :col_sep=>import_params[:csv_import_splitter]}
    CSV.new(@csv_data, csv_opt).each do |row|

      project = if isAattrsMap("project") then Project.find_by_name(fetch("project", row)) end
      project ||= @project

      begin
        row.each do |k, v|
          k = k.unpack('U*').pack('U*') if k.kind_of?(String)
          v = v.unpack('U*').pack('U*') if v.kind_of?(String)

          row[k] = v
        end

        issue = Issue.new

        if use_issue_id
          issue.id = fetch("id", row)
        end

        tracker = if isAattrsMap("tracker") then Tracker.find_by_name(fetch("tracker", row)) else nil end
        status = if isAattrsMap("status") then IssueStatus.find_by_name(fetch("status", row)) else nil end
        author = if isAattrsMap("author")
                   user_for_login!(fetch("author", row), params[:use_anonymous])
                 else
                   User.current
                 end
        priority = Enumeration.find_by_name(fetch("priority", row))
        category_name = if isAattrsMap("category") then fetch("category", row) else nil end
        unless category_name.blank?
          category = IssueCategory.find_by_project_id_and_name(project.id, category_name)
        end

        if (!category) \
          && category_name && category_name.length > 0 \
          && add_categories

          category = project.issue_categories.build(:name => category_name)
          category.save
        end

        if isAattrsMap("assigned_to")
          assigned_to_name = fetch("assigned_to", row)
          unless assigned_to_name.blank?
            assigned_to = user_for_login!(assigned_to_name, params[:use_anonymous])
          end
        end

        if isAattrsMap("fixed_version")
          fixed_version_name = fetch("fixed_version", row)
          unless fixed_version_name.blank?
            fixed_version_id = version_id_for_name!(project, fixed_version_name, add_versions)
          end
        end

        watchers = fetch("watchers", row)

        if !project.nil?
          issue.project_id = project.id
        else
          issue.project_id = @project.id
        end
        if !tracker.nil?
          issue.tracker_id = tracker.id
        else
          issue.tracker_id = default_tracker
        end
        if !status.nil?
          issue.status_id = status.id
        else
          issue.status_id = default_status
        end
        if !author.nil?
          issue.author_id = author.id
        else
          issue.author_id = User.current.id
        end
      rescue ActiveRecord::RecordNotFound
        log_failure(row, "Warning: When adding issue #{@failed_count+1} below," \
                    " the #{@unfound_class} #{@unfound_key} was not found")
        raise RowFailed
      end

      begin
        unique_attr = translate_unique_attr(issue, unique_field, unique_attr, unique_attr_checked)

        issue, journal = handle_issue_update(issue, row, author, status, update_other_project, journal_field,
                                             unique_attr, unique_field, ignore_non_exist, update_issue)

        project ||= Project.find_by_id(issue.project_id)

        update_project_issues_stat(project)

        assign_issue_attrs(issue, category, fixed_version_id, assigned_to, status, row, priority)
        handle_parent_issues(issue, row, ignore_non_exist, unique_attr)
        handle_custom_fields(add_versions, issue, project, row, params[:use_anonymous])
        handle_watchers(issue, row, watchers, params[:use_anonymous])
      rescue RowFailed
        next
      end

      begin
        issue_saved = issue.save
      rescue ActiveRecord::RecordNotUnique
        issue_saved = false
        @messages << "This issue id has already been taken."
      end

      unless issue_saved
        @failed_count += 1
        @failed_issues[@failed_count] = row
        @messages << "Warning: The following data-validation errors occurred" \
          " on issue #{@failed_count} in the list below"
        issue.errors.each do |attr, error_message|
          @messages << "Error: #{attr} #{error_message}"
        end
      else
        if unique_field
          @issue_by_unique_attr[row[unique_field]] = issue
        end

        if send_emails
          if update_issue
            if Setting.notified_events.include?('issue_updated') \
               && (!issue.current_journal.empty?)
              
              Mailer.deliver_issue_edit(issue.current_journal)
            end
          else
            if Setting.notified_events.include?('issue_added')
              Mailer.deliver_issue_add(issue)
            end
          end
        end
        
        # Issue relations
        begin
          IssueRelation::TYPES.each_pair do |rtype, rinfo|
            if !row[@attrs_map[rtype]]
              next
            end
            other_issue = issue_for_unique_attr(unique_attr,
                                                row[@attrs_map[rtype]],
                                                row)
            relations = issue.relations.select do |r|
              (r.other_issue(issue).id == other_issue.id) \
                && (r.relation_type_for(issue) == rtype)
            end
            if relations.length == 0
              relation = IssueRelation.new(:issue_from => issue,
                                           :issue_to => other_issue,
                                           :relation_type => rtype)
              relation.save
            end
          end
        rescue NoIssueForUniqueValue
          if ignore_non_exist
            @skip_count += 1
            next
          end
        rescue MultipleIssuesForUniqueValue
          break
        end

        if journal
          journal
        end

        @handle_count += 1

      end

    end # do

    if @failed_issues.size > 0
      @failed_issues = @failed_issues.sort
      @headers = @failed_issues[0][1].headers
    end

    return @messages, @handle_count, @affect_projects_issues, @failed_count, @headers, @failed_issues
  end

  def self.message
    return @message
  end

private
  def self.initValues(project)
    @project = project

    @settings = Setting.plugin_redmine_project_xml_sync
    @settings_import = @settings[:import]

    @message = {:notice => nil, :warning => nil, :error => nil}
    
    @handle_count = 0
    @update_count = 0
    @skip_count = 0
    @failed_count = 0
    @failed_issues = Hash.new
    @messages = Array.new
    @affect_projects_issues = Hash.new
    # This is a cache of previously inserted issues indexed by the value
    # the user provided in the unique column
    @issue_by_unique_attr = Hash.new
    # Cache of user id by login
    @user_by_login = Hash.new
    # Cache of Version by name
    @version_id_by_name = Hash.new
  end

  def self.isAattrsMap(key)
    return (@attrs_map[key].blank? == false)
  end
  
  def self.parseDate(datestring)
    if datestring.nil?
      return nil
    end
    return Date.parse(datestring) rescue nil
  end
  
  def self.translate_unique_attr(issue, unique_field, unique_attr, unique_attr_checked)
    # translate unique_attr if it's a custom field -- only on the first issue
    if !unique_attr_checked
      if unique_field && !ISSUE_ATTRS.include?(unique_attr.to_sym)
        issue.available_custom_fields.each do |cf|
          if cf.name == unique_attr
            unique_attr = "cf_#{cf.id}"
            break
          end
        end
      end
      unique_attr_checked = true
    end
    unique_attr
  end

  def self.handle_issue_update(issue, row, author, status, update_other_project, journal_field, unique_attr, unique_field, ignore_non_exist, update_issue)
    if update_issue
      begin
        issue = issue_for_unique_attr(unique_attr, row[unique_field], row)

        # ignore other project's issue or not
        if issue.project_id != @project.id && !update_other_project
          @skip_count += 1
          raise RowFailed
        end

        # init journal
        note = row[journal_field] || ''
        journal = issue.init_journal(author || User.current,
                                     note || '')
        journal.notify = false #disable journal's notification to use custom one down below
        @update_count += 1

      rescue NoIssueForUniqueValue
        if ignore_non_exist
          @skip_count += 1
          raise RowFailed
        else
          log_failure(row,
                      "Warning: Could not update issue #{@failed_count+1} below," \
                        " no match for the value #{row[unique_field]} were found")
          raise RowFailed
        end

      rescue MultipleIssuesForUniqueValue
        log_failure("Warning: Could not update issue #{@failed_count+1} below," \
                      " multiple matches for the value #{row[unique_field]} were found")
        raise RowFailed
      end
    end
    return issue, journal
  end

  def self.update_project_issues_stat(project)
    if @affect_projects_issues.has_key?(project.name)
      @affect_projects_issues[project.name] += 1
    else
      @affect_projects_issues[project.name] = 1
    end
  end

  def self.assign_issue_attrs(issue, category, fixed_version_id, assigned_to, status, row, priority)
    # required attributes
    issue.status_id = status != nil ? status.id : issue.status_id
    issue.priority_id = priority != nil ? priority.id : issue.priority_id
    issue.subject = fetch("subject", row) || issue.subject
    issue.done_ratio = fetch("done_ratio", row) || issue.done_ratio

    # optional attributes
    issue.description = if isAattrsMap("description") then fetch("description", row) else issue.description end
    if isAattrsMap("category")
      issue.category_id = category != nil ? category.id : nil
    end

    issue.start_date = if isAattrsMap("start_date") then parseDate(fetch("start_date", row)) else issue.start_date end
    issue.due_date = if isAattrsMap("due_date") then parseDate(fetch("due_date", row)) else issue.due_date end
    if isAattrsMap("assigned_to")
      issue.assigned_to_id = assigned_to != nil ? assigned_to.id : nil
    end
    issue.fixed_version_id = if isAattrsMap("fixed_version") then fixed_version_id else issue.fixed_version_id end
    issue.estimated_hours = if isAattrsMap("estimated_hours") then fetch("estimated_hours", row) else issue.estimated_hours end
  end

  def self.handle_parent_issues(issue, row, ignore_non_exist, unique_attr)
    begin
      parent_value = row[@attrs_map["parent_issue"]]
      if parent_value && (parent_value.length > 0)
        issue.parent_issue_id = issue_for_unique_attr(unique_attr, parent_value, row).id
      end
    rescue NoIssueForUniqueValue
      if ignore_non_exist
        @skip_count += 1
      else
        @failed_count += 1
        @failed_issues[@failed_count] = row
        @messages << "Warning: When setting the parent for issue #{@failed_count} below,"\
            " no matches for the value #{parent_value} were found"
        raise RowFailed
      end
    rescue MultipleIssuesForUniqueValue
      @failed_count += 1
      @failed_issues[@failed_count] = row
      @messages << "Warning: When setting the parent for issue #{@failed_count} below," \
          " multiple matches for the value #{parent_value} were found"
      raise RowFailed
    end
  end
  
  def self.handle_watchers(issue, row, watchers, use_anonymous)
    watcher_failed_count = 0
    if watchers
      addable_watcher_users = issue.addable_watcher_users
      watchers.split(',').each do |watcher|
        begin
          watcher_user = user_id_for_login!(watcher, use_anonymous)
          if issue.watcher_users.include?(watcher_user)
            next
          end
          if addable_watcher_users.include?(watcher_user)
            issue.add_watcher(watcher_user)
          end
        rescue ActiveRecord::RecordNotFound
          if watcher_failed_count == 0
            @failed_count += 1
            @failed_issues[@failed_count] = row
          end
          watcher_failed_count += 1
          @messages << "Warning: When trying to add watchers on issue" \
                " #{@failed_count} below, User #{watcher} was not found"
        end
      end
    end
    raise RowFailed if watcher_failed_count > 0
  end

  def self.handle_custom_fields(add_versions, issue, project, row, use_anonymous)
    custom_failed_count = 0
    issue.custom_field_values = issue.available_custom_fields.inject({}) do |h, cf|
      value = row[@attrs_map[cf.name]]
      unless value.blank?
        if cf.multiple
          h[cf.id] = process_multivalue_custom_field(issue, cf, value)
        else
          begin
            value = case cf.field_format
                      when 'user'
                        user_id_for_login!(value, use_anonymous).to_s
                      when 'version'
                        version_id_for_name!(project, value, add_versions).to_s
                      when 'date'
                        value.to_date.to_s(:db)
                      else
                        value
                    end
            h[cf.id] = value
          rescue
            if custom_failed_count == 0
              custom_failed_count += 1
              @failed_count += 1
              @failed_issues[@failed_count] = row
            end
            @messages << "Warning: When trying to set custom field #{cf.name}" \
                           " on issue #{@failed_count} below, value #{value} was invalid"
          end
        end
      end
      h
    end
    raise RowFailed if custom_failed_count > 0
  end

  def self.fetch(key, row)
    row[@attrs_map[key]]
  end

  def self.log_failure(row, msg)
    @failed_count += 1
    @failed_issues[@failed_count] = row
    @messages << msg
  end

  def self.validate_csv_data()
    if @csv_data.lines.to_a.size <= 1
      @message[:error] = 'No data line in your CSV, check the encoding of the file'\
        '<br/><br/>Header :<br/>'.html_safe + @csv_data
      return
    end
  end

  def self.sample_data(import_params)
    # display sample
    sample_count = 5
    @samples = []

    csv_opt = {:headers=>true,
               :encoding=>import_params[:csv_import_encoding],
               :quote_char=>import_params[:csv_import_wrapper],
               :col_sep=>import_params[:csv_import_splitter]}
    begin
      CSV.new(@csv_data, csv_opt).each_with_index do |row, i|
                               @samples[i] = row
                               break if i >= sample_count
                             end # do

    rescue Exception => e
      csv_data_lines = @csv_data.lines.to_a

      error_message = e.message +
        '<br/><br/>Header :<br/>'.html_safe +
        csv_data_lines[0]

      # if there was an exception, probably happened on line after the last sampled.
      if csv_data_lines.size > 0
        error_message += '<br/><br/>Error on header or line :<br/>'.html_safe +
          csv_data_lines[@samples.size + 1]
      end

      @message[:error] = error_message

      return
    end
  end

  def self.set_csv_headers(import_params)
    if @samples.size > 0
      @headers = @samples[0].headers
    end

    missing_header_columns = ''
    @headers.each_with_index{|h, i|
      if h.nil?
        missing_header_columns += " #{i+1}"
      end
    }

    if missing_header_columns.present?
      @message[:error] = "Column header missing : #{missing_header_columns}" \
      " / #{@headers.size} #{'<br/><br/>Header :<br/>'.html_safe}" \
      " #@csv_data.lines.to_a[0]}"
      return
    end

  end

  # Returns the issue object associated with the given value of the given attribute.
  # Raises NoIssueForUniqueValue if not found or MultipleIssuesForUniqueValue
  def self.issue_for_unique_attr(unique_attr, attr_value, row_data)
    if @issue_by_unique_attr.has_key?(attr_value)
      return @issue_by_unique_attr[attr_value]
    end

    if unique_attr == "id"
      issue = Issue.find_by_id(attr_value)
    else
      query = IssueQuery.new(:name => "_importer", :project_id => @project.id)
      #query.add_filter("status_id", "*", [1])
      query.add_filter(unique_attr, "=", [attr_value])

      issues = Issue.all.where(query.statement).limit(2)
      if issues.size > 1
        @failed_count += 1
        @failed_issues[@failed_count] = row_data
        @messages << "Warning: Unique field #{unique_attr} with value " \
          "'#{attr_value}' in issue #{@failed_count} has duplicate record"
        raise MultipleIssuesForUniqueValue, "Unique field #{unique_attr} with" \
          " value '#{attr_value}' has duplicate record"
      elsif issues.size == 1
        issue = issues.first
      end
    end

    if issue.nil?
      raise NoIssueForUniqueValue, "No issue with #{unique_attr} of '#{attr_value}' found"
    end
    
    return issue
  end

  # Returns the id for the given user or raises RecordNotFound
  # Implements a cache of users based on login name
  def self.user_for_login!(login, use_anonymous)
    if login.nil?
      return nil
    end
    
    name_arr = login.split(/[\,]?\s+/) # Split on comma or whitespace
    if name_arr.length > 1
      users_found = User.where("firstname LIKE ? AND lastname LIKE ?", "%#{name_arr[0]}%", "%#{name_arr[1]}%")
      users_found += User.where("firstname LIKE ? AND lastname LIKE ?", "%#{name_arr[1]}%", "%#{name_arr[0]}%")
      unless users_found.nil? || users_found.empty?
        if users_found.count == 1
          user = users_found.first
          @user_by_login[user.login] = user
          @user_by_login[login] = user
        end
      end
    end

    begin
      if !@user_by_login.has_key?(login)
        @user_by_login[login] = User.find_by_login!(login)
      end
    rescue ActiveRecord::RecordNotFound
      if use_anonymous
        @user_by_login[login] = User.anonymous()
      else
        @unfound_class = "User"
        @unfound_key = login
        raise
      end
    end
    @user_by_login[login]
  end

  def self.user_id_for_login!(login, use_anonymous)
    user = user_for_login!(login, use_anonymous)
    user ? user.id : nil
  end

  # Returns the id for the given version or raises RecordNotFound.
  # Implements a cache of version ids based on version name
  # If add_versions is true and a valid name is given,
  # will create a new version and save it when it doesn't exist yet.
  def self.version_id_for_name!(project,name,add_versions)
    if !@version_id_by_name.has_key?(name)
      version = Version.find_by_project_id_and_name(project.id, name)
      if !version
        if name && (name.length > 0) && add_versions
          version = project.versions.build(:name=>name)
          version.save
        else
          @unfound_class = "Version"
          @unfound_key = name
          raise ActiveRecord::RecordNotFound, "No version named #{name}"
        end
      end
      @version_id_by_name[name] = version.id
    end
    @version_id_by_name[name]
  end

  def self.process_multivalue_custom_field(issue, custom_field, csv_val)
    csv_val.split(',').map(&:strip).map do |val|
      if custom_field.field_format == 'version'
        version = Version.find_by_name val
        version.id
      else
        val
      end
    end
  end

  class RowFailed < Exception
  end
end
