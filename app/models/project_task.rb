class ProjectTask
  attr_accessor :task_id
  attr_accessor :name
  attr_accessor :resource
  attr_accessor :start_date
  attr_accessor :finish_date
  attr_accessor :create_date
  attr_accessor :duration
  attr_accessor :parent_id
  attr_accessor :create
  attr_accessor :outline_level  # The number that indicates the level of a task in the project outline hierarchy.
  attr_accessor :outline_number # same as wbs
  attr_accessor :wbs            # A unique code (work breakdown structure) that represents a task's position within the hierarchical structure of the project.
  attr_accessor :done_ratio
  attr_accessor :priority_id
  attr_accessor :notes

  attr_accessor :tracker
  attr_accessor :redmine_id
  attr_accessor :redmine_status
  attr_accessor :redmine_version
  attr_accessor :redmine_category

  attr_accessor :redmine_custom_field
end