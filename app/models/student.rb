# Student user for a given course.
class Student < Role

  scope :active, -> { where(hidden: false) }
  scope :inactive, -> { where(hidden: true) }
  has_many :grade_entry_students, foreign_key: 'role_id'
  has_many :accepted_groupings,
           -> { where 'memberships.membership_status' => [StudentMembership::STATUSES[:accepted], StudentMembership::STATUSES[:inviter]] },
           class_name: 'Grouping',
           through: :memberships,
           source: :grouping

  has_many :pending_groupings,
           -> { where 'memberships.membership_status' => StudentMembership::STATUSES[:pending] },
           class_name: 'Grouping',
           through: :memberships,
           source: :grouping

  has_many :rejected_groupings,
           -> { where 'memberships.membership_status' => StudentMembership::STATUSES[:rejected] },
           class_name: 'Grouping',
           through: :memberships,
           source: :grouping

  has_many :student_memberships, foreign_key: 'role_id'

  has_many :grace_period_deductions, through: :memberships

  belongs_to :section, optional: true
  accepts_nested_attributes_for :section

  validates_presence_of :section, unless: -> { section_id.nil? }

  validates_inclusion_of :receives_invite_emails, in: [true, false]

  validates_inclusion_of :receives_results_emails, in: [true, false]

  validates_numericality_of :grace_credits,
                            only_integer: true,
                            greater_than_or_equal_to: 0

  after_create :create_all_grade_entry_students

  CSV_UPLOAD_ORDER = Settings.student_csv_upload_order.map(&:to_sym)
  SESSION_TIMEOUT = Settings.student_session_timeout

  # Returns true if this student has a Membership in a Grouping for an
  # Assignment with id 'aid', where that Membership.membership_status is either
  # 'accepted' or 'inviter'
  def has_accepted_grouping_for?(aid)
    !accepted_grouping_for(aid).nil?
  end

  # Returns the Grouping for an Assignment with id 'aid' if this Student has
  # a Membership in that Grouping where the membership.status is 'accepted'
  # or 'inviter'
  def accepted_grouping_for(aid)
    accepted_groupings.where(assessment_id: aid).first
  end

  def has_pending_groupings_for?(aid)
    pending_groupings_for(aid).size > 0
  end

  def pending_groupings_for(aid)
    pending_groupings.where(assessment_id: aid)
  end

  def remaining_grace_credits
    return @remaining_grace_credits if !@remaining_grace_credits.nil?
    total_deductions = 0
    grace_period_deductions.each do |grace_period_deduction|
      total_deductions += grace_period_deduction.deduction
    end
    @remaining_grace_credits = grace_credits - total_deductions
  end

  def display_for_note
    human.user_name + ': ' + human.last_name + ', ' + human.first_name
  end

  # invites a student
  def invite(gid)
    unless self.hidden
      membership = StudentMembership.new
      membership.grouping_id = gid
      membership.membership_status = StudentMembership::STATUSES[:pending]
      membership.role_id = self.id
      membership.save
    end
  end

  def destroy_all_pending_memberships(aid)
    # NOTE: no repository permission updates needed since users with
    #       pending status don't have access to repos anyway
    self.pending_groupings_for(aid).each do |grouping|
      membership = grouping.student_memberships.where(role_id: id).first
      membership.destroy
    end
  end

  # creates a group and a grouping for a student to work alone, for
  # assignment aid. If this is a timed assignment, a new group will
  # always be created.
  def create_group_for_working_alone_student(aid)
    @assignment = Assignment.find(aid)
    Group.transaction do
      if @assignment.is_timed
        # must use a new group for timed assignments so that repos are
        # not accessible before the student starts the timer
        @group = Group.new
        @group.save(validate: false)
        @group.group_name = @group.get_autogenerated_group_name
      else
        # If an individual repo has already been created for this user
        # then just use that one.
        @group = Group.find_by(group_name: human.user_name)
        if @group.nil?
          @group = Group.new(group_name: human.user_name)
          # We want to have the user_name as repository name,
          # so we have to set the repo_name before we save the group.
          @group.repo_name = human.user_name
        end
      end
      unless @group.save
        m_logger = MarkusLogger.instance
        m_logger.log("Could not create a group for Student '#{user_name}'."\
            " The group was #{@group.inspect} - errors:"\
            " #{@group.errors.inspect}", MarkusLogger::ERROR)
        raise 'Sorry!  For some reason, your group could not be created.'\
            '  Please wait a few seconds, then hit refresh to try again.  If'\
            ' you come back to this page, you should inform the course'\
            ' instructor.'
      end

      # a grouping can be found if the student has an (empty) existing grouping that he is not a member of
      # this can happen if an instructor removes the student membership from its grouping (see issue 627)
      @grouping = Grouping.find_or_initialize_by(assessment_id: aid, group_id: @group.id)
      unless @grouping.save
        m_logger = MarkusLogger.instance
        m_logger.log("Could not create a grouping for Student '#{user_name}'"\
          ". The grouping was:  #{@grouping.inspect} - errors: "\
          "#{@grouping.errors.inspect}", MarkusLogger::ERROR)
        raise 'Sorry!  For some reason, your grouping could not be created. '\
          ' Please wait a few seconds, and hit refresh to try again.  If you'\
          ' come back to this page, you should inform the course instructor.'
      end

      # Create the membership
      @member = StudentMembership.create!(grouping_id: @grouping.id,
                                          membership_status: StudentMembership::STATUSES[:inviter], role_id: self.id)
      # Destroy all the other memberships for this assignment
      self.destroy_all_pending_memberships(aid)
    end
  end

  def create_autogenerated_name_group(aid)
    Group.transaction do
      group = Group.new
      group.save(validate: false)
      group.group_name = group.get_autogenerated_group_name # the autogen name depends on the id, hence the two saves
      group.save
      grouping = Grouping.create(assessment_id: aid, group_id: group.id)
      StudentMembership.create(grouping_id: grouping.id, membership_status: StudentMembership::STATUSES[:inviter],
                               role_id: self.id)
      self.destroy_all_pending_memberships(aid)
      grouping
    end
  end

  # This method is called when a student joins a grouping
  def join(grouping)
    membership = self.student_memberships.find_by(
      grouping_id: grouping.id,
      membership_status: [StudentMembership::STATUSES[:pending], StudentMembership::STATUSES[:rejected]]
    )
    raise I18n.t('groups.members.errors.not_found') if membership.nil?
    membership.update!(membership_status: StudentMembership::STATUSES[:accepted])

    # Reject all other pending invitations for this assignment
    self.student_memberships
        .joins(:grouping)
        .where('groupings.assessment_id': grouping.assessment_id,
               membership_status: StudentMembership::STATUSES[:pending])
        .update_all(membership_status: StudentMembership::STATUSES[:rejected])
  end

  # Hides a list of students and revokes repository
  # permissions (when exposed externally)
  def self.hide_students(student_id_list)
    update_list = {}
    student_id_list.each do |student_id|
      update_list[student_id] = {hidden: true}
    end
    Student.update(update_list.keys, update_list.values)
  end

  # "Unhides" students not visible and grants repository
  # permissions (when exposed externally)
  def self.unhide_students(student_id_list)
    update_list = {}
    student_id_list.each do |student_id|
      update_list[student_id] = {hidden: false}
    end
    Student.update(update_list.keys, update_list.values)
  end

  def self.give_grace_credits(student_ids, number_of_grace_credits)
    students = Student.find(student_ids)
    students.each do |student|
      student.grace_credits += number_of_grace_credits.to_i
      if student.grace_credits < 0
        student.grace_credits = 0
      end
      student.save
    end
  end

  # Returns true when the student has a section
  def has_section?
    !self.section.nil?
  end

  # Updates the section of a list of students
  def self.update_section(students_ids, nsection)
    students_ids.each do |sid|
      Student.update(sid, {section_id: nsection})
    end
  end

  # Creates grade_entry_student for every marks spreadsheet
  def create_all_grade_entry_students
    GradeEntryForm.all.each do |form|
      unless form.grade_entry_students.exists?(role_id: id)
        form.grade_entry_students.create(role_id: id, released_to_student: false)
      end
    end
  end

  def released_result_for?(assessment)
    if assessment.is_a? GradeEntryForm
      grade_entry_students.find_by(assessment_id: assessment.id)&.released_to_student
    else
      accepted_groupings.find_by(assessment_id: assessment.id)&.current_result&.released_to_students
    end
  end
end
