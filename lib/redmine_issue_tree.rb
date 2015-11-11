class RedmineIssueTree

  def self.getFlatIssuesFromProject(project)
    result = []

    getIssues(project, result)

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
      result << extend_issue

      if extend_issue.ChildrenCount > 0
        getNestIssues(root_issue, extend_issue.OutlineLevel, extend_issue.OutlineNumber, result)
      end
    end
  end
  
  def self.getNestIssues(issue, outlinelevel, outlinenumber, result)
    issue.children.each_with_index do |issue, index|
      extend_issue = ExtendIssue.new
      extend_issue.issue = issue
      extend_issue.ChildrenCount = issue.children.count
      extend_issue.OutlineLevel = (outlinelevel+1)
      extend_issue.OutlineNumber = outlinenumber + "." + (index+1).to_s
      result << extend_issue

      if extend_issue.ChildrenCount > 0
        getNestIssues(issue, extend_issue.OutlineLevel, extend_issue.OutlineNumber, result)
      end
    end
  end
end