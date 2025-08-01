# frozen_string_literal: true

#
# Copyright (C) 2011 - present Instructure, Inc.
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

full_path_glob = "(/*full_path)"

# allow plugins to prepend routes
Rails.root.glob("{gems,vendor}/plugins/*/config/pre_routes.rb") do |pre_routes|
  load pre_routes
end

CanvasRails::Application.routes.draw do
  post "/api/graphql", to: "graphql#execute"
  get "graphiql", to: "graphql#graphiql"

  get "acceptable_use_policy", to: "accounts#acceptable_use_policy"

  resources :submissions, only: [] do
    resources :submission_comments, path: :comments, only: :index, defaults: { format: :pdf }
    resources :docviewer_audit_events, only: [:create], constraints: { format: :json }
  end
  resources :submission_comments, only: [:update, :destroy]

  resources :epub_exports, only: [:index]

  get "inbox" => "context#inbox"
  get "oauth/redirect_proxy" => "oauth_proxy#redirect_proxy"

  get "conversations/unread" => "conversations#index", :as => :conversations_unread, :redirect_scope => "unread"
  get "conversations/starred" => "conversations#index", :as => :conversations_starred, :redirect_scope => "starred"
  get "conversations/sent" => "conversations#index", :as => :conversations_sent, :redirect_scope => "sent"
  get "conversations/archived" => "conversations#index", :as => :conversations_archived, :redirect_scope => "archived"
  get "conversations/find_recipients" => "search#recipients"

  get "search/recipients" => "search#recipients"
  post "conversations/mark_all_as_read" => "conversations#mark_all_as_read"
  get "conversations/batches" => "conversations#batches", :as => :conversation_batches
  resources :conversations, only: %i[index show update create destroy] do
    post :add_recipients
    post :add_message
    post :remove_messages
  end

  post "/external_auth_observers/redirect_login" => "login/external_auth_observers#redirect_login", :as => :external_auth_validation

  # So, this will look like:
  # http://instructure.com/register/5R32s9iqwLK75Jbbj0
  match "register/:nonce" => "communication_channels#confirm", :as => :registration_confirmation, :via => [:get, :post]
  # deprecated
  get "pseudonyms/:id/register/:nonce" => "communication_channels#confirm", :as => :registration_confirmation_deprecated
  post "confirmations/:user_id/re_send(/:id)" => "communication_channels#re_send_confirmation", :as => :re_send_confirmation, :id => nil
  get "confirmations/:user_id/limit_reached(/:id)" => "communication_channels#confirmation_limit_reached", :as => :confirmation_limit_reached, :id => nil
  match "forgot_password" => "pseudonyms#forgot_password", :as => :forgot_password, :via => [:get, :post]
  get "pseudonyms/:pseudonym_id/change_password/:nonce" => "pseudonyms#confirm_change_password", :as => :confirm_change_password
  post "pseudonyms/:pseudonym_id/change_password/:nonce" => "pseudonyms#change_password", :as => :change_password

  # callback urls for oauth authorization processes
  get "oauth" => "users#oauth"
  get "oauth_success" => "users#oauth_success"

  get "mr/:id" => "info#message_redirect", :as => :message_redirect
  get "help_links" => "info#help_links"

  # This is a debug route that makes working on error pages easier
  get "test_error" => "info#test_error" unless Rails.env.production?
  get "live_events/heartbeat" => "info#live_events_heartbeat" unless Rails.env.production?

  concern :question_banks do
    resources :question_banks do
      post :bookmark
      post :reorder
      get :questions
      post :move_questions
      resources :assessment_questions
    end
  end

  concern :groups do
    resources :groups, except: :edit
    resources :group_categories, only: %i[create update destroy]
    get "group_unassigned_members" => "groups#unassigned_members"
  end

  resources :group_categories do
    member do
      post "clone_with_name"
    end
  end

  concern :files do
    get "files/folder#{full_path_glob}" => "files#react_files", :format => false, :defaults => { format: "html" }
    get "files/search" => "files#react_files", :format => false, :defaults => { format: "html" }
    resources :files, except: [:new] do
      get "download" => "files#show", :download => "1"
      get "download.:type" => "files#show", :as => :typed_download, :download => "1"
      get "preview" => "files#show", :preview => "1"
      post "inline_view" => "files#show", :inline => "1"
      get "file_preview" => "file_previews#show"
      collection do
        get :quota
        post :reorder
      end
      get "*file_path" => "files#show_relative", :as => :relative_path, :file_path => /.+/ # needs to stay below react_files route
    end
  end

  concern :file_images do
    get "images" => "files#images"
  end

  concern :relative_files do
    get "file_contents/*file_path" => "files#show_relative", :as => :relative_file_path, :file_path => /.+/
  end

  concern :folders do
    resources :folders
  end

  concern :media do
    get "media_download" => "users#media_download"
  end

  concern :users do
    get "users" => "context#roster"
    get "user_services" => "context#roster_user_services"
    get "users/:user_id/usage" => "context#roster_user_usage", :as => :user_usage
    get "users/:id" => "context#roster_user", :as => :user
  end

  concern :announcements do
    resources :announcements
    post "announcements/external_feeds" => "announcements#create_external_feed"
    delete "announcements/external_feeds/:id" => "announcements#destroy_external_feed", :as => :announcements_external_feed
  end

  concern :discussions do
    resources :discussion_topics, only: %i[index new show edit destroy] do
      member do
        get "insights" => "discussion_topics#insights", :as => :insights
      end
    end
    get "discussion_topics/:id/*extras" => "discussion_topics#show", :as => :map, :extras => /.+/
    resources :discussion_entries
  end

  concern :pages do
    resources :wiki_pages, path: :pages, except: %i[update destroy new], constraints: { id: %r{[^/]+} } do
      get "revisions" => "wiki_pages#revisions", :as => :revisions
      put "create_block_editor" => "wiki_pages#create_block_editor", :as => :create_block_editor
    end

    get "wiki" => "wiki_pages#front_page", :as => :wiki
    get "wiki/:id" => "wiki_pages#show_redirect", :id => %r{[^/]+}
    get "wiki/:id/revisions" => "wiki_pages#revisions_redirect", :id => %r{[^/]+}
    get "wiki/:id/revisions/:revision_id" => "wiki_pages#revisions_redirect", :id => %r{[^/]+}
    get "new_page" => "wiki_pages#new", :as => :new_page
  end

  concern :conferences do
    resources :conferences do
      match :join, via: [:get, :post]
      match :close, via: [:get, :post]
      get :recording
      delete :recording, to: "conferences#delete_recording", as: :delete_recording
      get :settings
    end
  end

  get "/courses/:course_id/gradebook2", to: redirect("/courses/%{course_id}/gradebook")

  # There are a lot of resources that are all scoped to the course level
  # (assignments, files, wiki pages, user lists, forums, etc.).  Many of
  # these resources also apply to groups and individual users.  We call
  # courses, users, groups, or even accounts in this setting, "contexts".
  # There are some helper methods like the before_filter :get_context in application_controller
  # and the application_helper method :context_url to make retrieving
  # these contexts, and also generating context-specific urls, easier.
  resources :courses do
    # DEPRECATED
    get "self_enrollment/:self_enrollment" => "courses#self_enrollment", :as => :self_enrollment
    post "self_unenrollment/:self_unenrollment" => "courses#self_unenrollment", :as => :self_unenrollment
    post :unconclude
    get :students
    get "observer_pairing_codes.csv", action: :observer_pairing_codes_csv, as: "observer_pairing_codes"
    post :enrollment_invitation
    # this needs to come before the users concern, or users/:id will preempt it
    get "users/prior" => "context#prior_users", :as => :prior_users
    concerns :users
    get :statistics
    delete "unenroll/:id" => "courses#unenroll_user", :as => :unenroll
    post "move_enrollment/:id" => "courses#move_enrollment", :as => :move_enrollment
    delete "unenroll/:id.:format" => "courses#unenroll_user", :as => :formatted_unenroll
    post "limit_user_grading/:id" => "courses#limit_user", :as => :limit_user_grading
    delete "conclude_user/:id" => "courses#conclude_user", :as => :conclude_user_enrollment
    post "unconclude_user/:id" => "courses#unconclude_user", :as => :unconclude_user_enrollment
    resources :sections, except: %i[index edit new] do
      get "crosslist/confirm/:new_course_id" => "sections#crosslist_check", :as => :confirm_crosslist
      get "user_count" => "sections#user_count", :on => :collection, :as => :user_count
      post :crosslist
      delete "crosslist" => "sections#uncrosslist", :as => :uncrosslist
    end

    get "undelete" => "context#undelete_index", :as => :undelete_items
    post "undelete/:asset_string" => "context#undelete_item", :as => :undelete_item

    get "settings#{full_path_glob}", action: :settings
    get :settings
    get "details" => "courses#settings"
    post :re_send_invitations
    post :enroll_users
    post :link_enrollment
    post :update_nav
    resource :gradebook do
      get "submissions_upload/:assignment_id" => "gradebooks#show_submissions_upload", :as => :show_submissions_upload
      post "submissions_upload/:assignment_id" => "gradebooks#submissions_zip_upload", :as => :submissions_upload

      collection do
        get :change_gradebook_version
        get :blank_submission
        get :final_grade_overrides
        get :speed_grader
        post :speed_grader_settings
        get :history
        post :update_submission
        post :change_gradebook_column_size
        post :save_gradebook_column_order
        get :user_ids
        get :grading_period_assignments
      end
    end

    resource :gradebook_csv, only: [:create]

    # DEPRECATED old migration emails pointed the user to this url, leave so the controller can redirect
    get "imports/list" => "content_imports#index", :as => :import_list
    # DEPRECATED
    get "imports" => "content_imports#intro"
    resource :gradebook_upload do
      get "data" => "gradebook_uploads#data"
    end
    get "grades" => "gradebooks#grade_summary", :id => nil
    get "grading_rubrics" => "gradebooks#grading_rubrics"
    get "grades/:id" => "gradebooks#grade_summary", :as => :student_grades
    post "save_assignment_order" => "gradebooks#save_assignment_order", :as => :save_assignment_order
    concerns :announcements
    get "calendar" => "calendars#show"
    get :locks
    concerns :discussions
    resources :assignments do
      get "moderate" => "assignments#show_moderate"

      get "anonymous_submissions/:anonymous_id",
          to: "submissions/anonymous_previews#show",
          constraints: lambda { |request|
                         request.query_parameters.key?(:preview) && request.format == :html
                       }

      get "anonymous_submissions/:anonymous_id",
          to: "submissions/anonymous_downloads#show",
          constraints: lambda { |request|
                         request.query_parameters.key?(:download)
                       }

      get "anonymous_submissions/:anonymous_id", to: "anonymous_submissions#show", as: :anonymous_submission

      get "submissions/:id",
          to: "submissions/previews#show",
          constraints: lambda { |request|
                         request.query_parameters.key?(:preview) && request.format == :html
                       }

      get "submissions/:id",
          to: "submissions/downloads#show",
          constraints: lambda { |request|
                         request.query_parameters.key?(:download)
                       }

      put "anonymous_submissions/:anonymous_id", to: "anonymous_submissions#update"
      put "anonymous_submissions/:anonymous_id/reassign", to: "anonymous_submissions#redo_submission"
      resources :submissions do
        get "originality_report/:asset_string" => "submissions#originality_report", :as => :originality_report
        post "turnitin/resubmit" => "submissions#resubmit_to_turnitin", :as => :resubmit_to_turnitin
        get "turnitin/:asset_string" => "submissions#turnitin_report", :as => :turnitin_report
        post "vericite/resubmit" => "submissions#resubmit_to_vericite", :as => :resubmit_to_vericite
        get "vericite/:asset_string" => "submissions#vericite_report", :as => :vericite_report
        get "audit_events" => "submissions#audit_events", :as => :audit_events
        put "reassign" => "submissions#redo_submission", :as => :reassign
      end

      get "anonymous_submissions/:anonymous_id/originality_report/:asset_string",
          to: "anonymous_submissions#originality_report",
          as: :anonymous_submission_originality_report
      post "anonymous_submissions/:anonymous_id/turnitin/resubmit",
           to: "anonymous_submissions#resubmit_to_turnitin",
           as: :anonymous_submission_resubmit_to_turnitin
      get "anonymous_submissions/:anonymous_id/turnitin/:asset_string",
          to: "anonymous_submissions#turnitin_report",
          as: :anonymous_submission_turnitin_report
      post "anonymous_submissions/:anonymous_id/vericite/resubmit",
           to: "anonymous_submissions#resubmit_to_vericite",
           as: :anonymous_submission_resubmit_to_vericite
      get "anonymous_submissions/:anonymous_id/vericite/:asset_string",
          to: "anonymous_submissions#vericite_report",
          as: :anonymous_submission_vericite_report

      get :rubric
      resource :rubric_association, path: :rubric do
        resources :rubric_assessments, path: :assessments do
          collection do
            resources :rubric_assessment_imports, path: :imports, only: %i[create show], defaults: { format: :json }
            get :export
          end
        end
      end

      get :peer_reviews
      post :assign_peer_reviews
      delete "peer_reviews/:id" => "assignments#delete_peer_review", :as => :delete_peer_review
      post "peer_reviews/:id" => "assignments#remind_peer_review", :as => :remind_peer_review
      post "peer_reviews/users/:reviewer_id" => "assignments#assign_peer_review", :as => :assign_peer_review
      put "mute" => "assignments#toggle_mute"

      collection do
        get :syllabus
        get :submissions
      end

      get "lti/resource/:resource_link_id",
          controller: "lti/message",
          action: "resource",
          as: :resource_link_id

      get :tool_launch
    end

    resources :grading_standards, only: %i[index create update destroy]

    resources :assignment_groups do
      post "reorder" => "assignment_groups#reorder_assignments", :as => :reorder_assignments
      collection do
        post :reorder
      end
    end

    get "external_tools/sessionless_launch" => "external_tools#sessionless_launch"
    resources :external_tools do
      match :resource_selection, via: [:get, :post]
      get :homework_submission
      get :finished
      collection do
        get :retrieve
      end
    end

    get "lti/resource/:resource_link_id",
        controller: "lti/message",
        action: "resource",
        as: :resource_link_id
    get "lti/basic_lti_launch_request/:message_handler_id",
        controller: "lti/message",
        action: "basic_lti_launch_request",
        as: :basic_lti_launch_request
    post "lti/tool_proxy_registration", controller: "lti/message", action: "registration", as: :tool_proxy_registration
    get "lti/tool_proxy_reregistration/:tool_proxy_id",
        controller: "lti/message",
        action: "reregistration",
        as: :tool_proxy_reregistration
    get "lti/registration_return",
        controller: "lti/message",
        action: "registration_return",
        as: :registration_return

    resources :submissions
    resources :calendar_events

    concerns :files, :file_images, :relative_files, :folders
    concerns :groups
    concerns :pages
    concerns :conferences
    concerns :question_banks

    resources :item_banks, controller: "item_banks", only: [] do
      collection do
        get "/", to: "item_banks#show"
        get "*path", to: "item_banks#show"
      end
    end

    post "quizzes/publish"   => "quizzes/quizzes#publish"
    post "quizzes/unpublish" => "quizzes/quizzes#unpublish"

    post "assignments/publish/quiz"   => "assignments#publish_quizzes"
    post "assignments/unpublish/quiz" => "assignments#unpublish_quizzes"

    post "quizzes/new" => "quizzes/quizzes#new" # use POST instead of GET (not idempotent)
    resources :quizzes, controller: "quizzes/quizzes", except: :new do
      get :managed_quiz_data
      get :submission_versions
      get :history
      get :statistics
      get :read_only
      get :submission_html

      resources :quiz_submissions, controller: "quizzes/quiz_submissions", path: :submissions do
        collection do
          put :backup
          post :backup
        end
        member do
          get :record_answer
          post :record_answer
        end
        resources :events, controller: "quizzes/quiz_submission_events", path: "log#{full_path_glob}"
      end

      post "extensions/:user_id" => "quizzes/quiz_submissions#extensions", :as => :extensions
      resources :quiz_questions, controller: "quizzes/quiz_questions", path: :questions, only: %i[create update destroy show]
      resources :quiz_groups, controller: "quizzes/quiz_groups", path: :groups, only: %i[create update destroy] do
        member do
          post :reorder
        end
      end

      match "take" => "quizzes/quizzes#show", :take => "1", :via => [:get, :post]
      get "take/questions/:question_id" => "quizzes/quizzes#show", :as => :question, :take => "1"
      get :moderate
      get :lockdown_browser_required
    end

    resources :collaborations
    get "lti_collaborations" => "collaborations#lti_index"
    get "lti_collaborations/*all" => "collaborations#lti_index"
    resources :gradebook_uploads
    resources :rubrics
    post "rubrics/llm_criteria", controller: :rubrics, action: :llm_criteria
    resources :rubric_associations do
      post "remind/:assessment_request_id" => "rubric_assessments#remind", :as => :remind_assessee
      resources :rubric_assessments, path: "assessments"
    end

    get "outcomes/users/:user_id" => "outcomes#user_outcome_results", :as => :user_outcomes_results
    resources :outcomes do
      get "alignments/:id" => "outcomes#alignment_redirect", :as => :alignment_redirect
      post "alignments" => "outcomes#align", :as => :align
      delete "alignments/:id" => "outcomes#remove_alignment", :as => :remove_alignment
      get "results" => "outcomes#outcome_results"
      get "results/:id" => "outcomes#outcome_result", :as => :result
      get :details
      collection do
        get :list
        post :add_outcome
      end
    end

    resources :outcome_groups, only: %i[create update destroy] do
      post :reorder
    end

    resources :context_modules, path: :modules do
      post "items" => "context_modules#add_item", :as => :add_item
      post "reorder" => "context_modules#reorder_items", :as => :reorder
      post "collapse" => "context_modules#toggle_collapse", :as => :toggle_collapse
      get "items_html" => "context_modules#items_html", :as => :context_modules_items_html
      get "module_html" => "context_modules#module_html", :as => :context_modules_module_html
      get "prerequisites/:code" => "context_modules#content_tag_prerequisites_needing_finishing", :as => :prerequisites_needing_finishing
      get "items/last" => "context_modules#module_redirect", :as => :last_redirect, :last => 1
      get "items/first" => "context_modules#module_redirect", :as => :first_redirect, :first => 1
      collection do
        post :reorder
        get :progressions
      end
    end

    get "blackout_dates" => "blackout_dates#index"
    get "course_pacing" => "course_paces#index"

    post "collapse_all_modules" => "context_modules#toggle_collapse_all"
    resources :content_exports, only: %i[create index destroy show]
    get "offline_web_exports" => "courses#offline_web_exports"
    post "start_offline_web_export" => "courses#start_offline_web_export"
    get "start_offline_web_export" => "courses#start_offline_web_export"
    get "modules/items/assignment_info" => "context_modules#content_tag_assignment_data", :as => :context_modules_assignment_info
    get "modules/items/estimated_duration_info" => "context_modules#content_tag_estimated_duration_data", :as => :context_modules_estimated_duration_info
    get "modules/items/master_course_info" => "context_modules#content_tag_master_course_data", :as => :context_modules_master_course_info
    get "modules/items/:id" => "context_modules#item_redirect", :as => :context_modules_item_redirect
    get "modules/items/:id/edit_mastery_paths" => "context_modules#item_redirect_mastery_paths"
    get "modules/items/:id/choose" => "context_modules#choose_mastery_path"
    get "modules/items/sequence/:id" => "context_modules#item_details", :as => :context_modules_item_details
    delete "modules/items/:id" => "context_modules#remove_item", :as => :context_modules_remove_item
    put "modules/items/:id" => "context_modules#update_item", :as => :context_modules_update_item
    get "confirm_action" => "courses#confirm_action"
    get :copy, as: :start_copy
    post "copy" => "courses#copy_course", :as => :copy_course
    concerns :media
    get "details/sis_publish" => "courses#sis_publish_status", :as => :sis_publish_status
    post "details/sis_publish" => "courses#publish_to_sis", :as => :publish_to_sis

    resources :user_lists, only: :create
    post "invite_users" => "users#invite_users", :as => :invite_users

    post "reset" => "courses#reset_content"
    resources :alerts
    get "student_view(/:redirect_to_referer)" => "courses#student_view"
    post "student_view(/:redirect_to_referer)" => "courses#student_view", :as => :student_view
    delete "student_view" => "courses#leave_student_view"
    delete "test_student" => "courses#reset_test_student"
    get "content_migrations" => "content_migrations#index"
    get "link_validator" => "courses#link_validator", :as => :link_validator
    get "youtube_migration" => "courses#youtube_migration", :as => :youtube_migration

    get "grading_schemes" => "grading_schemes_json#detail_list"
    get "grading_scheme_summaries" => "grading_schemes_json#summary_list"
    post "grading_schemes" => "grading_schemes_json#create"
    post "grading_schemes/:id/archive" => "grading_schemes_json#archive"
    post "grading_schemes/:id/unarchive" => "grading_schemes_json#unarchive"
    delete "grading_schemes/:id" => "grading_schemes_json#destroy"
    put "grading_schemes/:id" => "grading_schemes_json#update"
    get "grading_schemes/default" => "grading_schemes_json#show_default_grading_scheme"
    get "grading_schemes/:id" => "grading_schemes_json#show"

    get "canvas_career_validation" => "horizon#validate_course"
    post "canvas_career_conversion" => "horizon#convert_course"
    post "canvas_career_reversion" => "horizon#revert_course"

    resources :accessibility, only: [:index] do
      collection do
        resource :issues, only: [:create, :update], module: "accessibility"
        post "preview" => "accessibility/preview#create"
        get "preview" => "accessibility/preview#show"
      end
    end

    resources :accessibility_resource_scans, only: [:index]
  end

  get "quiz_statistics/:quiz_statistics_id/files/:file_id/download" => "files#show", :as => :quiz_statistics_download, :download => "1"

  resources :page_views, only: :update
  post "media_objects" => "media_objects#create_media_object", :as => :create_media_object
  get "media_objects/:id" => "media_objects#media_object_inline", :as => :media_object
  get "media_objects/:media_object_id/redirect" => "media_objects#media_object_redirect", :as => :media_object_redirect
  get "media_objects/:media_object_id/thumbnail" => "media_objects#media_object_thumbnail", :as => :media_object_thumbnail
  get "media_objects/:media_object_id/info" => "media_objects#show", :as => :media_object_info
  get "media_objects_iframe/:media_object_id" => "media_objects#iframe_media_player", :as => :media_object_iframe
  get "media_objects_iframe" => "media_objects#iframe_media_player", :as => :media_object_iframe_href
  get "media_objects/:media_object_id/media_tracks/:id" => "media_tracks#show", :as => :show_media_tracks
  post "media_objects/:media_object_id/media_tracks" => "media_tracks#create", :as => :create_media_tracks
  delete "media_objects/:media_object_id/media_tracks/:id" => "media_tracks#destroy", :as => :delete_media_tracks

  post "media_attachments" => "media_objects#create_media_object", :as => :create_media_attachment
  get "media_attachments/:attachment_id/thumbnail" => "media_objects#media_object_thumbnail", :as => :media_attachment_thumbnail
  get "media_attachments/:attachment_id/info" => "media_objects#show", :as => :media_attachment_info
  get "media_attachments_iframe/:attachment_id" => "media_objects#iframe_media_player", :as => :media_attachment_iframe
  get "media_attachments/:attachment_id/redirect" => "media_objects#media_object_redirect", :as => :media_attachment_redirect
  get "media_attachments/:attachment_id/media_tracks/:id" => "media_tracks#show", :as => :show_media_attachment_tracks
  post "media_attachments/:attachment_id/media_tracks" => "media_tracks#create", :as => :create_media_attachment_tracks
  delete "media_attachments/:attachment_id/media_tracks/:id" => "media_tracks#destroy", :as => :delete_media_attachment_tracks

  get "external_content/success/:service" => "external_content#success", :as => :external_content_success
  get "external_content/success/:service/:id" => "external_content#success", :as => :external_content_update
  get "external_content/retrieve/oembed" => "external_content#oembed_retrieve", :as => :external_content_oembed_retrieve
  get "external_content/cancel/:service" => "external_content#cancel", :as => :external_content_cancel

  get "deep_linking_cancel", controller: "lti/ims/deep_linking", action: :deep_linking_cancel, as: "deep_linking_cancel"

  resources :block_editors, only: :show

  %w[account course group].each do |context|
    prefix = "#{context}s/:#{context}_id"
    post "#{prefix}/deep_linking_response", controller: "lti/ims/deep_linking", action: :deep_linking_response, as: "#{context}_deep_linking_response"
  end

  %w[account course group user].each do |context|
    match "#{context.pluralize}/:#{context}_id/external_content/success/:service" => "external_content#success", :as => "#{context}_external_content_success", :via => [:get, :post]
    match "#{context.pluralize}/:#{context}_id/external_content/success/:service/:id" => "external_content#success", :as => "#{context}_external_content_update", :via => [:get, :post]
  end

  # We offer a bunch of atom and ical feeds for the user to get
  # data out of Instructure.  The :feed_code attribute is keyed
  # off of either a user, and enrollment, a course, etc. based on
  # that item's uuid.  In config/initializers/active_record.rb you'll
  # find a feed_code method to generate the code, and in
  # application_controller there's a get_feed_context to get it back out.
  scope "/feeds" do
    get "calendars/:feed_code" => "calendar_events_api#public_feed", :as => :feeds_calendar
    get "calendars/:feed_code.:format" => "calendar_events_api#public_feed", :as => :feeds_calendar_format
    get "forums/:feed_code" => "discussion_topics#public_feed", :as => :feeds_forum
    get "forums/:feed_code.:format" => "discussion_topics#public_feed", :as => :feeds_forum_format
    get "topics/:discussion_topic_id/:feed_code" => "discussion_entries#public_feed", :as => :feeds_topic
    get "topics/:discussion_topic_id/:feed_code.:format" => "discussion_entries#public_feed", :as => :feeds_topic_format
    get "announcements/:feed_code" => "announcements#public_feed", :as => :feeds_announcements
    get "announcements/:feed_code.:format" => "announcements#public_feed", :as => :feeds_announcements_format
    get "courses/:feed_code" => "courses#public_feed", :as => :feeds_course
    get "courses/:feed_code.:format" => "courses#public_feed", :as => :feeds_course_format
    get "groups/:feed_code" => "groups#public_feed", :as => :feeds_group
    get "groups/:feed_code.:format" => "groups#public_feed", :as => :feeds_group_format
    get "enrollments/:feed_code" => "courses#public_feed", :as => :feeds_enrollment
    get "enrollments/:feed_code.:format" => "courses#public_feed", :as => :feeds_enrollment_format
    get "users/:feed_code" => "users#public_feed", :as => :feeds_user
    get "users/:feed_code.:format" => "users#public_feed", :as => :feeds_user_format
    get "eportfolios/:eportfolio_id.:format" => "eportfolios#public_feed", :as => :feeds_eportfolio
    get "conversations/:feed_code" => "conversations#public_feed", :as => :feeds_conversation
    get "conversations/:feed_code.:format" => "conversations#public_feed", :as => :feeds_conversation_format
  end

  resources :assessment_questions do
    get "files/:id/download" => "files#assessment_question_show", :as => :map, :download => "1"
    get "files/:id/preview" => "files#assessment_question_show", :preview => "1"
    get "files/:id/:verifier" => "files#assessment_question_show", :as => :verified_file, :download => "1"
  end

  resources :eportfolios, except: :index do
    post :reorder_categories
    post ":eportfolio_category_id/reorder_entries" => "eportfolios#reorder_entries", :as => :reorder_entries
    resources :categories, controller: :eportfolio_categories do
      get "pages" => "eportfolio_categories#pages", :as => :pages
    end
    resources :entries, controller: :eportfolio_entries do
      resources :page_comments, path: :comments, only: [:create, :destroy]
      get "files/:attachment_id" => "eportfolio_entries#attachment", :as => :view_file
      get "submissions/:submission_id" => "eportfolio_entries#submission", :as => :preview_submission
    end

    get :export, as: :export_portfolio
    get :recent_submissions, as: :recent_submissions
    get ":category_name" => "eportfolio_categories#show", :as => :named_category
    get ":category_name/:entry_name" => "eportfolio_entries#show", :as => :named_category_entry
  end

  resources :groups do
    concerns :users
    delete "remove_user/:user_id" => "groups#remove_user", :as => :remove_user
    post :add_user
    get "accept_invitation/:uuid" => "groups#accept_invitation", :as => :accept_invitation
    get "members" => "groups#context_group_members"
    get "undelete" => "context#undelete_index", :as => :undelete_items
    post "undelete/:asset_string" => "context#undelete_item", :as => :undelete_item
    concerns :announcements
    concerns :discussions
    resources :calendar_events
    concerns :files, :file_images, :relative_files, :folders

    resources :external_tools, only: :show do
      collection do
        get :retrieve
      end
    end

    concerns :pages
    concerns :conferences
    concerns :media

    resources :collaborations
    get "lti_collaborations" => "collaborations#lti_index"
    get "lti_collaborations/*all" => "collaborations#lti_index"
    get "calendar" => "calendars#show"

    resources :external_tools do
      get :finished
      match :resource_selection, via: [:get, :post]
      collection do
        get :retrieve
      end
    end
  end

  resources :accounts do
    get "search(/:tab)", action: :course_user_search
    get "settings#{full_path_glob}", action: :settings
    get :reports_tab
    get :settings
    get :admin_tools
    get :eportfolio_moderation
    get "search" => "accounts#course_user_search", :as => :course_user_search
    post "account_users" => "accounts#add_account_user", :as => :add_account_user
    delete "account_users/:id" => "accounts#remove_account_user", :as => :remove_account_user
    resources :grading_standards, only: %i[index create update destroy]
    get :statistics
    get "statistics/over_time/:attribute" => "accounts#statistics_graph", :as => :statistics_graph
    get "statistics/over_time/:attribute.:format" => "accounts#statistics_graph", :as => :formatted_statistics_graph
    get :turnitin_confirmation
    get :vericite_confirmation
    resources :permissions, controller: :role_overrides, only: [:index, :create] do
      collection do
        post :add_role
        delete :remove_role
      end
    end
    get :reports
    get "calendar_settings", action: :account_calendar_settings, as: :calendar_settings

    scope(controller: :analytics_hub) do
      get "analytics_hub", action: :show, as: :analytics_hub
    end

    scope(controller: :brand_configs) do
      get "theme_editor", action: :new, as: :theme_editor
      get "brand_configs", action: :index
      post "brand_configs", action: :create
      delete "brand_configs", action: :destroy
      post "brand_configs/save_to_account", action: :save_to_account
      post "brand_configs/save_to_user_session", action: :save_to_user_session
    end

    resources :role_overrides, only: [:index, :create] do
      collection do
        post :add_role
        delete :remove_role
      end
    end

    resources :terms, except: %i[index new show edit]
    # handle the index route using terms_api_controller
    get "terms", controller: :terms_api, action: "index"

    resources :sub_accounts
    resources :calendar_events

    get :avatars
    get :sis_import
    resources :sis_imports, only: %i[create show index], controller: :sis_imports_api
    get "users" => "accounts#users", :as => "users"
    post "users" => "users#create", :as => :add_user
    get "users/:user_id/delete" => "accounts#confirm_delete_user", :as => :confirm_delete_user
    delete "users/:user_id" => "accounts#remove_user", :as => :delete_user

    # create/delete are handled by specific routes just above
    resources :users, only: %i[new edit show update]
    resources :account_notifications, only: %i[create update destroy]
    concerns :announcements
    resources :submissions

    put "sso_settings" => "authentication_providers#update_sso_settings",
        :as => :update_sso_settings
    delete "authentication_providers" => "authentication_providers#destroy_all", :as => :remove_all_authentication_providers
    resources :authentication_providers, only: %i[show] do
      get :refresh_metadata, action: :refresh_saml_metadata
    end
    resources :authentication_providers, only: %i[index create update destroy] do
      get :debugging, action: :debug_data
      put :debugging, action: :start_debugging
      delete :debugging, action: :stop_debugging
    end
    get "test_ldap_connections" => "authentication_providers#test_ldap_connection"
    get "test_ldap_binds" => "authentication_providers#test_ldap_bind"
    get "test_ldap_searches" => "authentication_providers#test_ldap_search"
    match "test_ldap_logins" => "authentication_providers#test_ldap_login", :via => [:get, :post]

    get "external_tools/sessionless_launch" => "external_tools#sessionless_launch"
    resources :external_tools do
      get :finished
      match :resource_selection, via: [:get, :post]
      collection do
        get :retrieve
      end
    end

    get "lti/resource/:resource_link_id",
        controller: "lti/message",
        action: "resource",
        as: :resource_link_id
    get "lti/basic_lti_launch_request/:message_handler_id",
        controller: "lti/message",
        action: "basic_lti_launch_request",
        as: :basic_lti_launch_request
    post "lti/tool_proxy_registration", controller: "lti/message", action: "registration", as: :tool_proxy_registration
    get "lti/tool_proxy_reregistration/:tool_proxy_id",
        controller: "lti/message",
        action: "reregistration",
        as: :tool_proxy_reregistration
    get "lti/registration_return",
        controller: "lti/message",
        action: "registration_return",
        as: :registration_return

    get "outcomes/users/:user_id" => "outcomes#user_outcome_results", :as => :user_outcomes_results
    resources :outcomes do
      get "results" => "outcomes#outcome_results"
      get "results/:id" => "outcomes#outcome_result", :as => :result
      get "alignments/:id" => "outcomes#alignment_redirect", :as => :alignment_redirect
      get :details
      collection do
        get :list
        post :add_outcome
      end
    end

    resources :outcome_groups, only: %i[create update destroy] do
      post :reorder
    end

    resources :rubrics
    resources :rubric_associations do
      resources :rubric_assessments, path: "assessments"
    end

    concerns :files, :file_images, :relative_files, :folders
    concerns :media
    concerns :groups

    resources :outcomes
    get :courses
    get "courses/:id" => "accounts#courses_redirect", :as => :courses_redirect
    resources :alerts
    resources :question_banks do
      post :bookmark
      post :reorder
      get :questions
      post :move_questions
      resources :assessment_questions
    end

    resources :user_lists, only: :create

    member do
      get :statistics
    end
    resources :developer_keys, only: :index
    get "/developer_keys/:key_id", controller: :developer_keys, action: :index, as: "account_developer_key_view"

    get "apps", controller: "lti/registrations", action: :index, as: "lti_registrations"
    get "apps/*path", controller: "lti/registrations", action: :index
    get "apps/manage", controller: "lti/registrations", action: :index, as: "lti_manage_registrations"

    get "release_notes" => "release_notes#manage", :as => :release_notes_manage

    get "blackout_dates" => "blackout_dates#index"

    get "grading_schemes" => "grading_schemes_json#detail_list"
    get "grading_scheme_summaries" => "grading_schemes_json#summary_list"
    get "grading_scheme_grouped" => "grading_schemes_json#grouped_list"
    post "grading_schemes/:id/archive" => "grading_schemes_json#archive"
    post "grading_schemes/:id/unarchive" => "grading_schemes_json#unarchive"
    post "grading_schemes" => "grading_schemes_json#create"
    get "grading_schemes/account_default" => "grading_schemes_json#show_account_default_grading_scheme"
    put "grading_schemes/account_default" => "grading_schemes_json#update_account_default_grading_scheme"
    delete "grading_schemes/:id" => "grading_schemes_json#destroy"
    put "grading_schemes/:id" => "grading_schemes_json#update"
    get "grading_schemes/:id/used_locations" => "grading_schemes_json#used_locations", :as => :grading_schemes_used_locations
    get "grading_schemes/:id/used_locations/:course_id" => "grading_schemes_json#used_locations_for_course", :as => :grading_schemes_used_locations_for_course
    get "grading_schemes/:id/account_used_locations" => "grading_schemes_json#account_used_locations", :as => :grading_schemes_account_used_locations
    get "grading_schemes/default" => "grading_schemes_json#show_default_grading_scheme"
    get "grading_schemes/:id" => "grading_schemes_json#show"

    get "grading_settings" => "account_grading_settings#index"
    get "grading_settings/*path" => "account_grading_settings#index"
  end

  get "images/users/:user_id" => "users#avatar_image", :as => :avatar_image
  # The following two routes are only used when local storage is enabled, which isn't the case in prod.
  # Once we fully retire the uuids, we can remove the first route.
  get "images/thumbnails/show/:id/:uuid" => "files#show_thumbnail", :as => :show_thumbnail_image
  get "images/thumbnails/show/:id" => "files#show_thumbnail", :as => :show_thumbnail_image_plain
  get "images/thumbnails/:id/:uuid" => "files#image_thumbnail", :as => :thumbnail_image
  get "images/thumbnails/:id" => "files#image_thumbnail_plain", :as => :thumbnail_image_plain
  post "images/users/:user_id/report" => "users#report_avatar_image", :as => :report_avatar_image
  put "images/users/:user_id" => "users#update_avatar_image", :as => :update_avatar_image
  get "grades" => "users#grades"
  get "grades_for_student" => "users#grades_for_student"

  get "login" => "login#new"
  get "login/session_token" => "login#session_token", :as => :login_session_token
  delete "logout" => "login#destroy"
  get "logout" => "login#logout_landing"

  get "login/canvas" => "login/canvas#new", :as => :canvas_login
  get "login/canvas/forgot-password", to: "login/canvas#new"
  post "login/canvas" => "login/canvas#create"
  scope "login/canvas/register", as: "register" do
    get "/", to: "login/canvas#new", as: :landing
    get "/student", to: "login/canvas#new", as: :student
    get "/parent", to: "login/canvas#new", as: :parent
    get "/teacher", to: "login/canvas#new", as: :teacher
  end

  get "login/email_verify" => "login/email_verify#show", :as => :login_email_verify_show
  post "login/email_verify" => "login/email_verify#verify", :as => :login_email_verify

  get "login/ldap" => "login/ldap#new"
  post "login/ldap" => "login/ldap#create"

  get "login/cas" => "login/cas#new"
  get "login/cas/:id" => "login/cas#new", :as => :cas_login
  post "login/cas" => "login/cas#destroy", :as => :cas_logout
  post "login/cas/:id" => "login/cas#destroy"

  get "login/saml" => "login/saml#new", :as => :saml_login_base
  get "login/saml/logout" => "login/saml#destroy"
  post "login/saml/logout" => "login/saml#destroy"
  # deprecated alias
  get "saml_logout" => "login/saml#destroy"
  get "login/saml/:id" => "login/saml#new", :as => :saml_login
  get "saml_observee" => "login/saml#observee_validation", :as => :saml_observee
  post "login/saml" => "login/saml#create"
  # deprecated alias; no longer advertised
  post "saml_consume" => "login/saml#create"

  get "login/saml_idp_discovery" => "login/saml_idp_discovery#new"
  get "login/saml_idp_discovery/:id" => "login/saml_idp_discovery#new", :as => :saml_idp_discovery_login

  # the callback URL for all OAuth1.0a based SSO
  get "login/oauth/callback" => "login/oauth#create", :as => :oauth_login_callback
  # the callback URL for all OAuth2 based SSO
  get "login/oauth2/callback" => "login/oauth2#create", :as => :oauth2_login_callback
  # the callback URL for Apple
  post "login/oauth2/callback" => "login/oauth2#create"
  # ActionController::TestCase can't deal with aliased controllers when finding
  # routes, so we let this route exist only for tests
  get "login/oauth2" => "login/oauth2#new" if Rails.env.test?

  get "login/apple" => "login/apple#new", :as => :apple_login
  post "login/apple" => "login/apple#new"
  get "login/clever" => "login/clever#new", :as => :clever_login
  # Clever gets their own callback, cause we have to add additional processing
  # for their Instant Login feature
  get "login/clever/callback" => "login/clever#create", :as => :clever_callback
  get "login/clever/:id" => "login/clever#new"
  get "login/facebook" => "login/facebook#new", :as => :facebook_login
  get "login/github" => "login/github#new", :as => :github_login
  get "login/google" => "login/google#new", :as => :google_login
  post "login/google" => "login/google#new"
  get "login/google/:id" => "login/google#new"
  get "login/linkedin" => "login/linkedin#new", :as => :linkedin_login
  get "login/microsoft" => "login/microsoft#new"
  post "login/microsoft" => "login/microsoft#new"
  get "login/microsoft/:id" => "login/microsoft#new", :as => :microsoft_login
  get "login/openid_connect" => "login/openid_connect#new"
  post "login/openid_connect" => "login/openid_connect#new"
  get "login/openid_connect/:id" => "login/openid_connect#new", :as => :openid_connect_login
  post "login/openid_connect/logout" => "login/openid_connect#destroy", :as => :openid_connect_logout

  get "login/otp" => "login/otp#new", :as => :otp_login
  post "login/otp/sms" => "login/otp#send_via_sms", :as => :send_otp_via_sms
  post "login/otp" => "login/otp#create"
  delete "login/otp/cancel" => "login/otp#cancel_otp", :as => :cancel_otp
  get "users/self/otps" => "one_time_passwords#index", :as => :one_time_passwords
  delete "users/self/otps" => "one_time_passwords#destroy_all", :as => :destroy_all_one_time_passwords

  # deprecated redirect
  get "login/:id" => "login#new"

  delete "users/:user_id/mfa" => "login/otp#destroy", :as => :disable_mfa
  get "file_session/clear" => "login#clear_file_session", :as => :clear_file_session

  get "register" => "users#new"
  get "register_from_website" => "users#new"
  get "enroll/:self_enrollment_code" => "self_enrollments#new", :as => :enroll
  get "services" => "users#services"
  get "search/bookmarks" => "users#bookmark_search", :as => :bookmark_search
  get "search/rubrics" => "search#rubrics"
  get "search/all_courses" => "search#all_courses"
  resources :users, except: [:destroy, :index] do
    match "masquerade", via: [:get, :post]
    concerns :files, :file_images

    resources :page_views, only: :index
    resources :folders do
      get :download
    end

    resources :calendar_events
    get "external_tools/:id" => "users#external_tool", :as => :external_tool
    resources :rubrics
    resources :rubric_associations do
      resources :rubric_assessments, path: :assessments
    end

    resources :pseudonyms, except: :index
    resources :question_banks, only: :index
    get :admin_merge
    get :admin_split
    get :user_for_merge
    post :merge
    get :grades
    get :manageable_courses
    get "outcomes" => "outcomes#user_outcome_results"
    get "teacher_activity/course/:course_id" => "users#teacher_activity", :as => :course_teacher_activity
    get "teacher_activity/student/:student_id" => "users#teacher_activity", :as => :student_teacher_activity
    get :media_download
    resources :messages, only: %i[index create show] do
      get :html_message
    end
  end

  get "show_message_template" => "messages#show_message_template"
  get "message_templates" => "messages#templates"
  resource :profile, controller: :profile, only: [:show, :update] do
    resources :pseudonyms, except: :index
    resources :tokens, only: [] do
      member do
        post :activate
      end
    end
    member do
      put :update_profile
      get :communication
      put :communication_update
      get :settings
      get :content_shares
      get :observees
    end
  end

  get "account_notifications" => "account_notifications#render_past_global_announcements"

  scope "/profile" do
    post "toggle_disable_inbox" => "profile#toggle_disable_inbox"
    get "profile_pictures" => "profile#profile_pics", :as => :profile_pics
    get "qr_mobile_login" => "profile#qr_mobile_login", :as => :qr_mobile_login
    delete "user_services/:id" => "users#delete_user_service", :as => :profile_user_service
    post "user_services" => "users#create_user_service", :as => :profile_create_user_service
  end

  get "about/:id" => "profile#show", :as => :user_profile
  resources :communication_channels

  get "" => "users#user_dashboard", :as => "dashboard"
  get "dashboard-sidebar" => "users#dashboard_sidebar", :as => :dashboard_sidebar
  post "users/toggle_hide_dashcard_color_overlays" => "users#toggle_hide_dashcard_color_overlays"
  get "styleguide" => "info#styleguide"
  get "accounts/:account_id/theme-preview" => "brand_configs#show"
  root to: "users#user_dashboard", as: "root", via: :get
  # backwards compatibility with the old /dashboard url
  get "dashboard" => "users#user_dashboard", :as => :dashboard_redirect

  # Thought this idea of having dashboard-scoped urls was a good idea at the
  # time... now I'm not as big a fan.
  resource :dashboard, only: [] do
    resources :content_exports, path: :data_exports
  end

  scope "/dashboard" do
    get "stream_items" => "users#dashboard_stream_items", :as => :dashboard_stream_items
    get "dashboard_cards" => "users#dashboard_cards", :as => :dashboard_dashboard_cards
    put "view" => "users#dashboard_view"
    delete "account_notifications/:id" => "users#close_notification", :as => :dashboard_close_notification
    get "eportfolios" => "eportfolios#user_index", :as => :dashboard_eportfolios
    post "comment_session" => "services_api#start_kaltura_session", :as => :dashboard_comment_session
    delete "ignore_stream_item/:id" => "users#ignore_stream_item", :as => :dashboard_ignore_stream_item
  end

  resources :plugins, only: %i[index show update]

  get "calendar" => "calendars#show"
  get "calendar2" => "calendars#show"
  get "course_sections/:course_section_id/calendar_events/:id" => "calendar_events#show", :as => :course_section_calendar_event
  get "files" => "files#index"
  get "files/folder#{full_path_glob}", controller: "files", action: "react_files", format: false, defaults: { format: "html" }
  get "files/search", controller: "files", action: "react_files", format: false, defaults: { format: "html" }
  get "files/:id/public_url" => "files#public_url", :as => :public_url
  post "files/pending" => "files#create_pending", :as => :file_create_pending
  resources :assignments, only: :index do
    resources :files, only: [] do
      post "inline_view" => "files#show", :inline => "1"
    end
  end

  resources :appointment_groups, only: %i[index show edit]

  resources :errors, only: %i[show index create], path: :error_reports

  get "health_check" => "info#health_check"
  get "health_prognosis" => "info#health_prognosis"
  # To be used for uptime reporting
  get "readiness" => "info#readiness"
  # To be used by ALB
  get "internal/readiness" => "info#readiness"
  get "deep" => "info#deep"

  get "web-app-manifest/manifest.json" => "info#web_app_manifest"

  get "browserconfig.xml", to: "info#browserconfig", defaults: { format: "xml" }

  post "object_snippet" => "context#object_snippet"
  get "saml2" => "login/saml#metadata"
  get "internal/services/jwks" => "security#jwks"

  # Routes for course exports
  get "xsd/:version.xsd" => "content_exports#xml_schema"

  get "/jobs", to: "jobs_v2#redirect", as: "jobs"
  get "/job_stats", to: "jobs_v2#job_stats", as: "job_stats"

  resources :jobs_v1, controller: :jobs, only: [:index, :show] do
    collection do
      post "batch_update"
    end
  end

  resources :jobs_v2, only: [:index]

  get "equation_images/*id" => "equation_images#show", :as => :equation_images, :id => /.+/

  # assignments at the top level (without a context) -- we have some specs that
  # assert these routes exist, but just 404 unless it is a download from local
  # storage. I'm not sure we ever actually want top-level assignments available,
  # maybe we should change the specs instead.
  # Note, if local storage is used, a file is fetched from this top level
  # (i.e. SpeedGrader document preview with Google Docs viewer)
  resources :assignments, only: [:index, :show] do
    get "files/:id/download" => "files#show", :download => "1"
  end

  resources :files, except: [:new] do
    get "download" => "files#show", :download => "1"
  end

  resources :rubrics do
    resources :rubric_assessments, path: :assessments
  end

  post "selection_test" => "external_content#selection_test"

  scope "/quizzes/quiz_submissions/:quiz_submission_id", as: "quiz_submission" do
    concerns :files
  end

  get "courses/:course_id/outcome_rollups" => "outcome_results#rollups", :as => "course_outcome_rollups"

  get "terms_of_use" => "legal_information#terms_of_use", :as => "terms_of_use_redirect"
  get "privacy_policy" => "legal_information#privacy_policy", :as => "privacy_policy_redirect"

  scope(controller: :career) do
    # Routes for course/account are explicit so that get_context works (relies on :course_id and :account_id params)
    get "career/courses/:course_id", action: :show
    get "career/courses/:course_id/*path", action: :show
    get "career/accounts/:account_id", action: :show
    get "career/accounts/:account_id/*path", action: :show
    get "career", action: :show, as: :canvas_career
    get "career/*path", action: :show, as: :canvas_career_path
  end

  scope(controller: :career_experience) do
    post "career/switch_experience", action: :switch_experience
  end

  scope(controller: :smart_search) do
    get "courses/:course_id/search", action: :show, as: :course_search
    # TODO: Add back global search once we have a good way to handle it
    # get "search", action: :show
  end

  scope(controller: :translation) do
    post "courses/:course_id/translate", action: :translate, as: :translate
    post "courses/:course_id/translate/paragraph", action: :translate_paragraph, as: :translate_paragraph
  end

  scope(controller: "lti/asset_processor_launch") do
    get "asset_processors/:asset_processor_id/launch", action: :launch_settings, as: :asset_processor_settings_launch
    get "asset_processors/:asset_processor_id/reports/:report_id/launch", action: :launch_report, as: :asset_report_launch
  end

  scope(controller: "lti/eula_launch") do
    %w[course account].each do |context|
      get "#{context}s/:#{context}_id/external_tools/:context_external_tool_id/eula_launch", action: :launch_eula, as: "#{context}_tool_eula_launch"
    end
  end

  ### API routes ###

  # TODO: api routes can't yet take advantage of concerns for DRYness, because of
  # the way ApiRouteSet works. For now we get around it by defining methods
  # inline in the routes file, but getting concerns working would rawk.
  ApiRouteSet::V1.draw(self) do
    scope(controller: :courses) do
      get "courses", action: :index, as: "courses"
      put "courses/:id", action: :update
      get "courses/:id", action: :show, as: "course"
      delete "courses/:id", action: :destroy
      post "accounts/:account_id/courses", action: :create
      get "courses/:course_id/students", action: :students
      get "courses/:course_id/settings", action: :api_settings, as: "course_settings"
      put "courses/:course_id/settings", action: :update_settings
      get "courses/:course_id/recent_students", action: :recent_students, as: "course_recent_students"
      get "courses/:course_id/users", action: :users, as: "course_users"
      get "courses/:course_id/collaborations", controller: :collaborations, action: :api_index, as: "course_collaborations_index"
      delete "courses/:course_id/collaborations/:id", controller: :collaborations, action: :destroy
      put "courses/:id/quizzes", action: "new_quizzes_selection_update", as: "course_new_quizzes_selection_update"
      post "courses/:id/dismiss_migration_limitation_message", action: "dismiss_migration_limitation_msg", as: "course_dismiss_migration_limitation_msg"

      # this api endpoint has been removed, it was redundant with just courses#users
      # we keep it around for backward compatibility though
      get "courses/:course_id/search_users", action: :users
      get "courses/:course_id/users/:id", action: :user, as: "course_user"
      get "courses/:course_id/users/:user_id/progress", action: :user_progress
      get "courses/:course_id/content_share_users", action: :content_share_users, as: "course_content_share_users"
      get "courses/:course_id/activity_stream", action: :activity_stream, as: "course_activity_stream"
      get "courses/:course_id/activity_stream/summary", action: :activity_stream_summary, as: "course_activity_stream_summary"
      get "courses/:course_id/bulk_user_progress", action: :bulk_user_progress, as: "course_bulk_user_progress"
      get "courses/:course_id/todo", action: :todo_items, as: "course_todo_list_items"
      post "courses/:course_id/preview_html", action: :preview_html
      post "courses/:course_id/course_copy", controller: :content_imports, action: :copy_course_content
      get "courses/:course_id/course_copy/:id", controller: :content_imports, action: :copy_course_status, as: :course_copy_status
      get  "courses/:course_id/files", controller: :files, action: :api_index, as: "course_files"
      post "courses/:course_id/files", action: :create_file, as: "course_create_file"
      get "courses/:course_id/folders", controller: :folders, action: :list_all_folders, as: "course_folders"
      get "courses/:course_id/folders_and_files", controller: :folders, action: :list_all_folders_and_files, as: "course_folders_and_files"
      post "courses/:course_id/folders", controller: :folders, action: :create
      get "courses/:course_id/folders/by_path/*full_path", controller: :folders, action: :resolve_path
      get "courses/:course_id/folders/by_path", controller: :folders, action: :resolve_path
      get "courses/:course_id/folders/icon_maker", controller: :folders, action: :icon_maker_folder
      get "courses/:course_id/folders/media", controller: :folders, action: :media_folder
      get "courses/:course_id/folders/:id", controller: :folders, action: :show, as: "course_folder"
      get "media_objects", controller: "media_objects", action: :index, as: :media_objects
      get "courses/:course_id/media_objects", controller: "media_objects", action: :index, as: :course_media_objects
      get "groups/:group_id/media_objects", controller: "media_objects", action: :index, as: :group_media_objects
      get "media_attachments", controller: "media_objects", action: :index, as: :media_attachments
      get "courses/:course_id/media_attachments", controller: "media_objects", action: :index, as: :course_media_attachments
      get "groups/:group_id/media_attachments", controller: "media_objects", action: :index, as: :group_media_attachments
      put "accounts/:account_id/courses", action: :batch_update
      post "courses/:course_id/ping", action: :ping, as: "course_ping"

      get "courses/:course_id/link_validation", action: :link_validation, as: "course_link_validation"
      post "courses/:course_id/link_validation", action: :start_link_validation

      get "courses/:course_id/youtube_migration/scan", action: :youtube_migration_scan, as: "course_youtube_migration_scan"
      post "courses/:course_id/youtube_migration/scan", action: :start_youtube_migration_scan
      post "courses/:course_id/youtube_migration/convert", action: :start_youtube_migration_convert

      post "courses/:course_id/reset_content", action: :reset_content
      get  "users/:user_id/courses", action: :user_index, as: "user_courses"
      get "courses/:course_id/effective_due_dates", action: :effective_due_dates, as: "course_effective_due_dates"
      get "courses/:course_id/permissions", action: :permissions

      get "courses/:course_id/student_view_student", action: :student_view_student
    end

    scope(controller: :account_calendars_api) do
      get "account_calendars", action: :index, as: :account_calendars
      get "account_calendars/:account_id", action: :show, as: :account_calendar
      put "account_calendars/:account_id", action: :update, as: :update_account_calendar
      put "accounts/:account_id/account_calendars", action: :bulk_update, as: :bulk_update_account_calendars
      get "accounts/:account_id/account_calendars", action: :all_calendars, as: :all_account_calendars
      get "accounts/:account_id/visible_calendars_count", action: :visible_calendars_count, as: :visible_calendars_count
    end

    scope(controller: :account_notifications) do
      post "accounts/:account_id/account_notifications", action: :create, as: "account_notification"
      put "accounts/:account_id/account_notifications/:id", action: :update, as: "account_notification_update"
      get "accounts/:account_id/account_notifications", action: :user_index, as: "user_account_notifications" # to change the api docs
      get "accounts/:account_id/users/:user_id/account_notifications", action: :user_index_deprecated # for back compat
      get "accounts/:account_id/account_notifications/:id", action: :show, as: "user_account_notification_show"
      get "accounts/:account_id/users/:user_id/account_notifications/:id", action: :show_deprecated
      delete "accounts/:account_id/account_notifications/:id", action: :user_close_notification, as: "user_account_notification"
      delete "accounts/:account_id/users/:user_id/account_notifications/:id", action: :user_close_notification_deprecated
    end

    scope(controller: :brand_configs_api) do
      get "brand_variables", action: :show
    end

    scope(controller: :accounts) do
      get "settings/environment", action: :environment
    end

    scope(controller: :tabs) do
      get "accounts/:account_id/tabs", action: :index, as: "account_tabs"
      get "courses/:course_id/tabs", action: :index, as: "course_tabs"
      get "groups/:group_id/tabs", action: :index, as: "group_tabs"
      get "users/:user_id/tabs", action: :index, as: "user_profile_tabs"
      put "courses/:course_id/tabs/:tab_id", action: :update
    end

    scope(controller: :gradebook_filters_api) do
      get "courses/:course_id/gradebook_filters", action: :index
      post "courses/:course_id/gradebook_filters", action: :create
      get "courses/:course_id/gradebook_filters/:id", action: :show
      put "courses/:course_id/gradebook_filters/:id", action: :update
      delete "courses/:course_id/gradebook_filters/:id", action: :destroy
    end

    scope(controller: :scopes_api) do
      get "accounts/:account_id/scopes", action: :index
    end

    scope(controller: :sections) do
      get "courses/:course_id/sections", action: :index, as: "course_sections"
      get "courses/:course_id/sections/:id", action: :show, as: "course_section"
      get "sections/:id", action: :show
      post "courses/:course_id/sections", action: :create
      put "sections/:id", action: :update
      delete "sections/:id", action: :destroy
      post "sections/:id/crosslist/:new_course_id", action: :crosslist
      delete "sections/:id/crosslist", action: :uncrosslist
    end

    scope(controller: :enrollments_api) do
      get  "courses/:course_id/enrollments", action: :index, as: "course_enrollments"
      get  "sections/:section_id/enrollments", action: :index, as: "section_enrollments"
      get  "users/:user_id/enrollments", action: :index, as: "user_enrollments"
      get  "users/:user_id/temporary_enrollment_status", action: :show_temporary_enrollment_status
      get  "accounts/:account_id/enrollments/:id", action: :show, as: "enrollment"

      post "accounts/:account_id/bulk_enrollment", action: :bulk_enrollment, as: "bulk_enrollment"
      post "courses/:course_id/enrollments", action: :create
      post "sections/:section_id/enrollments", action: :create
      post "courses/:course_id/enrollments/:id/accept", action: :accept
      post "courses/:course_id/enrollments/:id/reject", action: :reject

      put "courses/:course_id/users/:user_id/last_attended", action: :last_attended
      put "courses/:course_id/enrollments/:id/reactivate", action: :reactivate, as: "reactivate_enrollment"

      delete "courses/:course_id/enrollments/:id", action: :destroy, as: "destroy_enrollment"
    end

    scope(controller: :temporary_enrollment_pairings_api) do
      get "accounts/:account_id/temporary_enrollment_pairings", action: :index
      get "accounts/:account_id/temporary_enrollment_pairings/:id", action: :show
      get "accounts/:account_id/temporary_enrollment_pairings/new", action: :new
      post "accounts/:account_id/temporary_enrollment_pairings", action: :create
      delete "accounts/:account_id/temporary_enrollment_pairings/:id", action: :destroy
    end

    scope(controller: :terms_api) do
      get "accounts/:account_id/terms", action: :index, as: "enrollment_terms"
      get "accounts/:account_id/terms/:id", action: :show, as: "enrollment_term"
    end

    scope(controller: :terms) do
      post "accounts/:account_id/terms", action: :create
      put "accounts/:account_id/terms/:id", action: :update
      delete "accounts/:account_id/terms/:id", action: :destroy
    end

    scope(controller: :tokens) do
      get "users/:user_id/tokens/:id", action: :show, as: "token"
      post "users/:user_id/tokens", action: :create, as: "tokens"
      put "users/:user_id/tokens/:id", action: :update
      delete "users/:user_id/tokens/:id", action: :destroy
    end

    scope(controller: :authentication_audit_api) do
      get "audit/authentication/logins/:login_id", action: :for_login, as: "audit_authentication_login"
      get "audit/authentication/accounts/:account_id", action: :for_account, as: "audit_authentication_account"
      get "audit/authentication/users/:user_id", action: :for_user, as: "audit_authentication_user"
    end

    scope(controller: :grade_change_audit_api) do
      get "audit/grade_change/assignments/:assignment_id", action: :for_assignment, as: "audit_grade_change_assignment"
      get "audit/grade_change/courses/:course_id", action: :for_course, as: "audit_grade_change_course"
      get "audit/grade_change/students/:student_id", action: :for_student, as: "audit_grade_change_student"
      get "audit/grade_change/graders/:grader_id", action: :for_grader, as: "audit_grade_change_grader"
      get "audit/grade_change/courses/:course_id/assignments/:assignment_id",
          action: :for_course_and_other_parameters,
          as: "audit_grade_change_course_assignment"
      get "audit/grade_change/courses/:course_id/assignments/:assignment_id/graders/:grader_id",
          action: :for_course_and_other_parameters,
          as: "audit_grade_change_course_assignment_grader"
      get "audit/grade_change/courses/:course_id/assignments/:assignment_id/graders/:grader_id/students/:student_id",
          action: :for_course_and_other_parameters,
          as: "audit_grade_change_course_assignment_grader_student"
      get "audit/grade_change/courses/:course_id/assignments/:assignment_id/students/:student_id",
          action: :for_course_and_other_parameters,
          as: "audit_grade_change_course_assignment_student"
      get "audit/grade_change/courses/:course_id/graders/:grader_id",
          action: :for_course_and_other_parameters,
          as: "audit_grade_change_course_grader"
      get "audit/grade_change/courses/:course_id/graders/:grader_id/students/:student_id",
          action: :for_course_and_other_parameters,
          as: "audit_grade_change_course_grader_student"
      get "audit/grade_change/courses/:course_id/students/:student_id",
          action: :for_course_and_other_parameters,
          as: "audit_grade_change_course_student"
      get "audit/grade_change", action: :query, as: "audit_grade_change"
    end

    scope(controller: :course_audit_api) do
      get "audit/course/courses/:course_id", action: :for_course, as: "audit_course_for_course"
      get "audit/course/accounts/:account_id", action: :for_account, as: "audit_course_for_account"
    end

    scope(controller: :assignment_overrides) do
      get "courses/:course_id/assignments/:assignment_id/overrides", action: :index
      post "courses/:course_id/assignments/:assignment_id/overrides", action: :create
      get "courses/:course_id/assignments/:assignment_id/overrides/:id", action: :show, as: "assignment_override"
      put "courses/:course_id/assignments/:assignment_id/overrides/:id", action: :update
      delete "courses/:course_id/assignments/:assignment_id/overrides/:id", action: :destroy
      get "sections/:course_section_id/assignments/:assignment_id/override", action: :section_alias
      get "groups/:group_id/assignments/:assignment_id/override", action: :group_alias
      get "courses/:course_id/assignments/overrides", action: :batch_retrieve
      put "courses/:course_id/assignments/overrides", action: :batch_update
      post "courses/:course_id/assignments/overrides", action: :batch_create
    end

    scope(controller: :assignments_api) do
      get "courses/:course_id/assignments/gradeable_students", controller: :submissions_api, action: :multiple_gradeable_students, as: "multiple_assignments_gradeable_students"
      get "courses/:course_id/assignments", action: :index, as: "course_assignments"
      get "courses/:course_id/assignment_groups/:assignment_group_id/assignments", action: :index, as: "course_assignment_group_assignments"
      get "users/:user_id/courses/:course_id/assignments", action: :user_index, as: "user_course_assignments"
      put "courses/:course_id/assignments/bulk_update", action: :bulk_update
      get "courses/:course_id/assignments/:id", action: :show, as: "course_assignment"
      get "courses/:course_id/assignments/:assignment_id/users/:user_id/group_members", action: :student_group_members
      post "courses/:course_id/assignments", action: :create
      put "courses/:course_id/assignments/:id", action: :update
      post "courses/:course_id/assignments/:assignment_id/duplicate", action: :duplicate
      post "courses/:course_id/assignments/:assignment_id/retry_alignment_clone", action: :retry_alignment_clone
      delete "courses/:course_id/assignments/:id", action: :destroy, controller: :assignments
    end

    scope(controller: "assignment_extensions") do
      post "courses/:course_id/assignments/:assignment_id/extensions", action: :create, as: "course_assignment_extensions_create"
    end

    scope(controller: :peer_reviews_api) do
      get "courses/:course_id/assignments/:assignment_id/peer_reviews", action: :index
      get "sections/:section_id/assignments/:assignment_id/peer_reviews", action: :index
      get "courses/:course_id/assignments/:assignment_id/submissions/:submission_id/peer_reviews", action: :index
      get "sections/:section_id/assignments/:assignment_id/submissions/:submission_id/peer_reviews", action: :index
      post "courses/:course_id/assignments/:assignment_id/submissions/:submission_id/peer_reviews", action: :create
      post "sections/:section_id/assignments/:assignment_id/submissions/:submission_id/peer_reviews", action: :create
      delete "courses/:course_id/assignments/:assignment_id/submissions/:submission_id/peer_reviews", action: :destroy
      delete "sections/:section_id/assignments/:assignment_id/submissions/:submission_id/peer_reviews", action: :destroy
    end

    scope(controller: :moderation_set) do
      get "courses/:course_id/assignments/:assignment_id/moderated_students", action: :index, as: :moderated_students
      post "courses/:course_id/assignments/:assignment_id/moderated_students", action: :create, as: :add_moderated_students
    end

    scope(controller: :submissions_api) do
      [%w[course course], %w[section course_section]].each do |(context, path_prefix)|
        post "#{context.pluralize}/:#{context}_id/submissions/update_grades", action: :bulk_update
        put "#{context.pluralize}/:#{context}_id/assignments/:assignment_id/submissions/:user_id/read", action: :mark_submission_read, as: "#{context}_submission_mark_read"
        delete "#{context.pluralize}/:#{context}_id/assignments/:assignment_id/submissions/:user_id/read", action: :mark_submission_unread, as: "#{context}_submission_mark_unread"
        put "#{context.pluralize}/:#{context}_id/assignments/:assignment_id/submissions/:user_id/read/:item", action: :mark_submission_item_read, as: "#{context}_submission_mark_item_read"
        put "#{context.pluralize}/:#{context}_id/submissions/bulk_mark_read", action: :mark_bulk_submissions_as_read, as: "#{context}_submissions_bulk_mark_read"
        put "#{context.pluralize}/:#{context}_id/submissions/:user_id/clear_unread", action: :submissions_clear_unread, as: "#{context}_submissions_clear_unread"
        get "#{context.pluralize}/:#{context}_id/assignments/:assignment_id/submissions/:user_id/document_annotations/read", action: :document_annotations_read_state, as: "#{path_prefix}_submission_document_annotations_read_state"
        put "#{context.pluralize}/:#{context}_id/assignments/:assignment_id/submissions/:user_id/document_annotations/read", action: :mark_document_annotations_read, as: "#{path_prefix}_submission_document_annotations_mark_read"
        get "#{context.pluralize}/:#{context}_id/assignments/:assignment_id/submissions/:user_id/rubric_comments/read", action: :rubric_assessments_read_state, as: "#{path_prefix}_submission_rubric_comments_read_state"
        put "#{context.pluralize}/:#{context}_id/assignments/:assignment_id/submissions/:user_id/rubric_comments/read", action: :mark_rubric_assessments_read, as: "#{path_prefix}_submission_rubric_comments_mark_read"
        get "#{context.pluralize}/:#{context}_id/assignments/:assignment_id/submissions/:user_id/rubric_assessments/read", action: :rubric_assessments_read_state, as: "#{path_prefix}_submission_rubric_assessments_read_state"
        put "#{context.pluralize}/:#{context}_id/assignments/:assignment_id/submissions/:user_id/rubric_assessments/read", action: :mark_rubric_assessments_read, as: "#{path_prefix}_submission_rubric_assessments_mark_read"
        get "#{context.pluralize}/:#{context}_id/assignments/:assignment_id/submissions", action: :index, as: "#{path_prefix}_assignment_submissions"
        get "#{context.pluralize}/:#{context}_id/students/submissions", controller: :submissions_api, action: :for_students, as: "#{path_prefix}_student_submissions"
        get "#{context.pluralize}/:#{context}_id/assignments/:assignment_id/submissions/:user_id", action: :show, as: "#{path_prefix}_assignment_submission"
        get "#{context.pluralize}/:#{context}_id/assignments/:assignment_id/anonymous_submissions/:anonymous_id", action: :show_anonymous
        post "#{context.pluralize}/:#{context}_id/assignments/:assignment_id/submissions", action: :create, controller: :submissions
        post "#{context.pluralize}/:#{context}_id/assignments/:assignment_id/submissions/:user_id/files", action: :create_file
        put "#{context.pluralize}/:#{context}_id/assignments/:assignment_id/submissions/:user_id", action: :update
        put "#{context.pluralize}/:#{context}_id/assignments/:assignment_id/anonymous_submissions/:anonymous_id", action: :update_anonymous
        post "#{context.pluralize}/:#{context}_id/assignments/:assignment_id/submissions/update_grades", action: :bulk_update
        get "#{context.pluralize}/:#{context}_id/assignments/:assignment_id/submission_summary", action: :submission_summary, as: "#{path_prefix}_assignment_submission_summary"
      end
      get "courses/:course_id/assignments/:assignment_id/gradeable_students", action: :gradeable_students, as: "course_assignment_gradeable_students"
    end

    scope(controller: :anonymous_provisional_grades) do
      get "courses/:course_id/assignments/:assignment_id/anonymous_provisional_grades/status",
          action: :status,
          as: "course_assignment_anonymous_provisional_status"
    end

    scope(controller: :provisional_grades) do
      put "courses/:course_id/assignments/:assignment_id/provisional_grades/bulk_select",
          action: :bulk_select,
          as: "bulk_select_provisional_grades"
      get "courses/:course_id/assignments/:assignment_id/provisional_grades/status",
          action: :status,
          as: "course_assignment_provisional_status"
      post "courses/:course_id/assignments/:assignment_id/provisional_grades/publish",
           action: :publish,
           as: "publish_provisional_grades"
      put "courses/:course_id/assignments/:assignment_id/provisional_grades/:provisional_grade_id/select",
          action: :select,
          as: "select_provisional_grade"
    end

    scope(controller: :submission_comments_api) do
      post "/courses/:course_id/assignments/:assignment_id/submissions/:user_id/comments/files", action: :create_file
      put "courses/:course_id/assignments/:assignment_id/submissions/:user_id/comments/:id", action: :update
      delete "courses/:course_id/assignments/:assignment_id/submissions/:user_id/comments/:id", action: :destroy
    end

    post "/courses/:course_id/assignments/:assignment_id/submissions/:user_id/annotation_notification", action: :annotation_notification, controller: :submission_comments_api

    scope(controller: :gradebook_history_api) do
      get "courses/:course_id/gradebook_history/days", action: :days, as: "gradebook_history"
      get "courses/:course_id/gradebook_history/feed", action: :feed, as: "gradebook_history_feed"
      get "courses/:course_id/gradebook_history/:date", action: :day_details, as: "gradebook_history_for_day"
      get "courses/:course_id/gradebook_history/:date/graders/:grader_id/assignments/:assignment_id/submissions", action: :submissions, as: "gradebook_history_submissions"
    end

    get "courses/:course_id/assignment_groups", controller: :assignment_groups, action: :index
    scope(controller: :assignment_groups_api) do
      resources :assignment_groups, path: "courses/:course_id/assignment_groups", name_prefix: "course_", except: :index
    end

    scope(controller: :discussion_topics) do
      get "courses/:course_id/discussion_topics", action: :index, as: "course_discussion_topics"
      get "groups/:group_id/discussion_topics", action: :index, as: "group_discussion_topics"
    end

    scope(controller: :content_migrations) do
      %w[account course group user].each do |context|
        get "#{context.pluralize}/:#{context}_id/content_migrations/migrators", action: :available_migrators, as: "#{context}_content_migration_migrators_list"
        get "#{context.pluralize}/:#{context}_id/content_migrations/:id", action: :show, as: "#{context}_content_migration"
        get "#{context.pluralize}/:#{context}_id/content_migrations", action: :index, as: "#{context}_content_migration_list"
        post "#{context.pluralize}/:#{context}_id/content_migrations", action: :create, as: "#{context}_content_migration_create"
        put "#{context.pluralize}/:#{context}_id/content_migrations/:id", action: :update, as: "#{context}_content_migration_update"
        get "#{context.pluralize}/:#{context}_id/content_migrations/:id/selective_data", action: :content_list, as: "#{context}_content_migration_selective_data"
      end
      get "courses/:course_id/content_migrations/:id/asset_id_mapping", action: :asset_id_mapping
    end

    scope(controller: :migration_issues) do
      %w[account course group user].each do |context|
        get "#{context.pluralize}/:#{context}_id/content_migrations/:content_migration_id/migration_issues/:id", action: :show, as: "#{context}_content_migration_migration_issue"
        get "#{context.pluralize}/:#{context}_id/content_migrations/:content_migration_id/migration_issues", action: :index, as: "#{context}_content_migration_migration_issue_list"
        post "#{context.pluralize}/:#{context}_id/content_migrations/:content_migration_id/migration_issues", action: :create, as: "#{context}_content_migration_migration_issue_create"
        put "#{context.pluralize}/:#{context}_id/content_migrations/:content_migration_id/migration_issues/:id", action: :update, as: "#{context}_content_migration_migration_issue_update"
      end
    end

    scope(controller: :discussion_topics_api) do
      put "courses/:course_id/discussion_topics/migrate_disallow", action: :migrate_disallow
      put "courses/:course_id/discussion_topics/update_discussion_types", action: :update_discussion_types

      %w[course group].each do |context|
        put "#{context.pluralize}/:#{context}_id/discussion_topics/read_all", action: :mark_all_topic_read, as: "#{context}_discussion_mark_all_read"
        put "#{context.pluralize}/:#{context}_id/discussion_topics/:topic_id/read", action: :mark_topic_read, as: "#{context}_discussion_topic_mark_read"
        delete "#{context.pluralize}/:#{context}_id/discussion_topics/:topic_id/read", action: :mark_topic_unread, as: "#{context}_discussion_topic_mark_unread"
        put "#{context.pluralize}/:#{context}_id/discussion_topics/:topic_id/read_all", action: :mark_all_read, as: "#{context}_discussion_topic_mark_all_read"
        delete "#{context.pluralize}/:#{context}_id/discussion_topics/:topic_id/read_all", action: :mark_all_unread, as: "#{context}_discussion_topic_mark_all_unread"
        put "#{context.pluralize}/:#{context}_id/discussion_topics/:topic_id/entries/:entry_id/read", action: :mark_entry_read, as: "#{context}_discussion_topic_discussion_entry_mark_read"
        delete "#{context.pluralize}/:#{context}_id/discussion_topics/:topic_id/entries/:entry_id/read", action: :mark_entry_unread, as: "#{context}_discussion_topic_discussion_entry_mark_unread"

        get "#{context.pluralize}/:#{context}_id/discussion_topics/:topic_id", action: :show, as: "#{context}_discussion_topic"
        post "#{context.pluralize}/:#{context}_id/discussion_topics", controller: :discussion_topics, action: :create
        put "#{context.pluralize}/:#{context}_id/discussion_topics/:topic_id", controller: :discussion_topics, action: :update
        post "#{context.pluralize}/:#{context}_id/discussion_topics/reorder", controller: :discussion_topics, action: :reorder
        delete "#{context.pluralize}/:#{context}_id/discussion_topics/:topic_id", controller: :discussion_topics, action: :destroy

        get "#{context.pluralize}/:#{context}_id/discussion_topics/:topic_id/view", action: :view, as: "#{context}_discussion_topic_view"
        get "#{context.pluralize}/:#{context}_id/discussion_topics/:topic_id/summaries", action: :find_summary, as: "#{context}_discussion_topic_summary"
        post "#{context.pluralize}/:#{context}_id/discussion_topics/:topic_id/summaries", action: :find_or_create_summary, as: "#{context}_discussion_topic_create_summary"
        put "#{context.pluralize}/:#{context}_id/discussion_topics/:topic_id/summaries/disable", action: :disable_summary, as: "#{context}_discussion_topic_disable_summary"
        post "#{context.pluralize}/:#{context}_id/discussion_topics/:topic_id/summaries/:summary_id/feedback", action: :summary_feedback, as: "#{context}_discussion_topic_summary_feedback"
        get "#{context.pluralize}/:#{context}_id/discussion_topics/:topic_id/insights", action: :insight, as: "#{context}_discussion_topic_insight"
        post "#{context.pluralize}/:#{context}_id/discussion_topics/:topic_id/insights", action: :insight_generation, as: "#{context}_discussion_topic_insight_generation"
        get "#{context.pluralize}/:#{context}_id/discussion_topics/:topic_id/insights/entries", action: :insight_entries, as: "#{context}_discussion_topic_insight_entries"
        put "#{context.pluralize}/:#{context}_id/discussion_topics/:topic_id/insights/entries/:entry_id", action: :insight_entry_update, as: "#{context}_discussion_topic_insight_entry_update"
        post "#{context.pluralize}/:#{context}_id/discussion_topics/:topic_id/duplicate", action: :duplicate
        get "#{context.pluralize}/:#{context}_id/discussion_topics/:topic_id/entry_list", action: :entry_list, as: "#{context}_discussion_topic_entry_list"
        post "#{context.pluralize}/:#{context}_id/discussion_topics/:topic_id/entries", action: :add_entry, as: "#{context}_discussion_add_entry"
        get "#{context.pluralize}/:#{context}_id/discussion_topics/:topic_id/entries", action: :entries, as: "#{context}_discussion_entries"
        post "#{context.pluralize}/:#{context}_id/discussion_topics/:topic_id/entries/:entry_id/replies", action: :add_reply, as: "#{context}_discussion_add_reply"
        get "#{context.pluralize}/:#{context}_id/discussion_topics/:topic_id/entries/:entry_id/replies", action: :replies, as: "#{context}_discussion_replies"
        put "#{context.pluralize}/:#{context}_id/discussion_topics/:topic_id/entries/:id", controller: :discussion_entries, action: :update, as: "#{context}_discussion_update_reply"
        delete "#{context.pluralize}/:#{context}_id/discussion_topics/:topic_id/entries/:id", controller: :discussion_entries, action: :destroy, as: "#{context}_discussion_delete_reply"

        post "#{context.pluralize}/:#{context}_id/discussion_topics/:topic_id/entries/:entry_id/rating",
             action: :rate_entry,
             as: "#{context}_discussion_topic_discussion_entry_rate"
        put "#{context.pluralize}/:#{context}_id/discussion_topics/:topic_id/subscribed", action: :subscribe_topic, as: "#{context}_discussion_topic_subscribe"
        delete "#{context.pluralize}/:#{context}_id/discussion_topics/:topic_id/subscribed", action: :unsubscribe_topic, as: "#{context}_discussion_topic_unsubscribe"
      end
    end

    scope(controller: :discussion_topic_users) do
      get "courses/:course_id/discussion_topics/:topic_id/messageable_users", action: :search, as: "course_discussion_messageable_users"
      get "groups/:group_id/discussion_topics/:topic_id/messageable_users", action: :search, as: "group_discussion_messageable_users"
    end

    scope(controller: :collaborations) do
      get "collaborations/:id/members", action: :members, as: "collaboration_members"
      get "courses/:course_id/potential_collaborators", action: :potential_collaborators, as: "course_potential_collaborators"
      get "groups/:group_id/potential_collaborators", action: :potential_collaborators, as: "group_potential_collaborators"
    end

    scope(controller: "microsoft_sync/groups") do
      post "courses/:course_id/microsoft_sync/group", action: :create
      get "courses/:course_id/microsoft_sync/group", action: :show
      delete "courses/:course_id/microsoft_sync/group", action: :destroy
      post "courses/:course_id/microsoft_sync/schedule_sync", action: :sync
    end

    scope(controller: :external_tools) do
      post "/accounts/:account_id/external_tools/rce_favorites/:id", action: :mark_rce_favorite, as: :account_external_tools_mark_rce_favorite
      delete "/accounts/:account_id/external_tools/rce_favorites/:id", action: :unmark_rce_favorite, as: :account_external_tools_unmark_rce_favorite

      post "/accounts/:account_id/external_tools/top_nav_favorites/:id", action: :add_top_nav_favorite, as: :account_external_tools_add_top_nav_favorite
      delete "/accounts/:account_id/external_tools/top_nav_favorites/:id", action: :remove_top_nav_favorite, as: :account_external_tools_remove_top_nav_favorite

      get "/courses/:course_id/external_tools/visible_course_nav_tools", action: :visible_course_nav_tools, as: :visible_course_nav_tools
      get "/external_tools/visible_course_nav_tools", action: :all_visible_nav_tools, as: :all_visible_nav_tools

      %w[course account].each do |context|
        get "#{context}s/:#{context}_id/external_tools/sessionless_launch", action: :generate_sessionless_launch, as: "#{context}_external_tool_sessionless_launch"
        get "#{context}s/:#{context}_id/external_tools/:external_tool_id", action: :show, as: "#{context}_external_tool_show"

        # Migration URL
        get "#{context}s/:#{context}_id/external_tools/:external_tool_id/migration_info", action: :migration_info, as: "#{context}_external_tool_migration_info"

        get "#{context}s/:#{context}_id/external_tools", action: :index, as: "#{context}_external_tools"
        post "#{context}s/:#{context}_id/external_tools", action: :create, as: "#{context}_external_tools_create"
        post "#{context}s/:#{context}_id/create_tool_with_verification", action: :create_tool_with_verification, as: "#{context}_create_tool_with_verification"
        put "#{context}s/:#{context}_id/external_tools/:external_tool_id", action: :update, as: "#{context}_external_tools_update"
        delete "#{context}s/:#{context}_id/external_tools/:external_tool_id", action: :destroy, as: "#{context}_external_tools_delete"
      end

      get "groups/:group_id/external_tools", action: :index, as: "group_external_tools"
    end

    scope(controller: "lti/lti_apps") do
      %w[course account].each do |context|
        get "#{context}s/:#{context}_id/lti_apps/launch_definitions", action: :launch_definitions, as: "#{context}_launch_definitions"
        get "#{context}s/:#{context}_id/lti_apps", action: :index, as: "#{context}_app_definitions"
      end
    end

    scope(controller: "lti/tool_proxy") do
      %w[course account].each do |context|
        delete "#{context}s/:#{context}_id/tool_proxies/:tool_proxy_id",
               action: :destroy,
               as: "#{context}_delete_tool_proxy"
        put "#{context}s/:#{context}_id/tool_proxies/:tool_proxy_id",
            action: :update,
            as: "#{context}_update_tool_proxy"

        delete "#{context}s/:#{context}_id/tool_proxies/:tool_proxy_id/update",
               action: :dismiss_update,
               as: "#{context}_dismiss_update_tool_proxy"
        put "#{context}s/:#{context}_id/tool_proxies/:tool_proxy_id/update",
            action: :accept_update,
            as: "#{context}_accept_update_tool_proxy"
      end
    end

    scope(controller: :external_feeds) do
      %w[course group].each do |context|
        get "#{context}s/:#{context}_id/external_feeds", action: :index, as: "#{context}_external_feeds"
        post "#{context}s/:#{context}_id/external_feeds", action: :create, as: "#{context}_external_feeds_create"
        delete "#{context}s/:#{context}_id/external_feeds/:external_feed_id", action: :destroy, as: "#{context}_external_feeds_delete"
      end
    end

    scope(controller: :sis_imports_api) do
      post "accounts/:account_id/sis_imports", action: :create
      put "accounts/:account_id/sis_imports/abort_all_pending", action: :abort_all_pending
      get "accounts/:account_id/sis_imports/importing", action: :importing
      get "accounts/:account_id/sis_imports/:id", action: :show
      get "accounts/:account_id/sis_imports", action: :index, as: "account_sis_imports"
      put "accounts/:account_id/sis_imports/:id/abort", action: :abort
      put "accounts/:account_id/sis_imports/:id/restore_states", action: :restore_states
    end

    scope(controller: :sis_import_errors_api) do
      get "accounts/:account_id/sis_imports/:id/errors", action: :index, as: :sis_batch_import_errors
      get "accounts/:account_id/sis_import_errors", action: :index, as: :account_sis_import_errors
    end

    scope(controller: :outcome_imports_api) do
      %w[account course].each do |context|
        post "#{context}s/:#{context}_id/outcome_imports(/group/:learning_outcome_group_id)", action: :create
        get "#{context}s/:#{context}_id/outcome_imports/:id", action: :show
        get "#{context}s/:#{context}_id/outcome_imports/:id/created_group_ids", action: :created_group_ids
      end
    end

    scope(controller: :outcome_proficiency_api) do
      post "accounts/:account_id/outcome_proficiency", action: :create
      get "accounts/:account_id/outcome_proficiency", action: :show
      post "courses/:course_id/outcome_proficiency", action: :create
      get "courses/:course_id/outcome_proficiency", action: :show
    end

    scope(controller: :users) do
      get "users/self/activity_stream", action: :activity_stream, as: "user_activity_stream"
      get "users/activity_stream", action: :activity_stream # deprecated
      get "users/self/activity_stream/summary", action: :activity_stream_summary, as: "user_activity_stream_summary"
      delete "users/self/activity_stream/:id", action: "ignore_stream_item"
      delete "users/self/activity_stream", action: "ignore_all_stream_items"

      put "users/:user_id/followers/self", action: :follow
      delete "users/:user_id/followers/self", action: :unfollow

      get "users/self/todo", action: :todo_items, as: "user_todo_list_items"
      get "users/self/todo_item_count", action: :todo_item_count
      get "users/self/upcoming_events", action: :upcoming_events
      get "users/:user_id/missing_submissions", action: :missing_submissions, as: "user_missing_submissions"

      delete "users/self/todo/:asset_string/:purpose", action: :ignore_item, as: "users_todo_ignore"
      post "accounts/:account_id/users", action: :create
      post "accounts/:account_id/self_registration", action: :create_self_registered_user
      get "accounts/:account_id/users", action: :api_index, as: "account_users"

      get "users/:id", action: :api_show
      put "users/:id", action: :update
      delete "users/mobile_sessions", action: :expire_mobile_sessions
      delete "users/:id", action: :destroy, as: "destroy_user"
      delete "users/:id/sessions", action: :terminate_sessions
      delete "users/:id/mobile_sessions", action: :expire_mobile_sessions

      post "users/:user_id/files", action: :create_file
      get  "users/:user_id/files", controller: :files, action: :api_index, as: "user_files"
      get "users/:user_id/folders", controller: :folders, action: :list_all_folders, as: "user_folders"
      get "users/:user_id/folders_and_files", controller: :folders, action: :list_all_folders_and_files, as: "user_folders_and_files"
      post "users/:user_id/folders", controller: :folders, action: :create
      get "users/:user_id/folders/by_path/*full_path", controller: :folders, action: :resolve_path
      get "users/:user_id/folders/by_path", controller: :folders, action: :resolve_path
      get "users/:user_id/folders/:id", controller: :folders, action: :show, as: "user_folder"

      get "users/:id/settings", controller: "users", action: "settings"
      put "users/:id/settings", controller: "users", action: "settings", as: "user_settings"

      get "users/:id/colors", controller: "users", action: "get_custom_colors"
      get "users/:id/colors/:asset_string", controller: "users", action: "get_custom_color"
      put "users/:id/colors/:asset_string", controller: "users", action: "set_custom_color"

      put "users/:id/text_editor_preference", controller: "users", action: "set_text_editor_preference"

      put "users/:id/files_ui_version_preference", controller: "users", action: "set_files_ui_version_preference"

      get "users/:id/new_user_tutorial_statuses", action: "get_new_user_tutorial_statuses"
      put "users/:id/new_user_tutorial_statuses/:page_name", action: "set_new_user_tutorial_status"

      get "users/:id/dashboard_positions", controller: "users", action: "get_dashboard_positions"
      put "users/:id/dashboard_positions", controller: "users", action: "set_dashboard_positions"

      put "users/:id/merge_into/:destination_user_id", controller: "users", action: "merge_into"
      put "users/:id/merge_into/accounts/:destination_account_id/users/:destination_user_id", controller: "users", action: "merge_into"
      post "users/:id/split", controller: "users", action: "split", as: "split"

      post "users/self/pandata_events_token", controller: "users", action: "pandata_events_token"

      get "dashboard/dashboard_cards", controller: "users", action: "dashboard_cards", as: :dashboard_dashboard_cards

      get "users/:id/graded_submissions", controller: "users", action: "user_graded_submissions", as: :user_submissions

      get "show_k5_dashboard", controller: "users", action: "show_k5_dashboard"

      post "users/:id/clear_cache", action: :clear_cache, as: "clear_cache"

      scope(controller: :user_observees) do
        get    "users/:user_id/observers", action: :observers, as: "user_observers"
        get    "users/:user_id/observees", action: :index, as: "user_observees"
        post   "users/:user_id/observees", action: :create
        get    "users/:user_id/observees/:observee_id", action: :show, as: "user_observee"
        get    "users/:user_id/observers/:observer_id", action: :show_observer, as: "user_observer"
        put    "users/:user_id/observees/:observee_id", action: :update
        delete "users/:user_id/observees/:observee_id", action: :destroy
      end

      scope(controller: :learning_object_dates) do
        get "courses/:course_id/modules/:context_module_id/date_details", action: :show, as: "course_context_module_date_details"
        get "courses/:course_id/assignments/:assignment_id/date_details", action: :show, as: "course_assignment_date_details"
        get "courses/:course_id/quizzes/:quiz_id/date_details", action: :show, as: "course_quizzes_quiz_date_details"
        get "courses/:course_id/discussion_topics/:discussion_topic_id/date_details", action: :show, as: "course_discussion_topic_date_details"
        get "courses/:course_id/pages/:url_or_id/date_details", action: :show, as: "course_wiki_page_date_details"
        get "courses/:course_id/files/:attachment_id/date_details", action: :show, as: "course_attachment_date_details"

        put "courses/:course_id/assignments/:assignment_id/date_details", action: :update
        put "courses/:course_id/quizzes/:quiz_id/date_details", action: :update
        put "courses/:course_id/discussion_topics/:discussion_topic_id/date_details", action: :update
        put "courses/:course_id/pages/:url_or_id/date_details", action: :update
        put "courses/:course_id/files/:attachment_id/date_details", action: :update

        put "courses/:course_id/assignments/:assignment_id/date_details/convert_tag_overrides", action: :convert_tag_overrides_to_adhoc_overrides
        put "courses/:course_id/quizzes/:quiz_id/date_details/convert_tag_overrides", action: :convert_tag_overrides_to_adhoc_overrides
        put "courses/:course_id/discussion_topics/:discussion_topic_id/date_details/convert_tag_overrides", action: :convert_tag_overrides_to_adhoc_overrides
        put "courses/:course_id/pages/:url_or_id/date_details/convert_tag_overrides", action: :convert_tag_overrides_to_adhoc_overrides
      end

      scope(controller: :course_tag_conversion) do
        put "courses/:course_id/convert_tag_overrides", action: :convert_tag_overrides_to_adhoc_overrides
        get "courses/:course_id/convert_tag_overrides/status", action: :conversion_job_status
      end

      scope(controller: :login) do
        get "login/session_token", action: :session_token, as: :login_session_token
      end

      scope(controller: :observer_alerts_api) do
        get "users/:user_id/observer_alerts/unread_count", action: :alerts_count
        get "users/:user_id/observer_alerts/:student_id", action: :alerts_by_student, as: "observer_alerts_by_student"
        put "users/:user_id/observer_alerts/:observer_alert_id/:workflow_state", action: :update
      end

      scope(controller: :observer_alert_thresholds_api) do
        get "users/:user_id/observer_alert_thresholds", action: :index
        post "users/:user_id/observer_alert_thresholds", action: :create
        get "users/:user_id/observer_alert_thresholds/:observer_alert_threshold_id", action: :show
        put "users/:user_id/observer_alert_thresholds/:observer_alert_threshold_id", action: :update
        delete "users/:user_id/observer_alert_thresholds/:observer_alert_threshold_id", action: :destroy
      end

      scope(controller: :observer_pairing_codes_api) do
        post "users/:user_id/observer_pairing_codes", action: :create
      end
    end

    scope(controller: :custom_data) do
      glob = "(/*scope)"
      get "users/:user_id/custom_data#{glob}", action: "get_data"
      put "users/:user_id/custom_data#{glob}", action: "set_data"
      delete "users/:user_id/custom_data#{glob}", action: "delete_data"
    end

    scope(controller: :pseudonyms) do
      get "accounts/:account_id/logins", action: :index, as: "account_pseudonyms"
      get "users/:user_id/logins", action: :index, as: "user_pseudonyms"
      post "accounts/:account_id/logins", action: :create
      put "accounts/:account_id/logins/:id", action: :update
      delete "users/:user_id/logins/:id", action: :destroy
      post "users/reset_password", action: :forgot_password
      post "users/:user_id/logins/:id/migrate_login_attribute", action: :migrate_login_attribute
    end

    scope(controller: :accounts) do
      get "accounts", action: :index, as: :accounts
      get "course_accounts", action: :course_accounts, as: :course_accounts
      get "manageable_accounts", action: :manageable_accounts, as: :manageable_accounts
      get "course_creation_accounts", action: :course_creation_accounts, as: :course_creation_accounts
      get "accounts/:id", action: :show, as: :account
      put "accounts/:id", action: :update
      get "accounts/:account_id/terms_of_service", action: :terms_of_service
      get "accounts/:account_id/help_links", action: :help_links
      get "accounts/:account_id/courses", action: :courses_api, as: "account_courses"
      get "accounts/:account_id/sub_accounts", action: :sub_accounts, as: "sub_accounts"
      get "accounts/:account_id/courses/:id", controller: :courses, action: :show, as: "account_course_show"
      get "accounts/:account_id/permissions", action: :permissions
      get "accounts/:account_id/settings", action: :show_settings
      get "manually_created_courses_account", action: :manually_created_courses_account
      delete "accounts/:account_id/users", action: :remove_users
      delete "accounts/:account_id/users/:user_id", action: :remove_user
      put "accounts/:account_id/users/bulk_update", action: :update_users
      put "accounts/:account_id/users/:user_id/restore", action: :restore_user
      get "accounts/:account_id/quiz_ip_filters", action: :quiz_ip_filters, as: "quiz_ip_filters"
      get "acceptable_use_policy", action: :acceptable_use_policy
    end

    scope(controller: :sub_accounts) do
      post "accounts/:account_id/sub_accounts", action: :create
      delete "accounts/:account_id/sub_accounts/:id", action: :destroy
    end

    scope(controller: :role_overrides) do
      get "accounts/:account_id/roles", action: :api_index, as: "account_roles"
      get "accounts/:account_id/roles/:id", action: :show
      post "accounts/:account_id/roles", action: :add_role
      post "accounts/:account_id/roles/:id/activate", action: :activate_role
      put "accounts/:account_id/roles/:id", action: :update
      delete "accounts/:account_id/roles/:id", action: :remove_role
      get "accounts/:account_id/permissions/:permission", action: :check_account_permission
    end

    scope(controller: :account_reports) do
      get "accounts/:account_id/reports/:report", action: :index
      get "accounts/:account_id/reports", action: :available_reports
      get "accounts/:account_id/reports/:report/:id", action: :show
      post "accounts/:account_id/reports/:report", action: :create, as: "account_create_report"
      delete "accounts/:account_id/reports/:report/:id", action: :destroy
      put "accounts/:account_id/reports/:report/:id/abort", action: :abort
    end

    scope(controller: :course_reports) do
      get "courses/:course_id/reports/:report_type", action: :last
      get "courses/:course_id/reports/:report_type/:id", action: :show
      post "courses/:course_id/reports/:report_type", action: :create
    end

    scope(controller: :admins) do
      post "accounts/:account_id/admins", action: :create
      delete "accounts/:account_id/admins/:user_id", action: :destroy
      get "accounts/:account_id/admins", action: :index, as: "account_admins"
      get "accounts/:account_id/admins/self", action: :self_roles, as: "account_self_roles"
    end

    scope(controller: :authentication_providers) do
      get "accounts/:account_id/sso_settings", action: :show_sso_settings, as: "account_show_sso_settings_url"
      put "accounts/:account_id/sso_settings", action: :update_sso_settings, as: "account_update_sso_settings_url"

      get "accounts/:account_id/authentication_providers", action: :index
      get "accounts/:account_id/authentication_providers/:id", action: :show
      post "accounts/:account_id/authentication_providers", action: :create, as: "account_create_ap"
      put "accounts/:account_id/authentication_providers/:id", action: :update, as: "account_update_ap"
      delete "accounts/:account_id/authentication_providers/:id", action: :destroy, as: "account_delete_ap"
      put "accounts/:account_id/authentication_providers/:id/restore", action: :restore, as: "account_restore_ap"
    end

    get "users/:user_id/page_views", controller: :page_views, action: :index, as: "user_page_views"
    get "users/:user_id/profile", controller: :profile, action: :settings
    get "users/:user_id/avatars", controller: :profile, action: :profile_pics

    # deprecated routes, second one is solely for YARD. preferred API is api/v1/search/recipients
    get "conversations/find_recipients", controller: :search, action: :recipients
    get "conversations/find_recipients", controller: :conversations, action: :find_recipients

    scope(controller: :conversations) do
      get "conversations", action: :index, as: "conversations"
      post "conversations", action: :create
      get "conversations/deleted", action: :deleted_index, as: "deleted_conversations"
      put "conversations/restore", action: :restore_message
      post "conversations/mark_all_as_read", action: :mark_all_as_read
      get "conversations/batches", action: :batches, as: "conversations_batches"
      get "conversations/unread_count", action: :unread_count
      get "conversations/:id", action: :show
      put "conversations/:id", action: :update # stars, subscribed-ness, workflow_state
      delete "conversations/:id", action: :destroy
      post "conversations/:id/add_message", action: :add_message
      post "conversations/:id/add_recipients", action: :add_recipients
      post "conversations/:id/remove_messages", action: :remove_messages
      put "conversations", action: :batch_update
      delete "conversations/:id/delete_for_all", action: :delete_for_all
    end

    scope(controller: :communication_channels) do
      get "users/:user_id/communication_channels", action: :index, as: "communication_channels"
      post "users/:user_id/communication_channels", action: :create
      post "users/:user_id/communication_channels/:id", action: :reset_bounce_count, as: "reset_bounce_count"
      get "accounts/:account_id/bounced_communication_channels.csv", action: :bouncing_channel_report, defaults: { format: :csv }
      get "accounts/:account_id/bounced_communication_channels", action: :bouncing_channel_report
      post "accounts/:account_id/bounced_communication_channels/reset", action: :bulk_reset_bounce_counts
      get "accounts/:account_id/unconfirmed_communication_channels.csv", action: :unconfirmed_channel_report, defaults: { format: :csv }
      get "accounts/:account_id/unconfirmed_communication_channels", action: :unconfirmed_channel_report
      post "accounts/:account_id/unconfirmed_communication_channels/confirm", action: :bulk_confirm
      delete "users/self/communication_channels/push", action: :delete_push_token
      delete "users/:user_id/communication_channels/:id", action: :destroy
      delete "users/:user_id/communication_channels/:type/:address", action: :destroy, constraints: { address: %r{[^/?]+} }
    end

    scope(controller: :notification_preferences) do
      get "users/:user_id/communication_channels/:communication_channel_id/notification_preferences", action: :index
      get "users/:user_id/communication_channels/:communication_channel_id/notification_preference_categories", action: :category_index
      get "users/:user_id/communication_channels/:type/:address/notification_preferences", action: :index, constraints: { address: %r{[^/?]+} }
      get "users/:user_id/communication_channels/:communication_channel_id/notification_preferences/:notification", action: :show
      get "users/:user_id/communication_channels/:type/:address/notification_preferences/:notification", action: :show, constraints: { address: %r{[^/?]+} }
      put "users/self/communication_channels/:communication_channel_id/notification_preferences/:notification", action: :update
      put "users/self/communication_channels/:type/:address/notification_preferences/:notification", action: :update, constraints: { address: %r{[^/?]+} }
      put "users/self/communication_channels/:communication_channel_id/notification_preferences", action: :update_all
      put "users/self/communication_channels/:type/:address/notification_preferences", action: :update_all, constraints: { address: %r{[^/?]+} }
      put "users/self/communication_channels/:communication_channel_id/notification_preference_categories/:category", action: :update_preferences_by_category
    end

    scope(controller: :comm_messages_api) do
      get "comm_messages", action: :index, as: "comm_messages"
    end

    scope(controller: :services_api) do
      get "services/kaltura", action: :show_kaltura_config
      post "services/kaltura_session", action: :start_kaltura_session
      get "services/rce_config", action: :rce_config
    end

    scope(controller: :calendar_events_api) do
      get "calendar_events", action: :index, as: "calendar_events"
      get "users/:user_id/calendar_events", action: :user_index, as: "user_calendar_events"
      post "calendar_events", action: :create
      get "calendar_events/visible_contexts", action: :visible_contexts
      get "calendar_events/:id", action: :show, as: "calendar_event"
      put "calendar_events/:id", action: :update
      delete "calendar_events/:id", action: :destroy
      post "calendar_events/:id/reservations", action: :reserve
      post "calendar_events/:id/reservations/:participant_id", action: :reserve, as: "calendar_event_reserve"
      get "calendar_events/:id/participants", action: :participants, as: "calendar_event_participants"
      post "calendar_events/save_selected_contexts", action: :save_selected_contexts
      post "calendar_events/save_enabled_account_calendars", action: :save_enabled_account_calendars

      get "courses/:course_id/calendar_events/timetable", action: :get_course_timetable
      post "courses/:course_id/calendar_events/timetable", action: :set_course_timetable
      post "courses/:course_id/calendar_events/timetable_events", action: :set_course_timetable_events
    end

    scope(controller: :appointment_groups) do
      get "appointment_groups", action: :index, as: "appointment_groups"
      post "appointment_groups", action: :create
      get "appointment_groups/next_appointment", action: :next_appointment
      get "appointment_groups/:id", action: :show, as: "appointment_group"
      put "appointment_groups/:id", action: :update
      delete "appointment_groups/:id", action: :destroy
      get "appointment_groups/:id/users", action: :users, as: "appointment_group_users"
      get "appointment_groups/:id/groups", action: :groups, as: "appointment_group_groups"
    end

    scope(controller: :groups) do
      resources :groups, except: :index
      get "users/self/groups", action: :index, as: "current_user_groups"
      get "accounts/:account_id/groups", action: :context_index, as: "account_user_groups"
      get "courses/:course_id/groups", action: :context_index, as: "course_user_groups"
      get "groups/:group_id/users", action: :users, as: "group_users"
      get "groups/:group_id/permissions", action: :permissions
      post "groups/:group_id/invite", action: :invite
      post "groups/:group_id/files", action: :create_file
      post "groups/:group_id/preview_html", action: :preview_html
      post "group_categories/:group_category_id/groups", action: :create
      get "groups/:group_id/activity_stream", action: :activity_stream, as: "group_activity_stream"
      get "groups/:group_id/activity_stream/summary", action: :activity_stream_summary, as: "group_activity_stream_summary"
      put "groups/:group_id/followers/self", action: :follow
      delete "groups/:group_id/followers/self", action: :unfollow
      get "groups/:group_id/collaborations", controller: :collaborations, action: :api_index, as: "group_collaborations_index"
      delete "groups/:group_id/collaborations/:id", controller: :collaborations, action: :destroy

      scope(controller: :group_memberships) do
        resources :memberships, path: "groups/:group_id/memberships", name_prefix: "group_", controller: :group_memberships
        resources :users, path: "groups/:group_id/users", name_prefix: "group_", controller: :group_memberships, except: [:index, :create]
      end

      get "groups/:group_id/files", controller: :files, action: :api_index, as: "group_files"
      get "groups/:group_id/folders", controller: :folders, action: :list_all_folders, as: "group_folders"
      get "groups/:group_id/folders_and_files", controller: :folders, action: :list_all_folders_and_files, as: "group_folders_and_files"
      post "groups/:group_id/folders", controller: :folders, action: :create
      get "groups/:group_id/folders/by_path/*full_path", controller: :folders, action: :resolve_path
      get "groups/:group_id/folders/by_path", controller: :folders, action: :resolve_path
      get "groups/:group_id/folders/media", controller: :folders, action: :media_folder
      get "groups/:group_id/folders/:id", controller: :folders, action: :show, as: "group_folder"
    end

    scope(controller: :developer_key_account_bindings) do
      post "accounts/:account_id/developer_keys/:developer_key_id/developer_key_account_bindings", action: :create_or_update
    end

    scope(controller: :developer_keys) do
      delete "developer_keys/:id", action: :destroy
      put "developer_keys/:id", action: :update

      get "accounts/:account_id/developer_keys", action: :index, as: "account_developer_keys"
      post "accounts/:account_id/developer_keys", action: :create
    end

    scope(controller: "lti/registrations") do
      get "accounts/:account_id/lti_registrations", action: :list
      post "accounts/:account_id/lti_registrations", action: :create
      post "accounts/:account_id/lti_registrations/configuration/validate", action: :validate_lti_configuration
      delete "accounts/:account_id/lti_registrations/:id", action: :destroy
      get "accounts/:account_id/lti_registrations/:registration_id/deployments/:deployment_id/context_search", action: :context_search, as: "lti_registration_context_search"
      get "accounts/:account_id/lti_registrations/:id", action: :show
      get "accounts/:account_id/lti_registrations/:id/overlay_history", action: :overlay_history
      get "accounts/:account_id/lti_registration_by_client_id/:client_id", action: :show_by_client_id
      put "accounts/:account_id/lti_registrations/:id", action: :update
      put "accounts/:account_id/lti_registrations/:id/reset", action: :reset
      post "accounts/:account_id/lti_registrations/:id/bind", action: :bind
    end

    scope(controller: "lti/deployments") do
      get "accounts/:account_id/lti_registrations/:registration_id/deployments", action: :list, as: :list_deployments
      post "accounts/:account_id/lti_registrations/:registration_id/deployments", action: :create
      delete "accounts/:account_id/lti_registrations/:registration_id/deployments/:id", action: :destroy
      get "accounts/:account_id/lti_registrations/:registration_id/deployments/:id", action: :show
      get "accounts/:account_id/lti_registrations/:registration_id/deployments/:id/controls", action: :list_controls, as: :list_deployment_controls
    end

    scope(controller: "lti/context_controls") do
      get "accounts/:account_id/lti_registrations/:registration_id/controls", action: :index, as: :lti_context_controls_index
      post "accounts/:current_account_id/lti_registrations/:registration_id/controls", action: :create # avoid param name conflict
      post "accounts/:account_id/lti_registrations/:registration_id/controls/bulk", action: :create_many
      get "accounts/:account_id/lti_registrations/:registration_id/controls/:id", action: :show
      put "accounts/:account_id/lti_registrations/:registration_id/controls/:id", action: :update
      delete "accounts/:account_id/lti_registrations/:registration_id/controls/:id", action: :delete
    end

    scope(controller: "lti/resource_links") do
      get "courses/:course_id/lti_resource_links", action: :index
      post "courses/:course_id/lti_resource_links", action: :create
      post "courses/:course_id/lti_resource_links/bulk", action: :bulk_create
      get "courses/:course_id/lti_resource_links/:id", action: :show
      put "courses/:course_id/lti_resource_links/:id", action: :update
      delete "courses/:course_id/lti_resource_links/:id", action: :destroy
    end

    scope(controller: :immersive_reader) do
      get "immersive_reader/authenticate", action: :authenticate
    end

    scope(controller: :search) do
      get "search/rubrics", action: "rubrics", as: "search_rubrics"
      get "search/recipients", action: "recipients", as: "search_recipients"
      get "search/all_courses", action: "all_courses", as: "search_all_courses"
    end

    post "files/:id/create_success", controller: :files, action: :api_create_success, as: "files_create_success"
    get "files/:id/create_success", controller: :files, action: :api_create_success

    scope(controller: :files) do
      post "files/:id/create_success", action: :api_create_success
      get "files/:id/create_success", action: :api_create_success
      match "/api/v1/files/:id/create_success", via: [:options], action: :api_create_success_cors
      post "files/capture", action: :api_capture, as: "files_capture"

      # 'attachment' (rather than 'file') is used below so modules API can use polymorphic_url to generate an item API link
      get "files/:id", action: :api_show, as: "attachment"
      get "files/:id/icon_metadata", action: :icon_metadata
      delete "files/:id", action: :destroy
      put "files/:id", action: :api_update
      post "files/:id/reset_verifier", action: :reset_verifier
      post "rce_linked_file_instfs_ids", action: :rce_linked_file_instfs_ids

      # exists as an alias of GET for backwards compatibility
      #
      # older API clients were told to POST to the value of the Location header
      # returned after upload to S3, when that was the create_success URL.
      # that's no longer necessary, but they are still given a Location header
      # pointed at this endpoint which they can GET for the file details (which
      # create_success would have provided).
      #
      # such behavior is now undocumented, and subject to removal once open
      # sourcing of inst-fs is complete.
      #
      # to actually change the file metadata (e.g. rename), the PUT route above
      # must be used.
      post "files/:id", action: :api_show

      get "files/:id/public_url", action: :public_url
      get "courses/:course_id/files/file_ref/:migration_id", action: :file_ref
      %w[course group user].each do |context|
        get "#{context}s/:#{context}_id/files/quota", action: :api_quota
        get "#{context}s/:#{context}_id/files/:id", action: :api_show, as: "#{context}_attachment"
      end
    end

    scope(controller: :folders) do
      get "folders/:id", action: :show
      get "folders/:id/folders", action: :api_index, as: "list_folders"
      get "folders/:id/all", action: :list_folders_and_files, as: "list_folders_and_files"
      get "folders/:id/files", controller: :files, action: :api_index, as: "list_files"
      delete "folders/:id", action: :api_destroy
      put "folders/:id", action: :update
      post "folders/:folder_id/folders", action: :create, as: "create_folder"
      post "accounts/:account_id/folders", action: :create
      post "folders/:folder_id/files", action: :create_file
      post "folders/:dest_folder_id/copy_file", action: :copy_file
      post "folders/:dest_folder_id/copy_folder", action: :copy_folder
    end

    scope(controller: :favorites) do
      get "users/self/favorites/courses", action: :list_favorite_courses, as: :list_favorite_courses
      post "users/self/favorites/courses/:id", action: :add_favorite_course, as: :add_favorite_course
      delete "users/self/favorites/courses/:id", action: :remove_favorite_course, as: :remove_favorite_course
      delete "users/self/favorites/courses", action: :reset_course_favorites
      get "users/self/favorites/groups", action: :list_favorite_groups, as: :list_favorite_groups
      post "users/self/favorites/groups/:id", action: :add_favorite_groups, as: :add_favorite_groups
      delete "users/self/favorites/groups/:id", action: :remove_favorite_groups, as: :remove_favorite_groups
      delete "users/self/favorites/groups", action: :reset_groups_favorites
    end

    scope(controller: :wiki_pages_api) do
      get "courses/:course_id/front_page", action: :show_front_page
      get "groups/:group_id/front_page", action: :show_front_page
      put "courses/:course_id/front_page", action: :update_front_page
      put "groups/:group_id/front_page", action: :update_front_page
      post "courses/:course_id/pages/:url_or_id/duplicate", action: :duplicate

      get "courses/:course_id/pages", action: :index, as: "course_wiki_pages"
      get "groups/:group_id/pages", action: :index, as: "group_wiki_pages"
      get "courses/:course_id/pages/:url_or_id", action: :show, as: "course_wiki_page"
      get "groups/:group_id/pages/:url_or_id", action: :show, as: "group_wiki_page"
      get "courses/:course_id/pages/:url_or_id/revisions", action: :revisions, as: "course_wiki_page_revisions"
      get "groups/:group_id/pages/:url_or_id/revisions", action: :revisions, as: "group_wiki_page_revisions"
      get "courses/:course_id/pages/:url_or_id/revisions/latest", action: :show_revision
      get "groups/:group_id/pages/:url_or_id/revisions/latest", action: :show_revision
      get "courses/:course_id/pages/:url_or_id/revisions/:revision_id", action: :show_revision
      get "groups/:group_id/pages/:url_or_id/revisions/:revision_id", action: :show_revision
      post "courses/:course_id/pages/:url_or_id/revisions/:revision_id", action: :revert
      post "groups/:group_id/pages/:url_or_id/revisions/:revision_id", action: :revert
      post "courses/:course_id/pages", action: :create
      post "groups/:group_id/pages", action: :create
      put "courses/:course_id/pages/:url_or_id", action: :update
      put "groups/:group_id/pages/:url_or_id", action: :update
      delete "courses/:course_id/pages/:url_or_id", action: :destroy
      delete "groups/:group_id/pages/:url_or_id", action: :destroy
      get "courses/:course_id/page_title_availability", action: :check_title_availability, as: "course_page_title_availability"
      get "groups/:group_id/page_title_availability", action: :check_title_availability, as: "group_page_title_availability"
    end

    scope(controller: :context_modules_api) do
      get "courses/:course_id/modules", action: :index, as: "course_context_modules"
      get "courses/:course_id/modules/:id", action: :show, as: "course_context_module"
      put "courses/:course_id/modules", action: :batch_update
      post "courses/:course_id/modules/:module_id/duplicate", action: :duplicate
      post "courses/:course_id/modules", action: :create, as: "course_context_module_create"
      put "courses/:course_id/modules/:id", action: :update, as: "course_context_module_update"
      delete "courses/:course_id/modules/:id", action: :destroy
      put "courses/:course_id/modules/:id/relock", action: :relock
    end

    scope(controller: :context_module_items_api) do
      get "courses/:course_id/modules/:module_id/items", action: :index, as: "course_context_module_items"
      get "courses/:course_id/modules/:module_id/items/:id", action: :show, as: "course_context_module_item"
      put "courses/:course_id/modules/:module_id/items/:id/done", action: :mark_as_done, as: "course_context_module_item_done"
      delete "courses/:course_id/modules/:module_id/items/:id/done", action: :mark_as_not_done, as: "course_context_module_item_not_done"
      get "courses/:course_id/module_item_redirect/:id", action: :redirect, as: "course_context_module_item_redirect"
      get "courses/:course_id/module_item_sequence", action: :item_sequence
      post "courses/:course_id/modules/:module_id/items", action: :create, as: "course_context_module_items_create"
      put "courses/:course_id/modules/:module_id/items/:id", action: :update, as: "course_context_module_item_update"
      delete "courses/:course_id/modules/:module_id/items/:id", action: :destroy
      post "courses/:course_id/modules/:module_id/items/:id/mark_read", action: :mark_item_read
      post "courses/:course_id/modules/:module_id/items/:id/select_mastery_path", action: :select_mastery_path
      post "courses/:course_id/modules/items/:id/duplicate", action: :duplicate, as: :course_context_module_item_duplicate
    end

    scope(controller: :module_assignment_overrides) do
      get "courses/:course_id/modules/:context_module_id/assignment_overrides", action: :index, as: "module_assignment_overrides_index"
      put "courses/:course_id/modules/:context_module_id/assignment_overrides", action: :bulk_update
      put "courses/:course_id/modules/:context_module_id/assignment_overrides/convert_tag_overrides", action: :convert_tag_overrides_to_adhoc_overrides
    end

    scope(controller: "quizzes/quiz_assignment_overrides") do
      get "courses/:course_id/quizzes/assignment_overrides", action: :index, as: "course_quiz_assignment_overrides"
      get "courses/:course_id/new_quizzes/assignment_overrides", action: :new_quizzes, as: "course_new_quizzes_assignment_overrides"
    end

    scope(controller: "quizzes/quizzes_api") do
      get "courses/:course_id/quizzes", action: :index, as: "course_quizzes"
      post "courses/:course_id/quizzes", action: :create, as: "course_quiz_create"
      get "courses/:course_id/quizzes/:id", action: :show, as: "course_quiz"
      put "courses/:course_id/quizzes/:id", action: :update, as: "course_quiz_update"
      delete "courses/:course_id/quizzes/:id", action: :destroy, as: "course_quiz_destroy"
      post "courses/:course_id/quizzes/:id/reorder", action: :reorder, as: "course_quiz_reorder"
      post "courses/:course_id/quizzes/:id/validate_access_code", action: :validate_access_code, as: "course_quiz_validate_access_code"
    end

    scope(controller: "quizzes_next/quizzes_api") do
      get "courses/:course_id/all_quizzes", action: :index, as: "course_all_quizzes"
    end

    scope(controller: "quizzes/quiz_submission_users") do
      get "courses/:course_id/quizzes/:id/submission_users", action: :index, as: "course_quiz_submission_users"
      post "courses/:course_id/quizzes/:id/submission_users/message", action: :message, as: "course_quiz_submission_users_message"
    end

    scope(controller: "quizzes/quiz_groups") do
      get "courses/:course_id/quizzes/:quiz_id/groups/:id", action: :show, as: "course_quiz_group"
      post "courses/:course_id/quizzes/:quiz_id/groups", action: :create, as: "course_quiz_group_create"
      put "courses/:course_id/quizzes/:quiz_id/groups/:id", action: :update, as: "course_quiz_group_update"
      delete "courses/:course_id/quizzes/:quiz_id/groups/:id", action: :destroy, as: "course_quiz_group_destroy"
      post "courses/:course_id/quizzes/:quiz_id/groups/:id/reorder", action: :reorder, as: "course_quiz_group_reorder"
    end

    scope(controller: "quizzes/quiz_questions") do
      get "courses/:course_id/quizzes/:quiz_id/questions", action: :index, as: "course_quiz_questions"
      get "courses/:course_id/quizzes/:quiz_id/questions/:id", action: :show, as: "course_quiz_question"
      post "courses/:course_id/quizzes/:quiz_id/questions", action: :create, as: "course_quiz_question_create"
      put "courses/:course_id/quizzes/:quiz_id/questions/:id", action: :update, as: "course_quiz_question_update"
      delete "courses/:course_id/quizzes/:quiz_id/questions/:id", action: :destroy, as: "course_quiz_question_destroy"
    end

    scope(controller: "quizzes/quiz_reports") do
      post "courses/:course_id/quizzes/:quiz_id/reports", action: :create, as: "course_quiz_reports_create"
      delete "courses/:course_id/quizzes/:quiz_id/reports/:id", action: :abort, as: "course_quiz_reports_abort"
      get "courses/:course_id/quizzes/:quiz_id/reports", action: :index, as: "course_quiz_reports"
      get "courses/:course_id/quizzes/:quiz_id/reports/:id", action: :show, as: "course_quiz_report"
    end

    scope(controller: "quizzes/quiz_submission_files") do
      post "courses/:course_id/quizzes/:quiz_id/submissions/self/files", action: :create, as: "quiz_submission_files"
    end

    scope(controller: "quizzes/quiz_submissions_api") do
      get "courses/:course_id/quizzes/:quiz_id/submission", action: :submission, as: "course_quiz_user_submission"
      get "courses/:course_id/quizzes/:quiz_id/submissions", action: :index, as: "course_quiz_submissions"
      get "courses/:course_id/quizzes/:quiz_id/submissions/:id", action: :show, as: "course_quiz_submission"
      get "courses/:course_id/quizzes/:quiz_id/submissions/:id/time", action: :time, as: "course_quiz_submission_time"
      post "courses/:course_id/quizzes/:quiz_id/submissions", action: :create, as: "course_quiz_submission_create"
      put "courses/:course_id/quizzes/:quiz_id/submissions/:id", action: :update, as: "course_quiz_submission_update"
      post "courses/:course_id/quizzes/:quiz_id/submissions/:id/complete", action: :complete, as: "course_quiz_submission_complete"
    end

    scope(controller: "quizzes/outstanding_quiz_submissions") do
      get "courses/:course_id/quizzes/:quiz_id/outstanding_quiz_submissions", action: :index, path_name: "outstanding_quiz_submission_index"
      post "courses/:course_id/quizzes/:quiz_id/outstanding_quiz_submissions", action: :grade, path_name: "outstanding_quiz_submission_grade"
    end

    scope(controller: "quizzes/quiz_extensions") do
      post "courses/:course_id/quizzes/:quiz_id/extensions", action: :create, as: "course_quiz_extensions_create"
    end

    scope(controller: "quizzes/course_quiz_extensions") do
      post "courses/:course_id/quiz_extensions", action: :create
    end

    scope(controller: "quizzes/quiz_submission_events_api") do
      get "courses/:course_id/quizzes/:quiz_id/submissions/:id/events", action: :index, as: "course_quiz_submission_events"
      post "courses/:course_id/quizzes/:quiz_id/submissions/:id/events", action: :create, as: "create_quiz_submission_events"
    end

    scope(controller: "quizzes/quiz_submission_questions") do
      get "/quiz_submissions/:quiz_submission_id/questions", action: :index, as: "quiz_submission_questions"
      post "/quiz_submissions/:quiz_submission_id/questions", action: :answer, as: "quiz_submission_question_answer"
      get "/quiz_submissions/:quiz_submission_id/questions/:id/formatted_answer", action: :formatted_answer, as: "quiz_submission_question_formatted_answer"
      get "/quiz_submissions/:quiz_submission_id/questions/:id", action: :show, as: "quiz_submission_question"
      put "/quiz_submissions/:quiz_submission_id/questions/:id/flag", action: :flag, as: "quiz_submission_question_flag"
      put "/quiz_submissions/:quiz_submission_id/questions/:id/unflag", action: :unflag, as: "quiz_submission_question_unflag"
    end

    scope(controller: "quizzes/quiz_ip_filters") do
      get "courses/:course_id/quizzes/:quiz_id/ip_filters", action: :index, as: "course_quiz_ip_filters"
    end

    scope(controller: "quizzes/quiz_statistics") do
      get "courses/:course_id/quizzes/:quiz_id/statistics", action: :index, as: "course_quiz_statistics"
    end

    scope(controller: "polling/polls") do
      get "polls", action: :index, as: "polls"
      post "polls", action: :create, as: "poll_create"
      get "polls/:id", action: :show, as: "poll"
      put "polls/:id", action: :update, as: "poll_update"
      delete "polls/:id", action: :destroy, as: "poll_destroy"
    end

    scope(controller: "polling/poll_choices") do
      get "polls/:poll_id/poll_choices", action: :index, as: "poll_choices"
      post "polls/:poll_id/poll_choices", action: :create, as: "poll_choices_create"
      get "polls/:poll_id/poll_choices/:id", action: :show, as: "poll_choice"
      put "polls/:poll_id/poll_choices/:id", action: :update, as: "poll_choice_update"
      delete "polls/:poll_id/poll_choices/:id", action: :destroy, as: "poll_choice_destroy"
    end

    scope(controller: "polling/poll_sessions") do
      get "polls/:poll_id/poll_sessions", action: :index, as: "poll_sessions"
      post "polls/:poll_id/poll_sessions", action: :create, as: "poll_sessions_create"
      get "polls/:poll_id/poll_sessions/:id", action: :show, as: "poll_session"
      put "polls/:poll_id/poll_sessions/:id", action: :update, as: "poll_session_update"
      delete "polls/:poll_id/poll_sessions/:id", action: :destroy, as: "poll_session_destroy"
      get "polls/:poll_id/poll_sessions/:id/open", action: :open, as: "poll_session_publish"
      get "polls/:poll_id/poll_sessions/:id/close", action: :close, as: "poll_session_close"

      get "poll_sessions/opened", action: :opened, as: "poll_sessions_opened"
      get "poll_sessions/closed", action: :closed, as: "poll_sessions_closed"
    end

    scope(controller: "polling/poll_submissions") do
      post "polls/:poll_id/poll_sessions/:poll_session_id/poll_submissions", action: :create, as: "poll_submissions_create"
      get "polls/:poll_id/poll_sessions/:poll_session_id/poll_submissions/:id", action: :show, as: "poll_submission"
    end

    scope(controller: "live_assessments/assessments") do
      get "courses/:course_id/live_assessments", action: :index, as: "course_live_assessments"
      post "courses/:course_id/live_assessments", action: :create, as: "course_live_assessment_create"
    end

    scope(controller: "live_assessments/results") do
      get "courses/:course_id/live_assessments/:assessment_id/results", action: :index, as: "course_live_assessment_results"
      post "courses/:course_id/live_assessments/:assessment_id/results", action: :create, as: "course_live_assessment_result_create"
    end

    scope(controller: "support_helpers/turnitin") do
      get "support_helpers/turnitin/md5", action: :md5
      get "support_helpers/turnitin/error2305", action: :error2305
      get "support_helpers/turnitin/shard", action: :shard
      get "support_helpers/turnitin/assignment", action: :assignment
      get "support_helpers/turnitin/pending", action: :pending
      get "support_helpers/turnitin/expired", action: :expired
      get "support_helpers/turnitin/refresh_lti_attachment", action: :lti_attachment
    end

    scope(controller: "support_helpers/plagiarism_platform") do
      get "support_helpers/plagiarism_platform/add_service", action: :add_service
      get "support_helpers/plagiarism_platform/resubmit_for_assignment/:assignment_id", action: :resubmit_for_assignment
    end

    scope(controller: "support_helpers/crocodoc") do
      get "support_helpers/crocodoc/shard", action: :shard
      get "support_helpers/crocodoc/submission", action: :submission
    end

    scope(controller: "support_helpers/submission_lifecycle_manage") do
      get "support_helpers/submission_lifecycle_manage/course", action: :course
    end

    scope(controller: "support_helpers/asset_processor") do
      get "support_helpers/asset_processor/submission_details", action: :submission_details
    end

    scope(controller: :outcome_groups_api) do
      %w[global account course].each do |context|
        prefix = ((context == "global") ? context : "#{context}s/:#{context}_id")
        unless context == "global"
          get "#{prefix}/outcome_groups", action: :index, as: "#{context}_outcome_groups"
          get "#{prefix}/outcome_group_links", action: :link_index, as: "#{context}_outcome_group_links"
        end
        get "#{prefix}/root_outcome_group", action: :redirect, as: "#{context}_redirect"
        get "#{prefix}/outcome_groups/account_chain", action: :account_chain, as: "#{context}_account_chain"
        get "#{prefix}/outcome_groups/:id", action: :show, as: "#{context}_outcome_group"
        put "#{prefix}/outcome_groups/:id", action: :update
        delete "#{prefix}/outcome_groups/:id", action: :destroy
        get "#{prefix}/outcome_groups/:id/outcomes", action: :outcomes, as: "#{context}_outcome_group_outcomes"
        get "#{prefix}/outcome_groups/:id/available_outcomes", action: :available_outcomes, as: "#{context}_outcome_group_available_outcomes"
        post "#{prefix}/outcome_groups/:id/outcomes", action: :link
        put "#{prefix}/outcome_groups/:id/outcomes/:outcome_id", action: :link, as: "#{context}_outcome_link"
        delete "#{prefix}/outcome_groups/:id/outcomes/:outcome_id", action: :unlink
        get "#{prefix}/outcome_groups/:id/subgroups", action: :subgroups, as: "#{context}_outcome_group_subgroups"
        post "#{prefix}/outcome_groups/:id/subgroups", action: :create
        post "#{prefix}/outcome_groups/:id/import", action: :import, as: "#{context}_outcome_group_import"
        post "#{prefix}/outcome_groups/:id/batch", action: :batch, as: "#{context}_outcome_group_batch"
      end
    end

    scope(controller: :outcomes_api) do
      get "outcomes/:id", action: :show, as: "outcome"
      put "outcomes/:id", action: :update
      delete "outcomes/:id", action: :destroy
      get "courses/:course_id/outcome_alignments", action: :outcome_alignments
    end

    scope(controller: :outcome_results) do
      get "courses/:course_id/outcome_rollups", action: :rollups, as: "course_outcome_rollups"
      get "courses/:course_id/outcome_results", action: :index, as: "course_outcome_results"
      post "courses/:course_id/assign_outcome_order", action: :outcome_order, as: "course_outcomes_order"
    end

    scope(controller: :outcomes_academic_benchmark_import_api) do
      # These can be uncommented when implemented
      # get  "global/outcomes_import",            action: :index
      # get  "global/outcomes_import/:id",        action: :show
      # put  "global/outcomes_import/:id",        action: :cancel
      # get  "global/outcomes_import/list/:guid", action: :list
      get  "global/outcomes_import/available",  action: :available
      post "global/outcomes_import",            action: :create
      get  "global/outcomes_import/migration_status/:migration_id", action: :migration_status
    end

    scope(controller: :group_categories) do
      resources :group_categories, except: [:index, :create]
      get "accounts/:account_id/group_categories", action: :index, as: "account_group_categories"
      get "courses/:course_id/group_categories", action: :index, as: "course_group_categories"
      post "accounts/:account_id/group_categories", action: :create
      post "courses/:course_id/group_categories", action: :create
      post "group_categories/:group_category_id/import", action: :import
      get "group_categories/:group_category_id/groups", action: :groups, as: "group_category_groups"
      get "group_categories/:group_category_id/users", action: :users, as: "group_category_users"
      get "group_categories/:group_category_id/export", action: :export, as: "group_category_export", defaults: { format: :csv }
      post "group_categories/:group_category_id/assign_unassigned_members", action: "assign_unassigned_members", as: "group_category_assign_unassigned_members"
      post "courses/:course_id/group_categories/bulk_manage_differentiation_tag", action: :bulk_manage_differentiation_tag
      post "courses/:course_id/group_categories/import_tags", action: :import_tags
    end

    scope(controller: :progress) do
      get "progress/:id", action: :show, as: "progress"
      post "progress/:id/cancel", action: :cancel
    end

    scope(controller: :app_center) do
      %w[course account].each do |context|
        prefix = "#{context}s/:#{context}_id/app_center"
        get  "#{prefix}/apps",                      action: :index,   as: "#{context}_app_center_apps"
        get  "#{prefix}/apps/:app_id/reviews",      action: :reviews, as: "#{context}_app_center_app_reviews"
        get  "#{prefix}/apps/:app_id/reviews/self", action: :review,  as: "#{context}_app_center_app_review"
        post "#{prefix}/apps/:app_id/reviews/self", action: :add_review
      end
    end

    scope(controller: :learn_platform) do
      prefix = "accounts/:account_id/learn_platform"
      get  "#{prefix}/products", action: :index
      get  "#{prefix}/products_categories", action: :index_by_category
      get  "#{prefix}/products/:id", action: :show
      get  "#{prefix}/filters", action: :filters
      get  "#{prefix}/organizations/:organization_salesforce_id/products", action: :index_by_organization
      get  "#{prefix}/custom_filters", action: :custom_filters
    end

    scope(controller: :feature_flags) do
      %w[course account user].each do |context|
        prefix = "#{context}s/:#{context}_id/features"
        get prefix.to_s, action: :index, as: "#{context}_features"
        get "#{prefix}/enabled", action: :enabled_features, as: "#{context}_enabled_features"
        get "#{prefix}/flags/:feature", action: :show
        put "#{prefix}/flags/:feature", action: :update
        delete "#{prefix}/flags/:feature", action: :delete
      end
      get "features/environment", action: :environment
    end

    scope(controller: :conferences) do
      %w[course group].each do |context|
        prefix = "#{context}s/:#{context}_id/conferences"
        get prefix, action: :index, as: "#{context}_conferences"
        post prefix.to_s, action: :create
        post "#{prefix}/:conference_id/recording_ready", action: :recording_ready, as: "#{context}_conferences_recording_ready"
      end

      get "conferences", action: :for_user, as: "conferences"
    end

    scope(controller: :custom_gradebook_columns_api) do
      prefix = "courses/:course_id/custom_gradebook_columns"
      get prefix, action: :index, as: "course_custom_gradebook_columns"
      post prefix, action: :create
      post "#{prefix}/reorder", action: :reorder, as: "custom_gradebook_columns_reorder"
      put "#{prefix}/:id", action: :update, as: "course_custom_gradebook_column"
      delete "#{prefix}/:id", action: :destroy
    end

    scope(controller: :custom_gradebook_column_data_api) do
      prefix = "courses/:course_id/custom_gradebook_columns/:id/data"
      get prefix, action: :index, as: "course_custom_gradebook_column_data"
      put "#{prefix}/:user_id", action: :update, as: "course_custom_gradebook_column_datum"
      put "courses/:course_id/custom_gradebook_column_data", action: :bulk_update, as: "course_custom_gradebook_column_bulk_data"
    end

    scope(controller: :content_exports_api) do
      %w[course group user].each do |context|
        context_prefix = "#{context.pluralize}/:#{context}_id"
        prefix = "#{context_prefix}/content_exports"
        get prefix, action: :index, as: "#{context}_content_exports"
        post prefix, action: :create
        get "#{prefix}/:id", action: :show
        put "#{prefix}/:id/fail", action: :fail
      end
      get "courses/:course_id/content_list", action: :content_list, as: "course_content_list"
      put "courses/:course_id/content_exports/:id", action: :update
    end

    scope(controller: :epub_exports) do
      get "courses/:course_id/epub_exports/:id", {
        action: :show
      }
      get "epub_exports", {
        action: :index
      }
      post "courses/:course_id/epub_exports", {
        action: :create
      }
    end

    scope(controller: :web_zip_exports) do
      get "courses/:course_id/web_zip_exports", action: :index, as: "web_zip_exports"
      get "courses/:course_id/web_zip_exports/:id", action: :show
    end

    scope(controller: :grading_standards_api) do
      get "courses/:course_id/grading_standards", action: :context_index
      get "accounts/:account_id/grading_standards", action: :context_index
      get "courses/:course_id/grading_standards/:grading_standard_id", action: :context_show
      get "accounts/:account_id/grading_standards/:grading_standard_id", action: :context_show
      post "accounts/:account_id/grading_standards", action: :create
      post "courses/:course_id/grading_standards", action: :create
    end

    get "/crocodoc_session", controller: "crocodoc_sessions", action: "show", as: :crocodoc_session
    get "/canvadoc_session", controller: "canvadoc_sessions", action: "show", as: :canvadoc_session
    post "/canvadoc_session", controller: "canvadoc_sessions", action: "create"

    scope(controller: :grading_period_sets) do
      get "accounts/:account_id/grading_period_sets", action: :index, as: :account_grading_period_sets
      post "accounts/:account_id/grading_period_sets", action: :create
      patch "accounts/:account_id/grading_period_sets/:id", action: :update, as: :account_grading_period_set
      delete "accounts/:account_id/grading_period_sets/:id", action: :destroy
    end

    scope(controller: :grading_periods) do
      # FIXME: This route will be removed/replaced with CNVS-27101
      get "accounts/:account_id/grading_periods", action: :index, as: :account_grading_periods

      get "courses/:course_id/grading_periods", action: :index, as: :course_grading_periods
      get "courses/:course_id/grading_periods/:id", action: :show, as: :course_grading_period
      patch "courses/:course_id/grading_periods/batch_update",
            action: :batch_update,
            as: :course_grading_period_batch_update
      put "courses/:course_id/grading_periods/:id", action: :update, as: :course_grading_period_update
      delete "courses/:course_id/grading_periods/:id", action: :destroy, as: :course_grading_period_destroy
      delete "accounts/:account_id/grading_periods/:id", action: :destroy, as: :account_grading_period_destroy

      patch "grading_period_sets/:set_id/grading_periods/batch_update",
            action: :batch_update,
            as: :grading_period_set_periods_update
    end

    scope(controller: :usage_rights) do
      %w[course group user].each do |context|
        content_prefix = "#{context.pluralize}/:#{context}_id"
        put "#{content_prefix}/usage_rights", action: :set_usage_rights
        delete "#{content_prefix}/usage_rights", action: :remove_usage_rights
        get "#{content_prefix}/content_licenses", action: :licenses
      end
    end

    scope(controller: "bookmarks/bookmarks") do
      get "users/self/bookmarks/", action: :index, as: :bookmarks
      get "users/self/bookmarks/:id", action: :show
      post "users/self/bookmarks", action: :create
      delete "users/self/bookmarks/:id", action: :destroy
      put "users/self/bookmarks/:id", action: :update
    end

    scope(controller: :course_nicknames) do
      get "users/self/course_nicknames", action: :index, as: :course_nicknames
      get "users/self/course_nicknames/:course_id", action: :show
      put "users/self/course_nicknames/:course_id", action: :update
      delete "users/self/course_nicknames/:course_id", action: :delete
      delete "users/self/course_nicknames", action: :clear
    end

    scope(controller: :shared_brand_configs) do
      post "accounts/:account_id/shared_brand_configs", action: :create
      put "accounts/:account_id/shared_brand_configs/:id", action: :update
      delete "shared_brand_configs/:id", action: :destroy
    end

    scope(controller: :errors) do
      post "error_reports", action: :create
    end

    scope(controller: :jwts) do
      post "jwts", action: :create
      post "jwts/refresh", action: :refresh
    end

    scope(controller: :inst_access_tokens) do
      post "inst_access_tokens", action: :create
    end

    scope(controller: :gradebook_settings) do
      put "courses/:course_id/gradebook_settings", action: :update, as: :course_gradebook_settings_update
    end

    scope(controller: :announcements_api) do
      get "announcements", action: :index, as: :announcements
    end

    scope(controller: :release_notes) do
      get "release_notes", action: :index, as: :release_notes
      post "release_notes", action: :create
      get "release_notes/latest", action: :latest
      get "release_notes/unread_count", action: :unread_count
      put "release_notes/:id", action: :update
      delete "release_notes/:id", action: :destroy
      put "release_notes/:id/published", action: :publish
      delete "release_notes/:id/published", action: :unpublish
    end

    scope(controller: :rubrics_api) do
      get "rubrics/upload_template", action: "upload_template", as: "rubrics_account_upload_template"
      post "courses/:course_id/rubrics/download_rubrics", action: "download_rubrics", as: "rubrics_account_download_rubrics"
      post "accounts/:account_id/rubrics/download_rubrics", action: "download_rubrics", as: "rubrics_course_download_rubrics"
      get "accounts/:account_id/rubrics", action: :index, as: :account_rubrics
      get "accounts/:account_id/rubrics/:id", action: :show
      get "courses/:course_id/rubrics", action: :index, as: :course_rubrics
      get "courses/:course_id/rubrics/:id", action: :show
      get "courses/:course_id/rubrics/:id/used_locations", action: "used_locations", as: "rubrics_course_used_locations"
      get "accounts/:account_id/rubrics/:id/used_locations", action: "used_locations", as: "rubrics_account_used_locations"
      post "courses/:course_id/rubrics/upload", action: "upload", as: "rubrics_course_upload"
      post "accounts/:account_id/rubrics/upload", action: "upload", as: "rubrics_account_upload"
      get "courses/:course_id/rubrics/upload/:id", action: "upload_status", as: "rubrics_course_upload_status"
      get "accounts/:account_id/rubrics/upload/:id", action: "upload_status", as: "rubrics_account_upload_status"
      get "courses/:course_id/rubrics/upload/:id/rubrics", action: "rubrics_by_import_id", as: "rubrics_course_upload_rubrics"
      get "accounts/:account_id/rubrics/upload/:id/rubrics", action: "rubrics_by_import_id", as: "rubrics_account_upload_rubrics"
      post "courses/:course_id/rubrics", controller: :rubrics, action: :create
      put "courses/:course_id/rubrics/:id", controller: :rubrics, action: :update
      delete "courses/:course_id/rubrics/:id", controller: :rubrics, action: :destroy
    end

    scope(controller: :rubric_associations) do
      post "courses/:course_id/rubric_associations", action: :create
      put "courses/:course_id/rubric_associations/:id", action: :update
      delete "courses/:course_id/rubric_associations/:id", action: :destroy
    end

    scope(controller: :rubric_assessment_api) do
      post "courses/:course_id/rubric_associations/:rubric_association_id/rubric_assessments", controller: :rubric_assessments, action: :create
      put "courses/:course_id/rubric_associations/:rubric_association_id/rubric_assessments/:id", controller: :rubric_assessments, action: :update
      delete "courses/:course_id/rubric_associations/:rubric_association_id/rubric_assessments/:id", controller: :rubric_assessments, action: :destroy
    end

    scope(controller: "master_courses/master_templates") do
      get "courses/:course_id/blueprint_templates/:template_id", action: :show
      get "courses/:course_id/blueprint_templates/:template_id/associated_courses", action: :associated_courses, as: :course_blueprint_associated_courses
      put "courses/:course_id/blueprint_templates/:template_id/update_associations", action: :update_associations
      get "courses/:course_id/blueprint_templates/:template_id/unsynced_changes", action: :unsynced_changes, as: :course_blueprint_unsynced_changes

      post "courses/:course_id/blueprint_templates/:template_id/migrations", action: :queue_migration
      get "courses/:course_id/blueprint_templates/:template_id/migrations", action: :migrations_index, as: :course_blueprint_migrations
      get "courses/:course_id/blueprint_templates/:template_id/migrations/:id", action: :migrations_show
      get "courses/:course_id/blueprint_templates/:template_id/migrations/:id/details", action: :migration_details

      put "courses/:course_id/blueprint_templates/:template_id/restrict_item", action: :restrict_item

      get "courses/:course_id/blueprint_subscriptions", action: :subscriptions_index, as: :course_blueprint_subscriptions
      get "courses/:course_id/blueprint_subscriptions/:subscription_id/migrations", action: :imports_index, as: :course_blueprint_imports
      get "courses/:course_id/blueprint_subscriptions/:subscription_id/migrations/:id", action: :imports_show
      get "courses/:course_id/blueprint_subscriptions/:subscription_id/migrations/:id/details", action: :import_details
    end

    scope(controller: :late_policy) do
      get "courses/:id/late_policy", action: :show
      post "courses/:id/late_policy", action: :create
      patch "courses/:id/late_policy", action: :update
    end

    scope(controller: :planner) do
      get "planner/items", action: :index, as: :planner_items
      get "users/:user_id/planner/items", action: :index, as: :user_planner_items
    end

    scope(controller: :planner_overrides) do
      get "planner/overrides", action: :index, as: :planner_overrides
      get "planner/overrides/:id", action: :show
      put "planner/overrides/:id", action: :update
      post "planner/overrides", action: :create
      delete "planner/overrides/:id", action: :destroy
    end

    scope(controller: :planner_notes) do
      get "planner_notes", action: :index, as: :planner_notes
      get "planner_notes/:id", action: :show, as: :planner_notes_show
      put "planner_notes/:id", action: :update
      post "planner_notes", action: :create
      delete "planner_notes/:id", action: :destroy
    end

    scope(controller: :content_shares) do
      post "users/:user_id/content_shares", action: :create
      get "users/:user_id/content_shares/sent", action: :index, defaults: { list: "sent" }, as: :user_sent_content_shares
      get "users/:user_id/content_shares/received", action: :index, defaults: { list: "received" }, as: :user_received_content_shares
      get "users/:user_id/content_shares/unread_count", action: :unread_count
      get "users/:user_id/content_shares/:id", action: :show
      delete "users/:user_id/content_shares/:id", action: :destroy
      post "users/:user_id/content_shares/:id/add_users", action: :add_users
      put "users/:user_id/content_shares/:id", action: :update
    end

    scope(controller: :csp_settings) do
      %w[course account].each do |context|
        get "#{context.pluralize}/:#{context}_id/csp_settings", action: :get_csp_settings
        put "#{context.pluralize}/:#{context}_id/csp_settings", action: :set_csp_setting
      end
      put "accounts/:account_id/csp_settings/lock", action: :set_csp_lock
      post "accounts/:account_id/csp_settings/domains", action: :add_domain
      post "accounts/:account_id/csp_settings/domains/batch_create", action: :add_multiple_domains
      delete "accounts/:account_id/csp_settings/domains", action: :remove_domain
    end

    scope(controller: :media_objects) do
      put "media_objects/:media_object_id", action: "update_media_object", as: :update_media_object
      post "media_objects", action: "create_media_object", as: :create_media_object
      put "media_attachments/:attachment_id", action: "update_media_object", as: :update_media_attachment
      post "media_attachments", action: "create_media_object", as: :create_media_attachment
    end

    scope(controller: :media_tracks) do
      get "media_objects/:media_object_id/media_tracks", action: "index", as: :list_media_tracks
      put "media_objects/:media_object_id/media_tracks", action: "update", as: :update_media_tracks

      get "media_attachments/:attachment_id/media_tracks", action: "index", as: :list_media_attachment_tracks
      put "media_attachments/:attachment_id/media_tracks", action: "update", as: :update_media_attachment_tracks
    end

    scope(controller: "conditional_release/rules") do
      # TODO: can rearrange so assignment is in path if desired once we're no longer maintaining backwards compat
      get "courses/:course_id/mastery_paths/rules", action: "index"
      get "courses/:course_id/mastery_paths/rules/:id", action: "show"
      post "courses/:course_id/mastery_paths/rules", action: "create"
      put "courses/:course_id/mastery_paths/rules/:id", action: "update"
      delete "courses/:course_id/mastery_paths/rules/:id", action: "destroy"
    end

    scope(controller: "conditional_release/stats") do
      # TODO: can rearrange so assignment is in path if desired once we're no longer maintaining backwards compat
      get "courses/:course_id/mastery_paths/stats/students_per_range", action: "students_per_range"
      get "courses/:course_id/mastery_paths/stats/student_details", action: "student_details"
    end

    scope(controller: :history) do
      get "users/:user_id/history", action: "index", as: :user_history
    end

    scope(controller: :gradebooks) do
      put "courses/:course_id/update_final_grade_overrides", action: "update_final_grade_overrides"
      put "courses/:course_id/apply_score_to_ungraded_submissions", action: "apply_score_to_ungraded_submissions"
    end

    scope(controller: :course_paces) do
      post "courses/:course_id/course_pacing", action: :create
      get "courses/:course_id/course_pacing/new", action: :new
      get "courses/:course_id/course_pacing/:id", action: :api_show
      put "courses/:course_id/course_pacing/:id", action: :update
      delete "courses/:course_id/course_pacing/:id", action: :destroy
      post "courses/:course_id/course_pacing/:id/publish", action: :publish
      post "courses/:course_id/course_pacing/compress_dates", action: :compress_dates
      post "courses/:course_id/course_pacing/bulk_create_enrollment_paces", action: :bulk_create_enrollment_paces
    end

    scope(controller: :blackout_dates) do
      get "courses/:course_id/blackout_dates", action: :index
      get "accounts/:account_id/blackout_dates", action: :index
      post "courses/:course_id/blackout_dates", action: :create
      post "accounts/:account_id/blackout_dates", action: :create
      get "courses/:course_id/blackout_dates/new", action: :new
      get "accounts/:account_id/blackout_dates/new", action: :new
      get "courses/:course_id/blackout_dates/:id", action: :show
      get "accounts/:account_id/blackout_dates/:id", action: :show
      put "courses/:course_id/blackout_dates/:id", action: :update
      put "accounts/:account_id/blackout_dates/:id", action: :update
      delete "courses/:course_id/blackout_dates/:id", action: :destroy
      delete "accounts/:account_id/blackout_dates/:id", action: :destroy
      put "courses/:course_id/blackout_dates", action: :bulk_update
    end

    scope(controller: :eportfolios_api) do
      get "users/:user_id/eportfolios", action: :index, as: :eportfolios
      get "eportfolios/:id", action: :show
      delete "eportfolios/:id", action: :delete
      get "eportfolios/:eportfolio_id/pages", action: :pages, as: :eportfolio_pages
      put "eportfolios/:eportfolio_id/moderate", action: :moderate
      put "users/:user_id/eportfolios", action: :moderate_all
      put "eportfolios/:eportfolio_id/restore", action: :restore
    end

    scope(controller: "course_pacing/section_paces_api") do
      get "courses/:course_id/sections/:course_section_id/pace", action: :show, as: :section_pace
      post "courses/:course_id/sections/:course_section_id/paces", action: :create, as: :new_section_pace
      patch "courses/:course_id/sections/:course_section_id/pace", action: :update, as: :patch_section_pace
      delete "courses/:course_id/sections/:course_section_id/pace", action: :delete, as: :delete_section_pace
    end

    scope(controller: "course_pacing/student_enrollment_paces_api") do
      get "courses/:course_id/student_enrollments/:student_enrollment_id/pace", action: :show, as: :student_enrollment_pace
      post "courses/:course_id/student_enrollments/:student_enrollment_id/paces", action: :create, as: :new_student_enrollment_pace
      patch "courses/:course_id/student_enrollments/:student_enrollment_id/pace", action: :update, as: :patch_student_enrollment_pace
      delete "courses/:course_id/student_enrollments/:student_enrollment_id/pace", action: :delete, as: :delete_student_enrollment_pace
    end

    scope(controller: "course_pacing/bulk_student_enrollment_paces_api") do
      get "courses/:course_id/bulk_student_enrollments/student_bulk_pace_edit_view", action: :student_bulk_pace_edit_view, as: :student_bulk_pace_edit_view
    end

    scope(controller: "course_pacing/pace_contexts_api") do
      get "courses/:course_id/pace_contexts", action: :index, as: :pace_contexts
    end

    scope(controller: "smart_search") do
      get "courses/:course_id/smartsearch", action: :search, as: :course_smart_search_query
      get "courses/:course_id/smartsearch/log", action: :log
      get "courses/:course_id/smartsearch/index_status", action: :index_status
      # TODO: add account level search
    end

    scope(controller: :what_if_grades_api) do
      put "submissions/:id/what_if_grades", action: :update
      put "courses/:course_id/what_if_grades/reset", action: :reset_for_student_course
    end

    scope(controller: :plugins) do
      put "plugins/:id", action: :update
      get "plugins/:id", action: :show
    end

    scope(controller: :rich_content_api) do
      post "rich_content/generate", action: :generate
    end

    scope(controller: :block_editor_templates_api) do
      get "courses/:course_id/block_editor_templates", action: :index
      post "courses/:course_id/block_editor_templates", action: :create
      put "courses/:course_id/block_editor_templates/:id", action: :update
      delete "courses/:course_id/block_editor_templates/:id", action: :destroy
      post "courses/:course_id/block_editor_templates/:id/publish", action: :publish
      get "courses/:course_id/block_editor_templates/can_edit", action: :can_edit
    end

    scope(controller: :career_experience) do
      get "career/experience_summary", action: :experience_summary
      post "career/switch_experience", action: :switch_experience
      post "career/switch_role", action: :switch_role
    end
  end

  # this is not a "normal" api endpoint in the sense that it is not documented or
  # generally available to hosted customers. it also does not respect the normal
  # pagination options; however, jobs_controller already accepts `limit` and `offset`
  # paramaters and defines a sane default limit
  ApiRouteSet::V1.draw(self) do
    scope(controller: :jobs) do
      get "jobs", action: :index
      get "jobs/:id", action: :show
      post "jobs/batch_update", action: :batch_update
    end

    # jobs_v2 actually does do regular pagination, but the comments above
    # otherwise still apply
    scope(controller: :jobs_v2) do
      get "jobs2/:bucket/by_:group/search", action: :search
      get "jobs2/:bucket/by_:group", action: :grouped_info, as: :jobs_grouped_info
      get "jobs2/:bucket", action: :list, as: :jobs_list, constraints: { bucket: /running|queued|future|failed/ }
      get "jobs2/clusters", action: :clusters, as: :job_clusters
      get "jobs2/:id", action: :lookup, constraints: { id: /\d+/ }
      post "jobs2/:id/requeue", action: :requeue
      put "jobs2/manage", action: :manage
      put "jobs2/unstuck", action: :unstuck
      get "jobs2/throttle/check", action: :throttle_check
      put "jobs2/throttle", action: :throttle
      get "jobs2/stuck/strands", action: :stuck_strands, as: :jobs_stuck_strands
      get "jobs2/stuck/singletons", action: :stuck_singletons, as: :jobs_stuck_singletons
    end
  end

  # this is not a "normal" api endpoint in the sense that it is not documented
  # or called directly, it's used as the redirect in the file upload process
  # for local files. it also doesn't use the normal oauth authentication
  # system, so we can't put it in the api uri namespace.
  post "files_api" => "files#api_create", :as => :api_v1_files_create

  get "login/oauth2/auth" => "oauth2_provider#auth", :as => :oauth2_auth
  post "login/oauth2/token" => "oauth2_provider#token", :as => :oauth2_token
  get "login/oauth2/confirm" => "oauth2_provider#confirm", :as => :oauth2_auth_confirm
  post "login/oauth2/accept" => "oauth2_provider#accept", :as => :oauth2_auth_accept
  get "login/oauth2/deny" => "oauth2_provider#deny", :as => :oauth2_auth_deny
  delete "login/oauth2/token" => "oauth2_provider#destroy", :as => :oauth2_logout
  get "login/oauth2/jwks" => "security#jwks", :as => :oauth2_jwks

  get "post_message_forwarding", controller: "lti/platform_storage", action: :post_message_forwarding, as: :lti_post_message_forwarding

  get "lti/tool_default_icon" => "lti/tool_default_icon#show"

  ApiRouteSet.draw(self, "/api/lti/v1") do
    post "tools/:tool_id/grade_passback", controller: :lti_api, action: :grade_passback, as: "lti_grade_passback_api"
    post "tools/:tool_id/ext_grade_passback", controller: :lti_api, action: :legacy_grade_passback, as: "blti_legacy_grade_passback_api"
    post "xapi/:token", controller: :lti_api, action: :xapi_service, as: "lti_xapi"
    post "caliper/:token", controller: :lti_api, action: :caliper_service, as: "lti_caliper"
    post "logout_service/:token", controller: :lti_api, action: :logout_service, as: "lti_logout_service"
    post "turnitin/outcomes_placement/:tool_id", controller: :lti_api, action: :turnitin_outcomes_placement, as: "lti_turnitin_outcomes_placement"
  end

  ApiRouteSet.draw(self, "/api/lti") do
    scope(controller: "lti/tool_configurations_api") do
      put "developer_keys/:developer_key_id/tool_configuration", action: :update
      post "accounts/:account_id/developer_keys/tool_configuration", action: :create
      delete "developer_keys/:developer_key_id/tool_configuration", action: :destroy

      %w[account course].each do |context|
        get "#{context}s/:#{context}_id/developer_keys/:developer_key_id/tool_configuration", action: :show, as: "#{context}_show_tool_configuration"
      end
    end

    scope(controller: "lti/subscriptions_api") do
      post "subscriptions", action: :create
      delete "subscriptions/:id", action: :destroy
      get "subscriptions/:id", action: :show
      put "subscriptions/:id", action: :update
      get "subscriptions", action: :index
    end

    scope(controller: "lti/users_api") do
      get "users/:id", action: :show
      get "groups/:group_id/users", action: :group_index, as: "lti_user_group_index"
    end

    scope(controller: "lti/plagiarism_assignments_api") do
      get "assignments/:assignment_id", action: :show
    end

    scope(controller: "lti/ims/authentication") do
      post "authorize_redirect", action: :authorize_redirect
      get "authorize_redirect", action: :authorize_redirect, as: "lti_authorize_redirect"
      get "authorize", action: :authorize, as: :lti_1_3_authorization
    end

    %w[course account].each do |context|
      prefix = "#{context}s/:#{context}_id"

      post "#{prefix}/authorize", controller: "lti/ims/authorization", action: :authorize, as: "#{context}_lti_oauth2_authorize"
      get  "#{prefix}/tool_consumer_profile(/:tool_consumer_profile_id)",
           controller: "lti/ims/tool_consumer_profile",
           action: "show",
           as: "#{context}_tool_consumer_profile"
      post "#{prefix}/tool_proxy",
           controller: "lti/ims/tool_proxy",
           action: :re_reg,
           as: "re_reg_#{context}_lti_tool_proxy",
           constraints: Lti::ReRegConstraint.new
      post "#{prefix}/tool_proxy",
           controller: "lti/ims/tool_proxy",
           action: :create,
           as: "create_#{context}_lti_tool_proxy"
      get "#{prefix}/jwt_token", controller: "external_tools", action: :jwt_token
      get "tool_proxy/:tool_proxy_guid/#{prefix}/tool_setting", controller: "lti/ims/tool_setting", action: :show, as: "show_#{context}_tool_setting"
      get "tool_proxy/:tool_proxy_guid/#{prefix}/resource_link_id/:resource_link_id/tool_setting", controller: "lti/ims/tool_setting", action: :show, as: "show_#{context}_resource_link_id_tool_setting"
      put "tool_proxy/:tool_proxy_guid/#{prefix}/tool_setting", controller: "lti/ims/tool_setting", action: :update, as: "update_#{context}_tool_setting"
      put "tool_proxy/:tool_proxy_guid/#{prefix}/resource_link_id/:resource_link_id/tool_setting", controller: "lti/ims/tool_setting", action: :update, as: "update_#{context}_update_resource_link_id_tool_setting"
    end
    # Tool Setting Services
    get "tool_settings/:tool_setting_id", controller: "lti/ims/tool_setting", action: :show, as: :show_lti_tool_settings
    get "tool_proxy/:tool_proxy_guid/tool_setting", controller: "lti/ims/tool_setting", action: :show, as: :show_tool_proxy_lti_tool_settings
    put "tool_settings/:tool_setting_id", controller: "lti/ims/tool_setting", action: :update, as: :update_lti_tool_settings
    put "tool_proxy/:tool_proxy_guid/tool_setting", controller: "lti/ims/tool_setting", action: :update, as: :update_tool_proxy_lti_tool_settings

    # Tool Proxy Services
    get "tool_proxy/:tool_proxy_guid", controller: "lti/ims/tool_proxy", action: :show, as: "show_lti_tool_proxy"

    # Membership Service
    get "courses/:course_id/membership_service", controller: "lti/membership_service", action: :course_index, as: :course_membership_service
    get "groups/:group_id/membership_service", controller: "lti/membership_service", action: :group_index, as: :group_membership_service

    # Submissions Service
    scope(controller: "lti/submissions_api") do
      get "assignments/:assignment_id/submissions/:submission_id", action: :show
      get "assignments/:assignment_id/submissions/:submission_id/history", action: :history
      get "assignments/:assignment_id/submissions/:submission_id/attachment/:attachment_id", action: :attachment, as: :lti_submission_attachment_download
    end

    # Originality Report Service
    scope(controller: "lti/originality_reports_api") do
      post "assignments/:assignment_id/submissions/:submission_id/originality_report", action: :create
      put "assignments/:assignment_id/submissions/:submission_id/originality_report/:id", action: :update
      put "assignments/:assignment_id/files/:file_id/originality_report", action: :update
      get "assignments/:assignment_id/submissions/:submission_id/originality_report/:id", action: :show
      get "assignments/:assignment_id/files/:file_id/originality_report", action: :show
    end

    # Line Item Service (LTI AGS)
    scope(controller: "lti/ims/line_items") do
      post "courses/:course_id/line_items", action: :create, as: :lti_line_item_create
      get "courses/:course_id/line_items/:id", action: :show, as: :lti_line_item_show
      get "courses/:course_id/line_items", action: :index, as: :lti_line_item_index
      put "courses/:course_id/line_items/:id", action: :update, as: :lti_line_item_edit
      delete "courses/:course_id/line_items/:id", action: :destroy, as: :lti_line_item_delete
    end

    # Scores Service (LTI AGS)
    scope(controller: "lti/ims/scores") do
      post "courses/:course_id/line_items/:line_item_id/scores", action: :create, as: :lti_result_create
    end

    # Result Service (LTI AGS)
    scope(controller: "lti/ims/results") do
      get "courses/:course_id/line_items/:line_item_id/results/:id", action: :show, as: :lti_result_show
      get "courses/:course_id/line_items/:line_item_id/results", action: :index
    end

    # Progress Service (LTI AGS)
    scope(controller: "lti/ims/progress") do
      get "courses/:course_id/progress/:id", action: :show, as: :lti_progress_show
    end

    # Asset Service & Asset Report Service (LTI Asset Processor Specs)
    scope(controller: "lti/ims/asset_processor") do
      post "asset_processors/:asset_processor_id/reports", action: :create_report, as: :lti_asset_processor_create_report
      get "asset_processors/:asset_processor_id/assets/:asset_id", action: :lti_asset_show, as: :lti_asset_processor_asset_show
    end

    # 1Edtech (IMS) LTI Asset Processor Eula service
    scope(controller: "lti/ims/asset_processor_eula") do
      put "asset_processor_eulas/:context_external_tool_id/deployment", action: :update_tool_eula, as: :update_tool_eula
      delete "asset_processor_eulas/:context_external_tool_id/user", action: :delete_acceptances, as: :delete_tool_eula_acceptances
      post "asset_processor_eulas/:context_external_tool_id/user", action: :create_acceptance, as: :create_user_eula_acceptance
    end

    # Asset Processor internal endpoints
    scope(controller: "lti/asset_processor") do
      post "asset_processors/:asset_processor_id/notices/:student_id/attempts/:attempt", action: :resubmit_notice, as: :lti_asset_processor_notice_resubmit
    end

    # Dynamic Registration Service
    scope(controller: "lti/ims/dynamic_registration") do
      get "accounts/:account_id/registration_token", action: :registration_token
      get "accounts/:account_id/registrations/uuid/:registration_uuid", action: :ims_registration_by_uuid
      get "accounts/:account_id/lti_registrations/uuid/:registration_uuid", action: :lti_registration_by_uuid
      get "accounts/:account_id/registrations/:registration_id", action: :show
      put "accounts/:account_id/registrations/:registration_id/overlay", action: :update_registration_overlay
      get "accounts/:account_id/dr_iframe", action: :dr_iframe
      get "registrations/:registration_id/view", action: :registration_view, as: :lti_registration_config
      post "registrations", action: :create, as: :create_lti_registration
    end

    # Public JWK Service
    scope(controller: "lti/public_jwk") do
      put "/developer_key/update_public_jwk", action: :update, as: :public_jwk_update
    end

    # Context External Tools Service
    scope(controller: "lti/account_external_tools") do
      post "/accounts/:account_id/external_tools", action: :create, as: :account_external_tools_create
      get "/accounts/:account_id/external_tools/:external_tool_id", action: :show, as: :account_external_tools_show
      get "/accounts/:account_id/external_tools", action: :index, as: :account_external_tools_index
      delete "/accounts/:account_id/external_tools/:external_tool_id", action: :destroy, as: :account_external_tools_destroy
    end

    # Data Services Service
    scope(controller: "lti/data_services") do
      post "/accounts/:account_id/data_services", action: :create, as: :data_services_create
      get "/accounts/:account_id/data_services/:id", action: :show, as: :data_services_show
      put "/accounts/:account_id/data_services/:id", action: :update, as: :data_services_update
      get "/accounts/:account_id/data_services", action: :index, as: :data_services_index
      get "/accounts/:account_id/event_types", action: :event_types_index, as: :data_services_event_types
      delete "/accounts/:account_id/data_services/:id", action: :destroy, as: :data_services_destroy
    end

    # Account Lookup service
    scope(controller: "lti/account_lookup") do
      get "/accounts/:account_id", action: :show
    end

    # Names and Roles Provisioning (NRPS) v2 Service
    scope(controller: "lti/ims/names_and_roles") do
      get "courses/:course_id/names_and_roles", controller: "lti/ims/names_and_roles", action: :course_index, as: :course_names_and_roles
      get "groups/:group_id/names_and_roles", controller: "lti/ims/names_and_roles", action: :group_index, as: :group_names_and_roles
    end

    # 1Edtech (IMS) LTI Platform Notification service (PNS)
    scope(controller: "lti/ims/notice_handlers") do
      get "notice-handlers/:context_external_tool_id", action: :index, as: :lti_notice_handlers
      put "notice-handlers/:context_external_tool_id", action: :update, as: :update_lti_notice_handlers
    end

    # Security
    scope(controller: "security") do
      get "security/jwks", action: :jwks, as: :lti_jwks
      get "security/openid-configuration", action: :openid_configuration, as: :openid_configuration
    end

    # Feature Flags
    scope(controller: "lti/feature_flags") do
      %w[course account].each do |context|
        prefix = "#{context}s/:#{context}_id"
        get "/#{prefix}/feature_flags/:feature", action: :show
      end
    end

    # LTI Access Tokens (Site Admin only)
    get "lti_2_token", controller: "lti/token", action: :lti_2_token, as: :lti_2_token_site_admin
    get "advantage_token", controller: "lti/token", action: :advantage_access_token, as: :lti_advantage_token_site_admin
  end

  ApiRouteSet.draw(self, "/api/sis") do
    scope(controller: :sis_api) do
      get "accounts/:account_id/assignments", action: "sis_assignments", as: :sis_account_assignments
      get "courses/:course_id/assignments", action: "sis_assignments", as: :sis_course_assignments
    end
    scope(controller: :disable_post_to_sis_api) do
      put "courses/:course_id/disable_post_to_sis", action: "disable_post_to_sis", as: :disable_post_to_sis_course_assignments
    end
  end
end
