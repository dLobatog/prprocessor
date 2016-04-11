require 'octokit'
require 'retriable'

class PullRequest

  attr_accessor :raw_data, :title, :issue_numbers, :repo, :number, :client, :commits

  def initialize(raw_data)
    self.raw_data = raw_data
    self.title    = raw_data['title']
    self.repo     = raw_data['base']['repo']['full_name']
    self.number   = raw_data['number']
    self.client   = Octokit::Client.new(:access_token => ENV['GITHUB_OAUTH_TOKEN'])

    # Sometimes the GitHub API returns a 404 immediately after PR creation
    Retriable.retriable :on => Octokit::NotFound, :interval => 2, :tries => 10 do
      self.commits = client.pull_commits(repo, number)
    end

    self.issue_numbers = []
    title.scan(/([\s\(\[,-]|^)(fixes|refs)[\s:]+(#\d+([\s,;&]+#\d+)*)(?=[[:punct:]]|\s|<|$)/i) do |match|
      action, refs = match[1].to_s.downcase, match[2]
      next if action.empty?
      refs.scan(/#(\d+)/).each { |m| self.issue_numbers << m[0].to_i }
    end
  end

  def new?
    @raw_data['created_at'] == @raw_data['updated_at']
  end

  def dirty?
    @raw_data['mergeable_state'] == 'dirty' && @raw_data['mergeable'] == false
  end

  def author
    @raw_data['user']['login']
  end

  def target_branch
    @raw_data['base']['ref']
  end

  def labels=(pr_labels)
    @client.add_labels_to_an_issue(@repo, @number, pr_labels)
  end

  def labels
    @client.labels_for_issue(@repo, @number)
  end

  def check_commits_style
    warnings = ''
    @commits.each do |commit|
      if (commit.commit.message.lines.first =~ /\A(fixes|refs) #\d+(, ?#\d+)*(:| -) .*\Z/i) != 0
        warnings += "  * #{commit.sha} must be in the format ```fixes #redmine_number - brief description```\n"
      end
      if commit.commit.message.lines.first.size > 65
        warnings += "  * length of the first commit message line for #{commit.sha} exceeds 65 characters\n"
      end
      commit.commit.message.lines.each do |line|
        if line.size > 72 && line !~ /^\s{4,}/
          warnings += "  * commit message for #{commit.sha} is not wrapped at 72nd column\n"
        end
      end
    end
    message = <<EOM
There were the following issues with the commit message:
#{warnings}

If you don't have a ticket number, please [create an issue in Redmine](http://projects.theforeman.org/projects/foreman/issues/new), selecting the appropriate project.

More guidelines are available in [Coding Standards](http://theforeman.org/handbook.html#Codingstandards) or on [the Foreman wiki](http://projects.theforeman.org/projects/foreman/wiki/Reviewing_patches-commit_message_format).

---------------------------------------
This message was auto-generated by Foreman's [prprocessor](http://projects.theforeman.org/projects/foreman/wiki/PrProcessor)
EOM
    unless warnings.empty?
      add_comment(message)
      self.labels = ['Waiting on contributor']
    end
  end

  def not_yet_reviewed?
    labels.map { |label| label[:name] }.include? 'Not yet reviewed'
  end

  def waiting_for_contributor?
    labels.map { |label| label[:name] }.include? 'Waiting on contributor'
  end

  def replace_labels(remove_labels, add_labels)
    remove_labels.each { |label| @client.remove_label(@repo, @number, label) }
    self.labels = add_labels
  end

  def add_comment(message)
    @client.add_comment(@repo, @number, message)
  end
end
