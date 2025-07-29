=begin
TODO: Write some basic documentation for what you're doing here.
=end

require_relative "../../factories/course_factory"
require_relative "../../factories/announcement_factory"
require_relative "../../factories/wiki_page_factory"
require_relative "../../factories/assignment_factory"
require_relative "../../factories/quiz_factory"
require_relative "../../factories/rubric_factory"
require_relative "../../factories/group_factory"
require 'json'  

class TestData 

  def initialize(data_file_path)

    data_file = File.open data_file_path
    data = JSON.load data_file


    @courses = data["courses"]
    @teachers = data["teachers"]
    @students = data["students"]
  end

  def get_test_course

    course = @courses.shift
    teacher = @teachers.shift
    student = @students.shift

    result = {
      :course_name => course["name"],
      :course_code => course["code"],
      :teacher_name => teacher["name"],
      :teacher_email=> teacher["email"],
      :teacher_password=> teacher["password"],
      :student_name=> student["name"],
      :student_email=> student["email"],
      :student_password=> student["password"]
    }

    result

  end

  def get_course(course_name)
    course = @courses.select {|item| item["name"] == course_name}
    course
  end

  # Returns test data for a discussion corresponding to the given course
  def get_discussion(course_name)
    course = self.get_course(course_name)
    discussion = course["discussions"].shift

    result = {
      :discussion_title => discussion["title"],
      :discussion_message => discussion["message"]
    }

    result
  end

  # Returns test data for an announcement corresponding to the given course
  def get_announcement(course_name)
    course = self.get_course(course_name)
    announcement = course["announcements"].shift

    result = {
      :announcement_title => announcement["title"],
      :announcement_message => announcement["message"]
    }

    result
  end


  def get_quiz(course_name)
    course = self.get_course(course_name)

    quiz = course["quizzes"].shift

    quiz


  end

  # Don't do this, just use the data returned by quiz instead.
  def get_quiz_question(course_name, quiz_name)

    course = self.get_course(course_name)
    quiz = course["quizzes"].select {|item| item.name == quiz_name}

    questions = quiz["questions"]

  end

  def get_student

    student = @students.shift

    result = {
      :student_name => student["name"],
      :student_email => student["email"],
      :student_password => student["password"]
    }

    result
  end

end


class TestCourse 



  attr_reader :course
  attr_reader :logged_in_user
  attr_reader :enrollments
  attr_reader :students
  attr_reader :classmates
  attr_reader :teachers
  attr_reader :discussions
  attr_reader :assignments
  attr_reader :quizzes
  attr_reader :groups
  attr_reader :pages
  attr_reader :teacher
  attr_reader :group #TODO: temp

=begin
Initalize the test course, with an instructor and a student.
The student account will be assumed to be the logged in user for this course. 
=end
  def initialize(data={
    :course_name => "Generic Course",
    :course_code => "GC",
    :teacher_name => "Tammy Teacherson",
    :teacher_email => "teacherson@ualberta.ca",
    :teacher_password => "password",
    :student_name => "Sven Studentson",
    :student_email => "studentson@ualberta.ca",
    :student_password => "password"
  })

    @course
    @logged_in_user
    @teacher
    @enrollments = []
    @students = []
    @classmates = [] # All students that aren't the logged in user
    @teachers = []
    @discussions = []
    @announcements = []
    @assignments = []
    @quizzes = []
    @groups = []
    @pages = []
    

    # Create the course and the teacher user
    course_with_teacher({
      :account => @root_account,
      :course_name => data[:course_name],
      :course_code => data[:course_code],
      :is_public => true,
      :active_course => 1,
      :active_enrollment => 1,
      :name => data[:teacher_name]
    })
    @course = @course
    @teacher = @user
    @enrollments << @enrollment

    @group = @course.assignment_groups.create!(name: "group 1")

    # Setup login details for the teacher account
    @teacher.pseudonyms.create(
      unique_id: data[:teacher_email],
      password: data[:teacher_password],
      password_confirmation: data[:teacher_password]
    )
    @teacher.email = data[:teacher_email]
    @teacher.accept_terms
    @teacher.register!
    
    @teachers << @teacher

    # Add the student to the course.
    course_with_student(
      account: @root_account,
      active_all: 1,
      course: @course,
      name: data[:student_name]
    )
    @enrollments << @entrollment
    @user.pseudonyms.create!(
      unique_id: data[:student_email],
      password: data[:student_password],
      password_confirmation: data[:student_password]
    )
    @user.email = data[:student_email]
    @user.accept_terms
    @students << @user
    @logged_in_user = @user

    @course.root_account.enable_feature! :discussions_reporting


  end

  def default_assignment_opts

    opts = {
      :title => "A simple Assignment",
      :description => "A simple thing to do which will test your understanding.",
      :due_at => Time.zone.now,
      :points_possible => 10,
      :created_at => Time.now.utc,
      :updated_at => Time.now.utc,
      :course => @course,
      :context_id => @course.id,
      :context_type => "Course",
      :submission_types => ["online_text_entry"],
      :workflow_state => "published",
      :grading_type => "points"
    }

  opts

  end

  def create_group(data)
    data[:context] = @course

    group = Factories.group(data.except("users", "discussions"))
 
    data["users"].each {|user| 
      u = resolve_user_value(user, self)
      group.add_user(u, "accepted", false)
    }
    group.name = data["name"]
    group.save!

    @groups << group

    if data["discussions"] # If the group has any discussions create those too. 
      data["discussions"].each {|discussion|
      
      create_group_discussion(group, discussion)

    }
    end

  end

  def create_group_discussion(group, data)

    data["user"] = resolve_user_value(data["user"], self)
    discussion = group.discussion_topics.create!(data.except("replies"))

    discussion.reload
    if data["replies"] # If there are any replies create those too
      data["replies"].each {|reply|
        create_discussion_reply(discussion, reply)
    }
    end

    discussion

  end


  def create_assignment(data={})

    assignment = @course.assignments.create!(data.merge({:assignment_group => @group }))
    @assignments << assignment
    assignment
  end

  def create_announcement(data)

    @context = @course

    data["user"] = resolve_user_value(data["user"], self)
    @announcement = @course.announcements.create!(data.except("replies"))

    @announcement.reload
    @announcements << @announcement

    if data["replies"] # If there are replies to this announcement create them now.
      data["replies"].each {|reply|
      create_discussion_reply(@announcement, reply)
    }
      
    end

    @announcement

  end

  def create_page(data={
    :page_title => "The Example Page",
    :page_body => "I have some text in me!",
    :user => @teacher 
  })

    page = wiki_page_model({
      title: data[:page_title],
      body: data[:page_body],
      user: data[:user],
      course: @course
    })

    page
  end

  def create_discussion(data={
    :title => "Welcome to the course!",
    :message => "Hi everyone! I'd like to welcome you all to Generic Course!", 
    :user => @teacher,
    :discussion_type => "threaded"
  })

  # process user value
  data["user"] = resolve_user_value(data["user"], self)


  @discussion = @course.discussion_topics.create!(data.except("replies"))

  @discussion.reload

  # If this discussion has replies, create them too. 
  if data["replies"]

    data["replies"].each { |reply|
      create_discussion_reply(@discussion, reply)
    }

  end

  @discussions << @discussion
  @discussion

  end

  def create_classmate(data={
    :student_name => "Carl Classmateson",
    :student_email => "classmateson@ualberta.ca",
    :student_password => "password"
  })

    course_with_student(
      account: @root_account,
      active_all: 1,
      course: @course,
      name: data[:student_name]
    )
    @enrollments << @enrollment
    @user.pseudonyms.create!(
      unique_id: data[:student_email],
      password: data[:student_password],
      password_confirmation: data[:student_password]
    )
    @user.email = data[:student_email]
    @user.accept_terms
    @students << @user
    @classmates << @user

    @user
  end

  def create_discussion_assignment(data)
    
=begin
This is where we left off on july 29th, need to implement loading in discussion assignments. 

discussion_assignment = @course.assignments.create!(title: "Del this disc", workflow_state: "active")
d = @course.discussion_topics.create!(assignment: discussion_assignment, title: "Del this disc")
=end



    data = data.merge({:assignment_group => @group})
    assignment = @course.assignments.create!(data.except("peer_reviews", "replies"))

    topic = assignment.discussion_topic

    puts "Created discussion topic? #{topic}"

    if data["replies"]
      data["replies"].each {|reply|
      create_discussion_reply(topic, reply )
    }
    end

    if data["peer_reviews"]
      assignment.peer_review_count = data["peer_reviews"]["count"]
      assignment.automatic_peer_reviews = data["peer_reviews"]["automatic_peer_reviews"]
      assignment.anonymous_peer_reviews = data["peer_reviews"]["anonymous_peer_reviews"]
      assignment.update!(peer_reviews: true)
      assignment.save!

      result = a.assign_peer_reviews
    end
  end

  def create_discussion_reply(discussion, reply)

    replier = reply["user"]
    reply_text = reply["text"]
   


    if replier.is_a? String # If the replier value is a string, resolve it to a user object.
      replier = resolve_user_value(replier, self)
    end

    _reply = discussion.reply_from(user: replier, text: reply_text)
    _reply.reload
    discussion.reload

    # Handle any nestest replies recursively.
    if reply["replies"]
      reply["replies"].each {|r| create_discussion_reply(_reply, r)}
    end

  end

  # A method that resolves user values loaded from the test data.
  # In the test data the value for a 'user' key may be one of the following:
  # 'instructor'/'teacher', 'student', 'logged_in_user'/'main_user' or the email of a particular user. 
  def resolve_user_value(user_value, course)

    # Pick a random instructor
    if user_value == "instructor" || user_value == "teacher"
      return course.teachers.sample
    end

    # Pick a random student
    if user_value == "student" 
      return course.students.sample
    end

    # Pick the main user
    if user_value == "logged_in_user" || user_value == "main_user"
      return course.logged_in_user
    end

    # pick the user corresponding with the provided email address.
    if user_value.include? "@"
      
      pool = []
      pool.concat course.students
      pool.concat course.teachers

      return pool.select {|user| user.email == user_value}.first


    end

  end


end