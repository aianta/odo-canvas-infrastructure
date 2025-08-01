# frozen_string_literal: true

#
# Copyright (C) 2012 - present Instructure, Inc.
#
# This file is part of Canvas.
#
# Canvas is free software: you can redistribute it and/or modify it under
# the terms of the GNU Affero General Public License as published by the Free
# Software Foundation, version 3 of the License.
#
# Canvas is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
# details.
#
# You should have received a copy of the GNU Affero General Public License along
# with this program. If not, see <http://www.gnu.org/licenses/>.

require_relative "../helpers/assignments_common"
require_relative "../helpers/discussions_common"
require_relative "../helpers/files_common"
require_relative "../helpers/wiki_and_tiny_common"
require_relative "../rcs/pages/rce_next_page"

describe "discussion assignments" do
  include_context "in-process server selenium tests"
  include DiscussionsCommon
  include FilesCommon
  include AssignmentsCommon
  include WikiAndTinyCommon
  include RCENextPage

  before do
    stub_rcs_config
    @domain_root_account = Account.default
    course_with_teacher_logged_in
  end

  context "created with 'more options'" do
    it "redirects to the discussion new page and maintain parameters", priority: "1" do
      ag = @course.assignment_groups.create!(name: "Stuff")
      get "/courses/#{@course.id}/assignments"
      expect_new_page_load { build_assignment_with_type("Discussion", assignment_group_id: ag.id, name: "More options created discussion", points: "30", more_options: true) }
      # check the content of the discussion page for our set point value and name and the URL to make sure were in /discussions
      expect(driver.current_url).to include("discussion_topics/new?#{ag.id}&due_at=&points_possible=30&post_to_sis=false&title=More%20options%20created%20discussion")
      expect(f("#discussion-title")).to have_value "More options created discussion"
      expect(f("#discussion_topic_assignment_points_possible")).to have_value "30"
    end
  end

  context "edited from the index page" do
    it "updates discussion when updated", priority: "2" do
      assign = @course.assignments.create!(name: "Discuss!", points_possible: "5", submission_types: "discussion_topic")
      get "/courses/#{@course.id}/assignments"
      edit_assignment(assign.id, name: "Rediscuss!", submit: true)
      expect(assign.reload.discussion_topic.title).to eq "Rediscuss!"
    end
  end

  context "edited with 'more options'" do
    it "redirects to the discussion edit page and maintain parameters", priority: "2" do
      assign = @course.assignments.create!(name: "Discuss!", points_possible: "5", submission_types: "discussion_topic")
      get "/courses/#{@course.id}/assignments"
      expect_new_page_load { edit_assignment(assign.id, name: "Rediscuss!", points: "10", more_options: true) }
      expect(f("#discussion-title")).to have_value "Rediscuss!"
      expect(f("#discussion_topic_assignment_points_possible")).to have_value "10"
    end
  end

  context "insert content using RCE" do
    it "inserts file using rce in a discussion", priority: "1" do
      discussion_title = "New Discussion"
      topic = create_discussion(discussion_title, "threaded")
      get "/courses/#{@course.id}/discussion_topics/#{topic.id}/edit"
      add_file_to_rce_next
      submit_form(".form-actions")
      wait_for_ajax_requests
      expect(fln("text_file.txt")).to be_displayed
    end
  end

  context "created by different users" do
    it "lists identical authors after a user merge", priority: "2" do
      @student_a = User.create!(name: "Student A")
      @student_b = User.create!(name: "Student B")
      discussion_a = @course.discussion_topics.create!(user: @student_a, title: "title a", message: "from student a")
      discussion_b = @course.discussion_topics.create!(user: @student_b, title: "title b", message: "from student b")
      discussion_b.discussion_entries.create!(user: @student_a, message: "reply from student a")
      discussion_a.discussion_entries.create!(user: @student_b, message: "reply from student b")
      UserMerge.from(@student_a).into(@student_b)
      @student_a.reload
      @student_b.reload
      get "/courses/#{@course.id}/discussion_topics/#{discussion_a.id}"
      expect(f('[data-testid="student_context_card_trigger_container_author"]').text).to eq "Student B"
      get "/courses/#{@course.id}/discussion_topics/#{discussion_b.id}"
      expect(f('[data-testid="student_context_card_trigger_container_author"]').text).to eq "Student B"
    end
  end
end
