require_relative "./common"
require_relative "./utils"
require 'json'

def generate_custom_course
  puts "Generating custom course"
  @student_list = []
  @enrollment_list = []
  @course_name = "Custom Course By Alex w/Discussion"
  course_with_teacher(
    account: @root_account,
    active_course: 1,
    active_enrollment: 1,
    course_name:@course_name,
    name: "Robot Alex 2"
  )
  @teacher = @user
  @teacher.pseudonyms.create!(
    unique_id: "newteacher#{@teacher.id}@example.com",
    password: "password",
    password_confirmation: "password"
  )
  @teacher.email = "newteacher#{@teacher.id}@example.com"
  @teacher.accept_terms
  @teacher.register!
  puts "Successfully generated custom course!"

  puts "Adding a student"

  course_with_student(
    account: @root_account,
    active_all: 1,
    course: @course,
    name: "Da Student"
  )

  @enrollment_list << @enrollment
  email = "daStudent#{SecureRandom.alphanumeric(10)}@ualberta.ca"
  @user.pseudonyms.create!(
    unique_id: email,
    password: "password",
    password_confirmation: "password"
  )
  @user.email = email
  @user.accept_terms
  @student_list << @user

  puts @course

  @student = @user

  @topic = @course.discussion_topics.create!(title: "A class discussion", message: "I'd like us to have a discussion.", user: @teacher, discussion_type: "threaded")
  @root_reply = @topic.reply_from(user: @student, text: "Sure!")
  @teacher_reply = @root_reply.reply_from(user: @teacher, text: "Thanks!")

  @all_entries = [@root_reply, @teacher_reply]
  @all_entries.each(&:reload)

  @topic.reload



end

def explore
    course_with_teacher(
    account: @root_account,
    active_course: 1,
    active_enrollment: 1,
    course_name:@course_name,
    name: "Robot Alex 3"
  )
  puts "Printing course"
  puts @course.inspect

  puts "-----------"
  puts @course.methods
end

def generate_test_environment

  @tasks = []

  task = CanvasTask.new("18895195-19df-400c-99f1-b4635028ccb5")
  @tasks << task

  task.create_resources {

    manifest = []



  }


  # Create 'global' collections to hold re-usable resources.
  @students = []
  @instructors = []
  @courses = []
  @assignments = []
  @groups = []
  @discussions = []
  @enrollments = []

  Account.site_admin.enable_feature! :react_discussions_post



  # Setup some dummy data for course creation. 
  course_data = {
    :account => @root_account,
    :course_name => "Generic Course 2",
    :course_code => "GC2",
    :is_public => true,
    :active_course => 1,
    :active_enrollment => 1,
    :name => "Teacherson II"
  }

  # Create a course and instructor using the dummy data.
  course_with_teacher(course_data)
  @teacher = @user

  @courses << @course
  @enrollments << @enrollment

  # Register a pseudonym for the created teacher
  @teacher.pseudonyms.create!(
    unique_id: "teach#{@teacher.id}@ualberta.com",
    password: "password",
    password_confirmation: "password"
  )
  @teacher.email = "teach#{@teacher.id}@ualberta.com"
  @teacher.accept_terms
  @teacher.register!

  @instructors << @teacher

  # Create a student in this course
  course_with_student(
    account: @root_account,
    active_all: 1,
    course: @course,
    name: "Stu"
  )
  @enrollments << @enrollment

  email = "student#{SecureRandom.alphanumeric(5)}@ualberta.ca"
  @user.pseudonyms.create!(
    unique_id: email,
    password: "password",
    password_confirmation: "password"
  )
  @user.email = email
  @user.accept_terms
  @students << @user

  discussion_data = {
    :discussion_title => "Welcome new students!",
    :discussion_body  => "I'd like to welcome everyone to this generic course, we will be learning lots of general things!"
  }

  produce_test_data(@course, @teacher, @user, discussion_data)

  # Create an annoucement
  @context = @course
  announcement_data = {
    :title => "Big announcement!",
    :message => "The big announcement is that this is valid test data for 2 tasks!"
  }
  @announcement  = announcement_model(announcement_data)

  # Create a second student in the course
  course_with_student(
    account: @root_account,
    active_all: 1,
    course: @course,
    name: "Bill"
  )
  @enrollments << @enrollment

  email = "student#{SecureRandom.alphanumeric(5)}@ualberta.ca"
  @user.pseudonyms.create!(
    unique_id: email, 
    password: "password",
    password_confirmation: "password"
  )
  @user.email = email
  @user.accept_terms
  @students << @user

  @classmate = @user

  # Add a reply from a 2nd user
  reply = @announcement.reply_from(user: @classmate, text: "I'm excited!" )
  reply.reload
  
  @announcement.reload

  # Register a 3rd student to the course
  course_with_student(
    account: @root_account,
    active_all: 1,
    course: @course,
    name: "Ted"
  )

  @enrollments << @enrollment

  email = "student#{SecureRandom.alphanumeric(5)}@ualberta.ca"
  @user.pseudonyms.create!(
    unique_id: email,
    password: "password",
    password_confirmation: "password"
  )
  @user.email = email
  @user.accept_terms
  @students << @user

  # Create a discussion with an inappropriate reply
  inappropriate_discussion_data = {
    :discussion_title => "I h8 school!",
    :discussion_body  => "Does anyone else h8 school?! It's so much work!",
    :student_reporting_enabled => true
  }

  inappropriate_discussion = @course.discussion_topics.create!(title: inappropriate_discussion_data[:discussion_title], message: inappropriate_discussion_data[:discussion_body], user: @user, discussion_type: "threaded")
  inappropriate_reply = inappropriate_discussion.reply_from(user: @classmate, text: "I hate everyone so much!")
  inappropriate_reply.reload

  inappropriate_discussion.reload


end

def generate_test_environment_2

  # data_file = File.open "/usr/src/app/spec/fixtures/data_generation/data.json"

  # data = JSON.load data_file
  # puts "Loaded the following json data!"
  # puts data

  tasks = {} # a hash to hold all the tasks we're creating

  tasks["18895195-19df-400c-99f1-b4635028ccb5"] = []
  tasks["1f88f7b8-e990-4bf2-b8e3-a5f4e7133609"] = []
  tasks["1f97e06f-ab71-48c8-ae91-c6cef3b46912"] = []

  test_course = TestCourse.new

  discussion = test_course.create_discussion

  tasks["18895195-19df-400c-99f1-b4635028ccb5"] << {
    "Discussion": discussion.title,
    "Course": test_course.course.name
  }

  classmate = test_course.create_classmate

  test_course.create_discussion_reply(discussion, classmate, "I think inappropriate replies are awesome and I encourage anyone to write the most inappropriate thing possible!")

  announcement = test_course.create_announcement

  reply = test_course.create_discussion_reply(announcement, classmate, "That's really exciting, I'm sure glad I read this!")

  tasks["1f88f7b8-e990-4bf2-b8e3-a5f4e7133609"] << {
    "Announcement" => announcement.title,
    "Course" => test_course.course.name,
    "User" => classmate.name,
    "Date" => reply.posted_at.to_datetime.strftime("%d-%m-%Y"),
    "Time" => reply.posted_at.to_datetime.strftime("%H:%M")
  }

  group_member_1 = test_course.create_classmate

  group_member_2 = test_course.create_classmate



  puts "Tasks"
  puts tasks

end


=begin
Run with:
docker-compose run --remove-orphans web bundle exec rails runner spec/fixtures/data_generation/custom_data.rb
=end

# explore
generate_test_environment_2