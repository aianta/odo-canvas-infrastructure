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

    # Fetch group test data and create student groups
    course_data["groups"].each { |group|
      puts "Creating group '#{group["name"]}' in #{_course.course.name}"
       _course.create_group(group)
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
      puts "Creating assignment #{assignment["name"]} in #{_course.course.name}"

      if assignment["submission_types"].include?("discussion_topic")
        _course.create_discussion_assignment(assignment)
        next
      end

      assignment_opts = _course.default_assignment_opts
      assignment_opts[:title] = assignment["name"]
      assignment_opts[:description] = assignment["description"]
      assignment_opts[:due_at] = assignment["due_at"]
      assignment_opts[:points_possible] = assignment["points_possible"]
      assignment_opts[:created_at] = assignment["created_at"]
      assignment_opts[:updated_at] = assignment["updated_at"]
      assignment_opts[:submission_types] = assignment["submission_types"]

      a = _course.create_assignment(assignment_opts)

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

        @quiz.save!
        @quiz.publish!

      else

        quiz_opts = quiz.except("rubric", "questions")

        q = _course.course.quizzes.create!(quiz_opts) # Create the actual quiz
        
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

      end

      

    


      

    


    

      }






  }

end





=begin
Run with:
docker-compose run --remove-orphans web bundle exec rails runner spec/fixtures/data_generation/custom_data.rb
=end

#explore
generate_test_environment
#puts Account.default.settings.pretty_inspect