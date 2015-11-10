class RedmineIssueTree

  def self.getFlatIssuesFromProject(project)
    result = []

    getIssues(project, result)

    return result
  end

private
  def self.getIssues(project, result)
Rails.logger.info("----- getIssues")
    root_issues = Issue.all.where(:project_id => project.id, :parent_id => nil)
    root_issues.each_with_index do |root_issue, index|
      extend_issue = ExtendIssue.new
      extend_issue.issue = root_issue
      extend_issue.OutlineLevel = 1
      extend_issue.OutlineNumber = (index+1).to_s
      result << extend_issue

      getNestIssues(root_issue, extend_issue.OutlineLevel, extend_issue.OutlineNumber, result)
    end
  end
  
  def self.getNestIssues(issue, outlinelevel, outlinenumber, result)
Rails.logger.info("----- getNestIssues")
    issue.children.each_with_index do |issue, index|
      extend_issue = ExtendIssue.new
      extend_issue.issue = issue
      extend_issue.OutlineLevel = (outlinelevel+1)
      extend_issue.OutlineNumber = outlinenumber + "." + (index+1).to_s
      result << extend_issue

      getNestIssues(issue, extend_issue.OutlineLevel, extend_issue.OutlineNumber, result)
    end
  end
end
