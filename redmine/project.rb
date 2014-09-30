require 'date'
require File.join(File.dirname(__FILE__), 'redmine_resource')

# Issue model on the client side
class Project < RedmineResource

  def base_path
    '/projects'
  end

  def get_versions
    get("#{@raw_data['project']['id']}/versions")
  end

  def get_issues(params = {})
    get("#{@raw_data['project']['id']}/issues", params)
  end

  def get_issues_for_release(id)
    get_issues(:release_id => id, :limit => 200, :status_id => "*")
  end

  def current_version
    versions = get_versions['versions']
    versions = versions.select { |version| version['due_date'] }
    versions.sort! { |a,b| a['due_date'] <=> b['due_date'] }
    versions.find do |version|
      version['status'] == 'open' && Date.parse(version['due_date']) >= Date.today
    end
  end

end
