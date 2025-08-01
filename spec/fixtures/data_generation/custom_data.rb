require_relative "../../factories/rubric_factory"
require_relative "../../factories/rubric_association_factory"

require_relative "./common"
require_relative "./utils"
require 'json'
require 'yaml'

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

  puts "Loading test data from container path: /usr/src/app/spec/fixtures/data_generation/test_data.yaml"
  
  test_data = YAML.load_file "/usr/src/app/spec/fixtures/data_generation/test_data.yaml"

  output = [] # Holds task instance output data

  courses = [] # Holds the generated course objects


  test_data["courses"].each {|course| 
    test_course = TestCourse.new({
      :course_name => course["name"],
      :course_code => course["code"],
      :teacher_name => course["instructor"]["name"],
      :teacher_email => course["instructor"]["email"],
      :teacher_password => course["instructor"]["password"],
      :student_name => course["main_user"]["name"],
      :student_email => course["main_user"]["email"],
      :student_password => course["main_user"]["password"]
    })
    courses << test_course
  }


  # Create resources for each course
  courses.each { |_course|
    course_data = test_data["courses"].select {|course| course["name"] == _course.course.name}
    course_data = course_data[0]

    # Fetch student test data and create enrolled students
    course_data["students"].each { |student|
      puts "Creating student #{student["name"]} in #{_course.course.name}"

      _course.create_classmate({
        :student_email => student["email"],
        :student_name => student["name"],
        :student_password => student["password"]
      })

    }

    # Fetch group category test data and create these in anticipation of creating groups
    if course_data["group_categories"]
      course_data["group_categories"].each {|group_category|
        _course.create_group_category(group_category)
      }
    end


    # Fetch group test data and create student groups
    course_data["groups"].each { |group|
      puts "Creating group '#{group["name"]}' in #{_course.course.name}"
       _course.create_group(group)
    }

    # Fetch page test data and create pages for the course
    course_data["pages"].each {|page|
      _course.create_page(page)
    }

    # Fetch discussion test data and create discussions for the course.
    course_data["discussions"].each { |discussion|
      puts "Creating discussion '#{discussion["title"]}' in  #{_course.course.name}"
      _course.create_discussion(discussion)
    }

    # Fetch announcement test data and create announcements
    course_data["announcements"].each {|announcement|

      puts "Creating announcement '#{announcement["title"]}' in #{_course.course.name}"

      _course.create_announcement(announcement)


    }

    # Fetch assignment test data and create assignments
    course_data["assignments"].each { |assignment|
      puts "Creating assignment #{assignment["title"]} in #{_course.course.name}"

      if assignment["submission_types"].include?("discussion_topic")
        _course.create_discussion_assignment(assignment)
        next
      end

      assignment_opts = _course.default_assignment_opts
      assignment_opts[:title] = assignment["title"]
      assignment_opts[:description] = assignment["description"]
      assignment_opts[:due_at] = assignment["due_at"]
      assignment_opts[:points_possible] = assignment["points_possible"]
      assignment_opts[:created_at] = assignment["created_at"]
      assignment_opts[:updated_at] = assignment["updated_at"]
      assignment_opts[:submission_types] = assignment["submission_types"]

      a = _course.create_assignment(assignment_opts)

      # Create a dummy rubric for the assignment
      rubric_opts = {
        :context => _course.course,
        :title => "Rubric for #{assignment["title"]}",
        :data => larger_rubric_data
      }
      rubric = rubric_model(rubric_opts)
      rubric.save!
      rubric.reload

      a.build_rubric_association(
        rubric: rubric,
        purpose: "grading",
        use_for_grading: true,
        context: _course.course
      )
      a.rubric_association.save!
      a.reload
      a.save!

      # Populate assignment submissions
      if assignment["submissions"] # If the assignment has submissions, create those too.
        assignment["submissions"].each { |submission|
          submission["user"] = _course.resolve_user_value(submission["user"], _course)
          _submission = a.submit_homework(submission["user"], submission.except("user"))

          if submission["peer_review"] # If there are peer review or instructor feedback comments create those too!
            submission["peer_review"].each { |review|
              review["author"] = _course.resolve_user_value(review["author"], _course)
              _submission.add_comment(comment: review["comment"], author: review["author"])
            }
          end

          _submission.save!

          # If there is instructor feedback for the submission let's create it now.
          if submission["feedback"]
            feedback = submission["feedback"]
            
            # Resolve the grader string from the test data to an actual user account
            feedback["grader"] = _course.resolve_user_value(feedback["grader"], _course)
            
            if feedback["grade"] # If a grade is specified, assign that grade to the submission  
              a.grade_student(submission["user"], grade: feedback["grade"], grader: feedback["grader"])
            end
            
            if feedback["comment"] # If there is a feedback comment add it to the submission
              _submission.add_comment(comment: feedback["comment"], author: feedback["grader"])
            end

          end
        }
      end

      if assignment["peer_reviews"] # If the assignment has peer reviews enabled, set those up.
        a.peer_review_count = assignment["peer_reviews"]["count"]
        a.automatic_peer_reviews = assignment["peer_reviews"]["automatic_peer_reviews"]
        a.update!(peer_reviews: true)
        a.save!
        result = a.assign_peer_reviews
      end

    }



    # Fetch quiz test data and create quizzes
    quiz_data = course_data["quizzes"]
    quiz_data.each { |quiz|
      
      puts "Creating quiz #{quiz["title"]} in #{_course.course.name}"

      if quiz["rubric"]
        @quiz = assignment_quiz([], {
          :course=> _course.course,
          :title => quiz["title"],
          :description => quiz["description"],
          :due_at => quiz["due_at"],
          :submission_types => ['online_quiz'],
          :workflow_state => quiz["workflow_state"]
        })

        

        
        # Create the rubric
        puts "Creating rubric #{quiz["rubric"]["title"]} for #{_course.course.name}"

        rubric_opts = quiz["rubric"].merge({
          :user=>_course.teacher,
          :context=>_course.course
        })
        
        rubric = rubric_model(rubric_opts)
        rubric.save!
        rubric.reload

        @assignment.build_rubric_association(
          rubric: rubric,
          purpose: "grading",
          use_for_grading: true,
          context: _course.course
        )
        @assignment.rubric_association.save!
        @assignment.reload
        @assignment.save!

                
        # Populate quiz questions
        questions = []
        quiz["questions"].each { |question|
          question[:regrade_option] = false
        }

        quiz["questions"].each { |question_data|
          question = @quiz.quiz_questions.create!(question_data: question_data)
          questions << question
        }
        @quiz.generate_quiz_data
        @quiz.due_at = quiz["due_at"]

        if quiz["allowed_attempts"]
          @quiz.allowed_attempts = quiz["allowed_attempts"]
          @quiz.save!
        end

        @quiz.save!
        @quiz.publish!

        _course.quizzes << @quiz

      else

        quiz_opts = quiz.except("rubric", "questions")

        q = _course.course.quizzes.create!(quiz_opts) # Create the actual quiz

        if quiz["allowed_attempts"]
          q.allowed_attempts = quiz["allowed_attempts"]
          q.save!
        end
        
        # Populate quiz questions
        questions = []
        
        quiz["questions"].each { |question|
          question[:regrade_option] = false
        }

        quiz["questions"].each { |question_data|
          question = q.quiz_questions.create!(question_data: question_data)
          questions << question
        }
        
        q.generate_quiz_data

        q.save!
        q.publish!

        _course.quizzes << q
      end    

      }

      # Fetch module test data and create the appropriate modules
      course_data["modules"].each{ |mod|

        _course.create_module(mod)

      }




  }

  courses[0]

end

def create_task_instances(test_course)

  tasks = []

  task = AgentTask.new({
    id: "9b30427c-2025-48db-baed-2cff271cd819",
    parameterized_text: "Task: In the course '[[Course]],' switch from your current group '[[Group 1]]' to the group '[[Group 2]]' within the 'Student Groups' group set."
  })

  task.populate(test_course) { |course, task|

      # find a group that the logged-in user is part of.
      group1 = course.groups.select {|group| (group.users.include? course.logged_in_user) && (!AgentTask.groups.include? group)}.first

      if group1.nil?
        puts "Cannot find group containing the logged in user for task #{task.id}"
        return
      end

      # find a group that the logged-in user in not a part of. 
      group2 = course.groups.select {|group| (!group.users.include? course.logged_in_user) && (!AgentTask.groups.include? group) }.first

      if group2.nil?
        puts "Cannot find group that does not contain the logged in user for task #{task.id}"
        return
      end

      # Register these groups as being used.
      AgentTask.groups << group1 
      AgentTask.groups << group2

      task.instance_variable_set(:@group1, group1)
      task.instance_variable_set(:@group2, group2)

      # Generate task instance text
      task.instance_text = task.parameterized_text.gsub(/\[\[Course\]\]/, course.course.name)
      task.instance_text = task.instance_text.gsub(/\[\[Group 1\]\]/, group1.name)
      task.instance_text = task.instance_text.gsub(/\[\[Group 2\]\]/, group2.name)

  }

  tasks << task

  task = AgentTask.new({
    id: "0b925826-6333-43cf-9eb0-4b5cb49a7e7d",
    parameterized_text: "Task: In the course '[[Course]]' use the Syllabus page to find the due date for the assignment titled '[[Assignment]]' and list the due date as displayed in the Course Summary section."
  })

  task.populate(test_course) { |course,task|

    assignment = course.assignments.select {|a| !AgentTask.assignments.include? a}.first

    if assignment.nil?
      puts "Cannot find assignment for task #{task.id}"
      return
    end

    # Register this assignment as being used.
    AgentTask.assignments << assignment

    task.instance_variable_set(:@assignment, assignment)

    # Generate task instance text
    task.instance_text = task.parameterized_text.gsub(/\[\[Course\]\]/, course.course.name)
    task.instance_text = task.instance_text.gsub(/\[\[Assignment\]\]/, assignment.title)

  }

  tasks << task

  task = AgentTask.new({
    id: "0be01f7a-0c6e-49c3-af20-52f9b97ef728",
    parameterized_text: "Task: View the feedback left by your instructor for the assignment '[[Assignment]]' in the course '[[Course]]', and add a comment saying 'Thank you for the feedback!' using the Feedback sidebar."
  })

  task.populate(test_course) { |course,task|

    assignment = course.assignments.select {|a| # Find an assignment
      # that has a submission by the logged in user.
      submission = a.submissions.find_by(user_id: course.logged_in_user.id)
      # where that submission has a comment provided by the course instructor. 
      comment_by_teacher = submission.submission_comments.select {|comment| comment.author == course.teacher}.first
      comment_by_teacher 
  }.first

    if (assignment.nil?) || (AgentTask.assignments.include? assignment)
      puts "Could not find assignment with submission and instructor feedback for task #{task.id}"
      return 
    end

    # Register this assignment as being used.
    AgentTask.assignments << assignment

    # Generate task instance text
    task.instance_text = task.parameterized_text.gsub(/\[\[Course\]\]/, course.course.name)
    task.instance_text = task.instance_text.gsub(/\[\[Assignment\]\]/, assignment.title)

  }

  tasks << task

  tasks.each {|t| 
    puts "Task: #{t.id}\n#{t.instance_text}"
  }


end



=begin
Run with:
docker-compose run --remove-orphans web bundle exec rails runner spec/fixtures/data_generation/custom_data.rb
=end

#explore
test_course = generate_test_environment
create_task_instances(test_course)
#puts Account.default.settings.pretty_inspect