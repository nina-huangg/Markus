require File.join(File.dirname(__FILE__), '..', '..',
                  'lib', 'repo', 'repository')
require 'csv_invalid_line_error'

# Maintains group information for a given user on a specific assignment
class Group < ActiveRecord::Base

  after_create :set_repo_name, :build_repository

  has_many :groupings
  has_many :submissions, through: :groupings
  has_many :student_memberships, through: :groupings
  has_many :ta_memberships,
           class_name: 'TaMembership',
           through: :groupings
  has_many :assignments, through: :groupings
  has_many :split_pages


  validates_presence_of :group_name
  validates_uniqueness_of :group_name
  validates_length_of :group_name, maximum: 30

  # prefix used for autogenerated group_names
  AUTOGENERATED_PREFIX = 'group_'

  # Set repository name in database after a new group is created
  def set_repo_name
    # If repo_name has been set already, use this name instead
    # of the autogenerated name.
    if self.repo_name.nil?
      self.repo_name = get_autogenerated_group_name
    end
    self.save(validate: false) # need to save!
  end

  # Returns the repository name for this group
  def repository_name
    self.repo_name
  end

  # Returns an autogenerated name for the group using Group::AUTOGENERATED_PREFIX
  # This only works, after a barebone group record has been created in the database
  def get_autogenerated_group_name
    Group::AUTOGENERATED_PREFIX + self.id.to_s.rjust(4, '0')
  end

  def grouping_for_assignment(aid)
    groupings.where(assignment_id: aid).first
  end

  # Returns the URL for externally accessible repos
  def repository_external_access_url
    MarkusConfigurator.markus_config_repository_external_base_url + '/' + repository_name
  end

  def repository_admin?
    MarkusConfigurator.markus_config_repository_admin?
  end

  def build_repository
    # create repositories if and only if we are admin
    return true if !MarkusConfigurator.markus_config_repository_admin?

    # This might cause repository collision errors, because when the group
    # maximum for an assignment is set to be one, the student's username
    # will be used as the repository name. This will raise a RepositoryCollision
    # if an instructor uses a csv file with a student appearing as the only member of
    # two different groups (remember: uploading via csv purges old groupings).
    #
    # Because we use the group id as part of the repository name in all other cases,
    # a repo collision *should* never occur then.
    #
    # For more info about the exception
    # See 'self.create' of lib/repo/subversion_repository.rb.
    begin
      Repository.get_class(MarkusConfigurator.markus_config_repository_type).create(File.join(MarkusConfigurator.markus_config_repository_storage, repository_name))
    rescue Repository::RepositoryCollision => e
      # log the collision
      errors.add(:base, self.repo_name)
      m_logger = MarkusLogger.instance
      m_logger.log("Creating group '#{self.group_name}' caused repository collision " +
                   "(Repository name was: '#{self.repo_name}'). Error message: '#{e.message}'",
                   MarkusLogger::ERROR)
    end
    true
  end

  # Set the default repo permissions.
  def set_repo_permissions
    return true if !MarkusConfigurator.markus_config_repository_admin?
    # Each admin user will have read and write permissions on each repo
    user_permissions = {}
    Admin.all.each do |admin|
      user_permissions[admin.user_name] = Repository::Permission::READ_WRITE
    end
    # Each grader will have read and write permissions on each repo
    Ta.all.each do |ta|
      user_permissions[ta.user_name] = Repository::Permission::READ_WRITE
    end
    group_repo = Repository.get_class(MarkusConfigurator.markus_config_repository_type)
    group_repo.set_bulk_permissions([File.join(MarkusConfigurator.markus_config_repository_storage, self.repository_name)], user_permissions)
    true
  end

  def repo_loc
    repo_class = Repository.get_class(MarkusConfigurator.markus_config_repository_type)
    repo_loc = File.join(MarkusConfigurator.markus_config_repository_storage, repository_name)
    unless repo_class.repository_exists?(repo_loc)
      raise 'Repository not found and MarkUs not in authoritative mode!' # repository not found, and we are not repo-admin
    end
    repo_loc
  end

  # Return a repository object, if possible
  def repo
    repo_class = Repository.get_class(MarkusConfigurator.markus_config_repository_type)
    repo_class.open(repo_loc)
  end

  #Yields a repository object, if possible, and closes it after it is finished
  def access_repo(&block)
    repo_class = Repository.get_class(MarkusConfigurator.markus_config_repository_type)
    repo_class.access(repo_loc, &block)
  end
end
