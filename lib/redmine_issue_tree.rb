class RedmineIssueTree

  def self.getFlatIssuesFromProject(project)
    result = []

    getIssues(project, result)

    return result
  end

  def self.getProjectIds(projectId, projectIds = nil)
    if projectIds.nil?
      result = [projectId]
    else
      result = projectIds
      result[result.count] = projectId
    end

    subprojects = Project.where(:parent_id => projectId).order(:name)
    subprojects.each do |project|
      result = ProjectInfo.getProjectIds(project.id, result)
    end
    
    return result
  end
  
private
  def self.getIssues(project, result)
    root_issues = Issue.all.where(:project_id => project.id, :parent_id => nil)
    root_issues.each_with_index do |root_issue, index|
      extend_issue = ExtendIssue.new
      extend_issue.issue = root_issue
      extend_issue.ChildrenCount = root_issue.children.count
      extend_issue.OutlineLevel = 1
      extend_issue.OutlineNumber = (index+1).to_s
      extend_issue.OutlineSubject = root_issue.subject
      result << extend_issue

      if extend_issue.ChildrenCount > 0
        getNestIssues(extend_issue, result)
      end
    end
  end
  
  def self.getNestIssues(parent_extend_issue, result)
    parent_extend_issue.issue.children.each_with_index do |issue, index|
      extend_issue = ExtendIssue.new
      extend_issue.issue = issue
      extend_issue.ChildrenCount = issue.children.count
      extend_issue.OutlineLevel = (parent_extend_issue.OutlineLevel + 1)
      extend_issue.OutlineNumber = parent_extend_issue.OutlineNumber + "." + (index+1).to_s
      extend_issue.OutlineSubject = parent_extend_issue.OutlineSubject + "/" + issue.subject
      result << extend_issue

      if extend_issue.ChildrenCount > 0
        getNestIssues(extend_issue, result)
      end
    end
  end
end