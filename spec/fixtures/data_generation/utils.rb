=begin
TODO: Write some basic documentation for what you're doing here.
=end

require_relative "../../factories/course_factory"
require_relative "../../factories/announcement_factory"
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
    discussion
  end

  def get_announcement(course_name)
    course = self.get_course(course_name)
    announcement = course["announcements"].shift
    announcement
  end

  def get_group(course_name)

  def get_student

    student = @students.shift

    result = {
      :student_name => student["name"],
      :student_email => student["email"],
      :student_password => student["password"]
    }

    result

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

    puts "in init, @course is nil? #{@course.nil?}"

  end

  def create_announcement(data={
    :announcement_title => "Big announcement!",
    :announcement_message => "Good news everyone!"
  })

    @context = @course
    @announcement = announcement_model({
      :title=>data[:announcement_title],
      :message=>data[:announcement_message]
    })
    @announcement.reload
    @announcement

  end



  def create_discussion(data={
    :discussion_title => "Welcome to the course!",
    :discussion_message => "Hi everyone! I'd like to welcome you all to Generic Course!", 
    :user => @teacher,
    :discussion_type => "threaded"
  })

  puts "@course is nil? #{@course.nil?}"

  @discussion = @course.discussion_topics.create!(
    title: data[:discussion_title],
    message: data[:discussion_message],
    user: data[:user],
    discussion_type: data[:discussion_type] 
  )

  @discussion.reload
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

  def create_discussion_reply(discussion, replier, reply_text)

    reply = discussion.reply_from(user: replier, text: reply_text)
    reply.reload
    discussion.reload

  end


end