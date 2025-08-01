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
require_relative "../../factories/assessment_request"
require 'json'  

class AgentTask

  @@groups = []
  @@assignments = []
  @@quizzes = []
  @@discussions = []
  @@pages = []
  @@modules = []

  def self.groups
    @@groups
  end

  def self.assignments
    @@assignments
  end

  def self.quizzes
    @@quizzes
  end

  def self.discussions
    @@discussions
  end

  def self.pages
    @@pages
  end

  def self.modules
    @@modules
  end
  
  attr_reader :id
  attr_reader :parameterized_text
  attr_accessor :instance_text


  def initialize(data)
    @id = data[:id]
    @parameterized_text = data[:parameterized_text]
    @instance_text = ""

  end

  def populate(test_course)

    if !test_course.is_a? TestCourse
      puts "The populate method requires an object of the TestCourse class. Instead got test_course -> #{test_course.class}"
    end

    yield test_course, self

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
  attr_reader :modules
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
    @group_categories = []
    @modules = []
    

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

  def create_group_category(group_category)
    puts "Creating group category #{group_category["name"]} in #{@course.name}"

    gc = @course.group_categories.create!(name: group_category["name"], self_signup: group_category["self_signup"], self_signup_end_at: group_category["self_signup_end_at"])
    gc.configure_self_signup(true, false)
    gc.save!
    @group_categories << gc
  end

  def create_group(data)
    data[:context] = @course

    data["group_category"] = resolve_group_category_value(data["group_category"], self)

    group = Factories.group(data.except("users", "discussions"))
    group.join_level = "parent_context_auto_join"
    
    # Create any specified users for this group.
    if data["users"]
      data["users"].each {|user| 
        u = resolve_user_value(user, self)
        group.add_user(u, "accepted", false)
        # puts "Does #{group.name} allow self sign up? #{group.allow_self_signup? u }"
      }
    end

    group.name = data["name"]
    group.save!

   

    @groups << group

    if data["announcements"] # If the group has any announcements create those too.
      data["announcements"].each {|announcement|
      create_group_announcement(group, announcement)
    }
    end

    if data["discussions"] # If the group has any discussions create those too. 
      data["discussions"].each {|discussion|
      
      create_group_discussion(group, discussion)

    }
    end

    if data["pages"] # If the group has any pages, create those too.
      data["pages"].each {|page|
      p = group.wiki_pages.create!(title: page["title"], body: page["body"])
      p.save!

      if page["updates"] # If the page has updates, to build a version history. Make those changes too.
        page["updates"].each {|update|
        
        p.title = update["title"]
        p.body = update["body"]
        p.save!

      }

      end
      
    }

    end

  end

  def create_module(data)
    puts "Creating module #{data["name"]} in #{@course.name}"

    m = @course.context_modules.create!(data.except("content"))
    
    # Go through any content listed for this module and add it.
    data["content"].each {|item|

        _item = resolve_module_content(item["title"], self)

        item_type = resolve_item_type(_item)

        tag = m.add_item(id: _item.id, type: item_type)

        # Handle completion requirements.
        if item["completion_requirements"]
          m.completion_requirements << {id: tag.id, type: item["completion_requirements"]}
          m.save!
        end

    }

    m.save!
    @modules << m

    m

  end

  def resolve_module_content(title, course)
    pool = []

    pool.concat course.pages
    pool.concat course.assignments
    pool.concat course.quizzes
    pool.concat course.discussions

    # puts "Pool Items:"
    # pool.each {|item| puts "#{item.title}->#{item.class}" }
    
    return pool.select {|item| item.title == title}.first

  end

  def create_group_announcement(group, data)
    data["user"] = resolve_user_value(data["user"], self)
    announcement = group.announcements.create!(data.except("replies"))
    announcement.reload

    if data["replies"] # If there are any replies create those too
      data["replies"].each {|reply|
        create_discussion_reply(announcement, reply)
    }
    end

    announcement
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

  def create_page(data)
    puts "Creating page #{data["title"]} in #{@course.name}"

    data["user"] = resolve_user_value(data["user"], self)
    data[:title] = data["title"]
    data[:body] = data["body"]
    data[:user] = data["user"]
    data[:context] = @course

    page = wiki_page_model(data)

    puts "Created page #{page.title}"

    @pages << page
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
    

    data = data.merge({:assignment_group => @group})
    assignment = @course.assignments.create!(data.except("peer_reviews", "replies"))

    topic = @course.discussion_topics.create!(assignment: assignment, title: data["title"], message:data["description"] )
   

    puts "Created discussion topic? #{topic}"

    if data["replies"]
      
      data["replies"].each {|reply|
      email = reply["user"]
      reply["user"] = resolve_user_value(reply["user"], self)
      create_discussion_reply(topic, reply )

      submission = assignment.submit_homework(reply["user"], submission_type:"discussion_topic")
      
      if data["peer_reviews"] 
        if !email.include? "sammy"
          assessment_request = AssessmentRequest.create!(
            asset: submission,
            user: reply["user"],
            assessor: @logged_in_user,
            assessor_asset: assignment.submission_for_student(@logged_in_user)
          )
        end
      end

      

    }
    end

    if data["peer_reviews"]
      assignment.peer_review_count = data["peer_reviews"]["count"]
      assignment.automatic_peer_reviews = data["peer_reviews"]["automatic_peer_reviews"]
      assignment.anonymous_peer_reviews = data["peer_reviews"]["anonymous_peer_reviews"]
      assignment.intra_group_peer_reviews = data["peer_reviews"]["intra_group_peer_reviews"]
      assignment.update!(peer_reviews: true)
      assignment.save!

    end

     topic.publish

     @assignments << assignment

     assignment
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

  def resolve_group_category_value(group_category_value, course)

    if !group_category_value.is_a? String
      return group_category_value
    end

    return @group_categories.select {|gc| gc.name ==  group_category_value}.first

  end

  # A method that resolves user values loaded from the test data.
  # In the test data the value for a 'user' key may be one of the following:
  # 'instructor'/'teacher', 'student', 'logged_in_user'/'main_user' or the email of a particular user. 
  def resolve_user_value(user_value, course)

    if !user_value.is_a? String # Only process strings.
      return user_value
    end

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
      pool << course.logged_in_user

      return pool.select {|user| user.email == user_value}.first


    end

  end

  def resolve_item_type(item)

    case item
      when Assignment
        return "assignment"
      when WikiPage
        return "page"
      when Quizzes::Quiz
        return "quiz"
      when DiscussionTopic
        return 'discussion_topic'
      else
        puts "Unknown item type: #{item.class}"
    end

  end


end