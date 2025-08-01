# frozen_string_literal: true

#
# Copyright (C) 2013 - present Instructure, Inc.
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

require_relative "../common"
require_relative "../helpers/wiki_and_tiny_common"
require_relative "../helpers/public_courses_context"
require_relative "../helpers/files_common"
require_relative "../helpers/items_assign_to_tray"

describe "Wiki Pages" do
  include_context "in-process server selenium tests"
  include FilesCommon
  include WikiAndTinyCommon
  include ItemsAssignToTray

  context "Navigation" do
    def edit_page(edit_text)
      get "/courses/#{@course.id}/pages/Page1/edit"
      add_text_to_tiny(edit_text)
      expect_new_page_load { fj('button:contains("Save")').click }
    end

    before do
      account_model
      course_with_teacher_logged_in account: @account
    end

    it "navigates to pages tab with no front page set", priority: "1" do
      @course.wiki_pages.create!(title: "Page1")
      @course.wiki_pages.create!(title: "Page2")
      get "/courses/#{@course.id}"
      f(".pages").click
      expect(driver.current_url).to include("/courses/#{@course.id}/pages")
      expect(driver.current_url).not_to include("/courses/#{@course.id}/wiki")
      get "/courses/#{@course.id}/wiki"
      expect(driver.current_url).to include("/courses/#{@course.id}/pages")
      expect(driver.current_url).not_to include("/courses/#{@course.id}/wiki")
    end

    it "navigates to front page when set", priority: "1" do
      front = @course.wiki_pages.create!(title: "Front")
      front.set_as_front_page!
      front.save!
      get "/courses/#{@course.id}"
      f(".pages").click
      expect(driver.current_url).not_to include("/courses/#{@course.id}/pages")
      expect(driver.current_url).to include("/courses/#{@course.id}/wiki")
      expect(f("div.front-page")).to include_text "Front Page"
      get "/courses/#{@course.id}/pages"
      expect(driver.current_url).to include("/courses/#{@course.id}/pages")
      expect(driver.current_url).not_to include("/courses/#{@course.id}/wiki")
    end

    it "has correct front page UI elements when set as home page", priority: "1" do
      front = @course.wiki_pages.create!(title: "Front")
      front.set_as_front_page!
      @course.update_attribute :default_view, "wiki"
      get "/courses/#{@course.id}"
      wait_for_ajaximations
      # validations
      expect(f(".al-trigger")).to be_present
      expect(f(".course-title")).to include_text "Unnamed Course"
      content = f("#content")
      expect(content).not_to contain_css("span.front-page.label")
      expect(content).not_to contain_css("button.btn.btn-published")
      f(".al-trigger").click
      expect(content).not_to contain_css(".icon-trash")
      expect(f(".icon-clock")).to be_present
    end

    it "navigates to the wiki pages edit page from the show page" do
      wiki_page = @course.wiki_pages.create!(title: "Foo")
      edit_url = edit_course_wiki_page_url(@course, wiki_page)
      get course_wiki_page_path(@course, wiki_page)

      f(".edit-wiki").click

      keep_trying_until { expect(driver.current_url).to eq edit_url }
    end

    it "alerts a teacher when accessing a non-existent page", priority: "1" do
      get "/courses/#{@course.id}/pages/fake"
      expect_flash_message :info
    end

    it "displays error if no title on submit", :ignore_js_errors, priority: "1" do
      @course.wiki_pages.create!(title: "Page1")
      get "/courses/#{@course.id}/pages/Page1/edit"
      wiki_page_title_input.clear
      f("form.edit-form button.submit").click
      wait_for_ajaximations
      expect(f('[id*="TextInput-messages"]')).to include_text "Title must contain at least one letter or number"
    end

    it "displays error if no title on save and publish", :ignore_js_errors, priority: "1" do
      @course.wiki_pages.create!(title: "Page1", workflow_state: "unpublished")
      get "/courses/#{@course.id}/pages/Page1/edit"
      wiki_page_title_input.clear
      f(".save_and_publish").click
      wait_for_ajaximations
      expect(f('[id*="TextInput-messages"]')).to include_text "Title must contain at least one letter or number"
    end

    it "changes Save button state based on publish_at state" do
      Account.site_admin.enable_feature!(:scheduled_page_publication)
      @course.wiki_pages.create!(title: "Page1", workflow_state: "unpublished")
      get "/courses/#{@course.id}/pages/Page1/edit"
      publish_at_input.send_keys("invalid date")
      # blurs the input
      wiki_page_title_input.click
      expect(submit_button).to be_disabled

      publish_at_input.clear
      publish_at_input.send_keys(Time.zone.now)
      wiki_page_title_input.click
      expect(submit_button).not_to be_disabled
    end

    it "updates with changes made in other window", custom_timeout: 40.seconds, priority: "1" do
      @course.wiki_pages.create!(title: "Page1")
      edit_page("this is")
      driver.execute_script("window.open()")
      driver.switch_to.window(driver.window_handles.last)
      edit_page("test")
      driver.execute_script("window.close()")
      driver.switch_to.window(driver.window_handles.first)
      get "/courses/#{@course.id}/pages/Page1/edit"
      in_frame rce_page_body_ifr_id do
        expect(wiki_body_paragraph.text).to include "test"
      end
    end

    it "blocks linked page from redirecting parent page", priority: "2" do
      @course.wiki_pages.create!(title: "Garfield and Odie Food Preparation",
                                 body: '<a href="http://example.com/poc/" target="_blank" id="click_here_now">click_here</a>')
      get "/courses/#{@course.id}/pages/garfield-and-odie-food-preparation"
      expect(f("#click_here_now").attribute("rel")).to eq "noreferrer noopener"
    end

    it "does not mark valid links as invalid", priority: "2" do
      Setting.set("link_validator_poll_timeout", 100)
      Setting.set("link_validator_poll_timeout_initial", 100)

      @course.wiki_pages.create!(title: "Page1", body: "http://www.instructure.com/")
      get "/courses/#{@course.id}/link_validator"
      fj('button:contains("Start Link Validation")').click
      run_jobs
      wait_for_ajaximations
      expect(f("#link_validator")).to contain_jqcss('div:contains("No broken links found")')
    end
  end

  context "Index Page as a teacher" do
    before do
      account_model
      course_with_teacher_logged_in
    end

    context "infinite scrolling" do
      before do
        90.times do |i|
          @course.wiki_pages.create!(title: "Page#{i}")
        end
      end

      def wait_for_index_page_load
        wait_for(method: nil, timeout: 5) { f(".paginatedLoadingIndicator").attribute("style").include?("display: none") }
        wait_for_animations
      end

      context "top_navigation_placement feature flag is enabled" do
        before do
          Account.default.enable_feature!(:top_navigation_placement)
        end

        it "can scroll down to bottom of page to load more pages" do
          get "/courses/#{@course.id}/pages"
          wait_for_index_page_load
          expect(ff(".wiki-page-link").length).to eq 60

          scroll_page_to_bottom
          wait_for_index_page_load
          expect(ff(".wiki-page-link").length).to eq 90
        end

        it "can scroll and more pages after refreshing the page" do
          get "/courses/#{@course.id}/pages"
          refresh_page
          wait_for_index_page_load
          expect(ff(".wiki-page-link").length).to eq 60
          scroll_page_to_bottom
          wait_for_index_page_load
          expect(ff(".wiki-page-link").length).to eq 90
        end
      end

      context "top_navigation_placement feature flag is disabled" do
        before do
          Account.default.disable_feature!(:top_navigation_placement)
        end

        it "can scroll down to bottom of page to load more pages" do
          get "/courses/#{@course.id}/pages"
          wait_for_index_page_load
          expect(ff(".wiki-page-link").length).to eq 60
          scroll_page_to_bottom
          wait_for_index_page_load
          expect(ff(".wiki-page-link").length).to eq 90
        end

        it "can scroll and more pages after refreshing the page" do
          get "/courses/#{@course.id}/pages"
          refresh_page
          wait_for_index_page_load
          expect(ff(".wiki-page-link").length).to eq 60
          scroll_page_to_bottom
          wait_for_index_page_load
          expect(ff(".wiki-page-link").length).to eq 90
        end
      end
    end

    it "edits page title from pages index", priority: "1" do
      @course.wiki_pages.create!(title: "B-Team")
      get "/courses/#{@course.id}/pages"
      f("tbody .al-trigger").click
      f(".edit-menu-item").click
      expect(f('[data-testid="wikiTitleEditModal"] input').attribute(:value)).to include("B-Team")
      f('[data-testid="wikiTitleEditModal"] input').clear
      f('[data-testid="wikiTitleEditModal"] input').send_keys("A-Team")
      fj('button:contains("Save")').click
      expect(f(".collectionViewItems")).to include_text("A-Team")
    end

    it "displays a warning alert when accessing a deleted page", priority: "1" do
      @course.wiki_pages.create!(title: "deleted")
      get "/courses/#{@course.id}/pages"
      f("tbody .al-trigger").click
      f(".delete-menu-item").click
      fj('button:contains("Delete")').click
      wait_for_ajaximations
      get "/courses/#{@course.id}/pages/deleted"
      expect_flash_message :info
    end

    it "shows notification once after deleting a page" do
      page = @course.wiki_pages.create!(title: "hello")
      get "/courses/#{@course.id}/pages/#{page.url}"
      f(".page-toolbar .al-trigger").click
      f(".delete_page").click
      expect_new_page_load { fj('button:contains("Delete")').click }
      expect_flash_message :success, 'The page "hello" has been deleted.'
      get "/courses/#{@course.id}/pages"
      expect(f("#flash_message_holder").property("innerHTML")).to eq ""
    end

    it "keeps the calendar icon after hover and moving away" do
      Account.site_admin.enable_feature!(:scheduled_page_publication)
      @course.wiki_pages.create!(title: "hello", workflow_state: "unpublished", editing_roles: "teachers", publish_at: 3.days.from_now)
      get "/courses/#{@course.id}/pages/"

      element_selector = ".icon-calendar-month"
      expect(element_exists?(element_selector)).to be_truthy
      hover(f(element_selector))

      driver.action.move_by(10, 10).perform
      expect(element_exists?(element_selector)).to be_truthy
    end

    context "Assign To differentiation tags" do
      before do
        @course.account.enable_feature! :assign_to_differentiation_tags
        @course.account.tap do |a|
          a.settings[:allow_assign_to_differentiation_tags] = { value: true }
          a.save!
        end

        @differentiation_tag_category = @course.group_categories.create!(name: "Differentiation Tag Category", non_collaborative: true)
        @diff_tag1 = @course.groups.create!(name: "Differentiation Tag 1", group_category: @differentiation_tag_category, non_collaborative: true)
        @diff_tag2 = @course.groups.create!(name: "Differentiation Tag 2", group_category: @differentiation_tag_category, non_collaborative: true)
      end

      it "can assign wiki-pages to differentiation tags" do
        @course.wiki_pages.create!(title: "B-Team")
        get "/courses/#{@course.id}/pages"
        f("tbody .al-trigger").click
        fj("[role=menuitem]:contains('Assign To...')").click
        f(add_assign_to_card_selector).click
        assignee_selector = ff("[data-testid='assignee_selector']")[1]
        assignee_selector.send_keys("Differentiation Tag 1")
        assignee_selector.send_keys(:enter)
        save_button.click

        # Reopen tray and verify that it saved
        f("tbody .al-trigger").click
        fj("[role=menuitem]:contains('Assign To...')").click
        expect(assign_to_in_tray("Remove #{@diff_tag1.name}")[0]).to be_displayed
      end
    end
  end

  context "Index Page as a student" do
    before do
      course_with_student_logged_in
    end

    it "displays a warning alert to a student when accessing a deleted page", priority: "1" do
      page = @course.wiki_pages.create!(title: "delete_deux")
      # sets the workflow_state = deleted to act as a deleted page
      page.workflow_state = "deleted"
      page.save!
      get "/courses/#{@course.id}/pages/delete_deux"
      expect_flash_message :warning
    end

    it "displays a warning alert when accessing a non-existant page", priority: "1" do
      get "/courses/#{@course.id}/pages/non-existant"
      expect_flash_message :warning
    end
  end

  context "Show Page" do
    before do
      account_model
      course_with_student_logged_in account: @account
    end

    it "locks page based on module date", priority: "1" do
      locked = @course.wiki_pages.create! title: "locked"
      mod2 = @course.context_modules.create! name: "mod2", unlock_at: 1.day.from_now
      mod2.add_item id: locked.id, type: "wiki_page"
      mod2.save!

      get "/courses/#{@course.id}/pages/locked"
      wait_for_ajaximations
      # validation
      lock_explanation = f(".lock_explanation").text
      expect(lock_explanation).to include "This page is part of the module #{mod2.name} and hasn't been unlocked yet."
      expect(lock_explanation).to include "The following requirements need to be completed before this page will be unlocked:"
    end

    it "locks page based on module progression", priority: "1" do
      foo = @course.wiki_pages.create! title: "foo"
      bar = @course.wiki_pages.create! title: "bar"
      mod = @course.context_modules.create! name: "the_mod", require_sequential_progress: true
      foo_item = mod.add_item id: foo.id, type: "wiki_page"
      bar_item = mod.add_item id: bar.id, type: "wiki_page"
      mod.completion_requirements = { foo_item.id => { type: "must_view" }, bar_item.id => { type: "must_view" } }
      mod.save!

      get "/courses/#{@course.id}/pages/bar"
      wait_for_ajaximations
      # validation
      lock_explanation = f(".lock_explanation").text
      expect(lock_explanation).to include "This page is part of the module the_mod and hasn't been unlocked yet"
      expect(lock_explanation).to match(/foo\s+must view the page/)
    end

    it "does not show the show all pages link if the pages tab is disabled" do
      @course.tab_configuration = [{ id: Course::TAB_PAGES, hidden: true }]
      @course.save!

      @course.wiki_pages.create! title: "foo"
      get "/courses/#{@course.id}/pages/foo"

      expect(f("#content")).not_to contain_css(".view_all_pages")
    end

    it "displays To-Do Date in user's time zone" do
      @user.time_zone = "Alaska"
      @user.save!
      Time.use_zone("UTC") do
        # Use a fixed time to avoid boundary issues (middle of the day, middle of the month)
        # Use a time with minutes to avoid formatting ambiguity (6:30pm vs 6pm)
        todo_date = Time.zone.parse("2024-07-15 18:30:00")
        @course.wiki_pages.create!(title: "todo", todo_date:)
        get "/courses/#{@course.id}/pages/todo"
        Time.use_zone("Alaska") do
          # The UI uses the date_at_time format which is "%b %-d at %l:%M%P"
          # Convert UTC time to Alaska time before formatting
          expected_date = todo_date.in_time_zone("Alaska").strftime("%b %-d at %l:%M%P").strip
          elm = find_by_test_id("friendly-date-time")
          expect(elm).to include_text "To-Do Date: #{expected_date}"
        end
      end
    end
  end

  context "Permissions" do
    before do
      course_with_teacher
    end

    it "displays public content to unregistered users", priority: "1" do
      Canvas::Plugin.register(:kaltura, nil, settings: { "partner_id" => 1, "subpartner_id" => 2, "kaltura_sis" => "1" })

      @course.is_public = true
      @course.workflow_state = "available"
      @course.save!

      title = "foo"
      @course.wiki_pages.create!(title:, body: "bar")

      get "/courses/#{@course.id}/pages/#{title}"
      expect(f("#wiki_page_show")).not_to be_nil
    end
  end

  context "menu tools" do
    before do
      course_with_teacher_logged_in
      @tool = Account.default.context_external_tools.new(name: "a", domain: "google.com", consumer_key: "12345", shared_secret: "secret")
      @tool.wiki_page_menu = { url: "http://www.example.com", text: "Export Wiki Page" }
      @tool.save!

      @course.wiki.set_front_page_url!("front-page")
      @wiki_page = @course.wiki.front_page
      @wiki_page.workflow_state = "active"
      @wiki_page.save!
    end

    it "shows tool launch links in the gear for items on the index" do
      get "/courses/#{@course.id}/pages"
      wait_for_ajaximations

      gear = f(".collectionViewItems tr .al-trigger")
      gear.click
      link = f(".collectionViewItems tr li a.menu_tool_link")
      expect(link).to be_displayed
      expect(link.text).to match_ignoring_whitespace(@tool.label_for(:wiki_page_menu))
      expect(link["href"]).to eq course_external_tool_url(@course, @tool) + "?launch_type=wiki_page_menu&pages[]=#{@wiki_page.id}"
    end

    it "shows tool launch links in the gear for items on the show page" do
      get "/courses/#{@course.id}/pages/#{@wiki_page.url}"
      wait_for_ajaximations

      gear = f("#wiki_page_show .al-trigger")
      gear.click
      link = f("#wiki_page_show .al-options li a.menu_tool_link")
      expect(link).to be_displayed
      expect(link.text).to match_ignoring_whitespace(@tool.label_for(:wiki_page_menu))
      expect(link["href"]).to eq course_external_tool_url(@course, @tool) + "?launch_type=wiki_page_menu&pages[]=#{@wiki_page.id}"
    end
  end

  context "when a public course is accessed" do
    include_context "public course as a logged out user"

    it "displays wiki content", priority: "1" do
      @coures = public_course
      title = "foo"
      public_course.wiki_pages.create!(title:, body: "bar")

      get "/courses/#{public_course.id}/wiki/#{title}"
      expect(f(".user_content")).not_to be_nil
    end
  end

  context "embed video in a Page" do
    before do
      course_with_teacher_logged_in account: @account, active_all: true
      @course.wiki_pages.create!(title: "Page1")
    end

    it "embeds vimeo video in the page", priority: "1" do
      get "/courses/#{@course.id}/pages/Page1/edit"
      switch_editor_views
      switch_to_raw_html_editor
      html_contents = <<~HTML
        <p>
          <iframe style="width: 640px; height: 480px;"
                  title="Instructure - About Us"
                  src="https://player.vimeo.com/video/51408381"
                  width="300"
                  height="150"
                  allowfullscreen="allowfullscreen"
                  webkitallowfullscreen="webkitallowfullscreen"
                  mozallowfullscreen="mozallowfullscreen">
          </iframe>
        </p>
      HTML
      element = f("#wiki_page_body")
      element.send_keys(html_contents)
      wait_for_new_page_load { f(".btn-primary").click }
      expect(f("iframe")).to be_present
    end
  end
end
