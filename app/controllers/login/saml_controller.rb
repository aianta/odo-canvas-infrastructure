# frozen_string_literal: true

#
# Copyright (C) 2015 - present Instructure, Inc.
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
#

class Login::SamlController < ApplicationController
  include Login::Shared

  protect_from_forgery except: [:create, :destroy], with: :exception

  before_action :forbid_on_files_domain
  before_action :run_login_hooks, only: [:new, :create]
  before_action :fix_ms_office_redirects, only: :new

  def new
    aac
    increment_statsd(:attempts)
    redirect_to aac.generate_authn_request_redirect(
      host: request.host_with_port,
      relay_state: forced_relay_state,
      force_login: force_login_after_logout? ||
       session[:parent_registration] ||
       Canvas::Plugin.value_to_boolean(params[:force_login])
    )
  end

  def forced_relay_state
    Rails.env.development? && params[:RelayState]
  end

  def create
    login_error_message = t("There was a problem logging in at %{institution}",
                            institution: @domain_root_account.display_name)

    response, relay_state = SAML2::Bindings::HTTP_POST.decode(request.request_parameters)
    unless response.is_a?(SAML2::Response)
      # something confusing and wrong has happened
      logger.error "[SAML] Attempted invalid SAML operation via login endpoint... #{response.class.name}"
      return render status: :bad_request, plain: "Invalid SAML operation for this endpoint: #{response.class.name}"
    end

    issuer = response.issuer&.id || response.assertions.first&.issuer&.id

    aac = @domain_root_account.authentication_providers.active
                              .where(auth_type: "saml")
                              .where(idp_entity_id: issuer)
                              .first
    tags = { idp_initiated: true } unless response.in_response_to
    increment_statsd(:attempts, tags:)
    if aac.nil?
      logger.error "Attempted SAML login for #{issuer} on account without that IdP"
      flash[:delegated_message] = if @domain_root_account.auth_discovery_url
                                    t("Canvas did not recognize your identity provider")
                                  elsif response.issuer
                                    t("Canvas is not configured to receive logins from %{issuer}.", issuer:)
                                  else
                                    t("The institution you logged in from is not configured on this account.")
                                  end
      increment_statsd(:failure, reason: :wrong_idp)
      return redirect_to login_url
    end

    debugging = if aac.debugging?
                  if response.in_response_to
                    aac.debug_get(:request_id) == response.in_response_to
                  else
                    aac.debug_set(:request_id, t("IdP Initiated"), overwrite: false)
                  end
                end
    encrypted_xml = response.to_s if debugging

    aac.sp_metadata(request.host_with_port).valid_response?(response,
                                                            aac.idp_metadata,
                                                            ignore_audience_condition: aac.settings["ignore_audience_condition"])

    if debugging
      aac.debug_set(:debugging, t("debug.redirect_from_idp", "Received LoginResponse from IdP"))
      aac.debug_set(:idp_response_encoded, params[:SAMLResponse])
      aac.debug_set(:idp_response_xml_encrypted, encrypted_xml)
      aac.debug_set(:idp_response_xml_decrypted, response.to_s)
      aac.debug_set(:idp_in_response_to, response.try(:in_response_to))
      aac.debug_set(:idp_login_destination, response.destination)
      aac.debug_set(:login_to_canvas_success, "false")
    end

    assertion = response.assertions.first
    begin
      provider_attributes = assertion&.attribute_statements&.first.to_h
    rescue
      # yes, they could be _that_ busted that we put an unconditional rescue here.
      {}
    end
    subject_name_id = assertion&.subject&.name_id
    unique_id = if aac.login_attribute == "NameID"
                  subject_name_id&.id
                else
                  provider_attributes[aac.login_attribute]
                end
    if unique_id && aac.strip_domain_from_login_attribute?
      unique_id = unique_id.split("@", 2)[0]
    end

    logger.info "Attempting SAML2 login for #{aac.login_attribute} #{unique_id} in account #{@domain_root_account.id}"

    unless response.errors.empty?
      if debugging
        aac.debug_set(:is_valid_login_response, "false")
        aac.debug_set(:login_response_validation_error, response.errors.join("\n"))
      end
      logger.error "Failed to verify SAML signature: #{response.errors.join("\n")}"
      flash[:delegated_message] = login_error_message
      increment_statsd(:failure, reason: :invalid)
      return redirect_to login_url
    end

    aac.debug_set(:is_valid_login_response, "true") if debugging

    # for parent using self-registration to observe a student
    # the student is logged out after validation
    # and registration process resumed
    if session[:parent_registration]
      expected_unique_id = session[:parent_registration][:observee][:unique_id]
      session[:parent_registration][:unique_id_match] = (expected_unique_id == unique_id)
      saml = ExternalAuthObservation::SAML.new(@domain_root_account, request, response)
      redirect_to saml.logout_url
      return
    end

    reset_session_for_login

    pseudonym =
      @domain_root_account.pseudonyms.for_auth_configuration(unique_id, aac, include_suspended: true)

    if !pseudonym && aac.jit_provisioning?
      pseudonym = aac.provision_user(unique_id, provider_attributes)
    elsif pseudonym && !pseudonym.suspended?
      aac.apply_federated_attributes(pseudonym, provider_attributes)
    end

    if pseudonym && !pseudonym.suspended? && (user = pseudonym.login_assertions_for_user)
      # Successful login and we have a user
      @domain_root_account.pseudonyms.scoping do
        PseudonymSession.create!(pseudonym, false)
      end

      if debugging
        aac.debug_set(:login_to_canvas_success, "true")
        aac.debug_set(:logged_in_user_id, user.id)
      end

      session[:saml_unique_id] = unique_id
      session[:name_id] = subject_name_id&.id
      session[:name_identifier_format] = subject_name_id&.format
      session[:name_qualifier] = subject_name_id&.name_qualifier
      session[:sp_name_qualifier] = subject_name_id&.sp_name_qualifier
      session[:session_index] = assertion.authn_statements.first&.session_index
      session[:login_aac] = aac.id

      Login::Shared.set_return_to_from_provider(request, session, pseudonym, @domain_root_account, relay_state)
      pseudonym.infer_auth_provider(aac)
      successful_login(user, pseudonym)
    else
      message = "Received SAML login request for unknown user: #{unique_id}"
      logger.warn message
      aac.debug_set(:canvas_login_fail_message, message) if debugging
      redirect_to_unknown_user_url(t("Canvas doesn't have an account for user: %{user}",
                                     user: unique_id))
      increment_statsd(:failure, reason: :unknown_user)
    end
  end

  rescue_from SAML2::InvalidMessage, with: :saml_error
  rescue_from SAML2::InvalidSignature, with: :saml_error
  rescue_from OpenSSL::X509::CertificateError, with: :saml_config_error
  def saml_error(error)
    Canvas::Errors.capture_exception(:saml, error, :warn)
    render status: :bad_request, plain: error.to_s
  end

  def saml_config_error(error)
    Canvas::Errors.capture_exception(:saml, error, :warn)
    render status: :unprocessable_entity, plain: error.to_s
  end

  def destroy
    @aac = message = nil
    key_to_certificate = {}
    log_key_used = lambda do |key|
      fingerprint = Digest::SHA1.hexdigest(key_to_certificate[key].to_der).gsub(/(\h{2})(?=\h)/, '\1:')
      logger.info "Received signed SAML LogoutRequest from #{message.issuer.id} using certificate #{fingerprint}"
    end

    if request.post?
      message, relay_state = SAML2::Bindings::HTTP_POST.decode(request.request_parameters)
      @aac = @domain_root_account.authentication_providers.active.where(idp_entity_id: message.issuer.id).first
      unless @aac
        increment_statsd(:attempts)
        increment_statsd(:failure, reason: :wrong_sp)
        return render status: :bad_request, plain: "Could not find SAML Entity"
      end

      # only require signatures for LogoutRequests, and only if the provider has a certificate on file
      if message.is_a?(SAML2::LogoutRequest) && (certificates = aac.signing_certificates)
        unless message.signed?
          increment_statsd(:attempts)
          increment_statsd(:failure, reason: :unsigned_request)
          raise SAML2::UnsignedMessage
        end

        unless (signature_errors = message.validate_signature(cert: certificates)).empty?
          logger.debug("Failed to validate signature: #{signature_errors}")
          increment_statsd(:attempts)
          increment_statsd(:failure, reason: :invalid_signature)
          raise SAML2::InvalidSignature
        end
      end
    else
      message, relay_state = SAML2::Bindings::HTTPRedirect.decode(request.url, public_key_used: log_key_used) do |m|
        message = m
        @aac = @domain_root_account.authentication_providers.active.where(idp_entity_id: message.issuer.id).first
        unless @aac
          increment_statsd(:attempts)
          increment_statsd(:failure, reason: :wrong_sp)
          return render status: :bad_request, plain: "Could not find SAML Entity"
        end

        # only require signatures for LogoutRequests, and only if the provider has a certificate on file
        next unless message.is_a?(SAML2::LogoutRequest)
        next if (certificates = aac.signing_certificates).blank?

        certificates.map do |certificate|
          key = certificate.public_key
          key_to_certificate[key] = certificate
          key
        end
      end
      # the above block may have been skipped in specs due to stubbing
      @aac ||= @domain_root_account.authentication_providers.active.where(idp_entity_id: message.issuer.id).first
      unless @aac
        increment_statsd(:attempts)
        increment_statsd(:failure, reason: :wrong_sp)
        return render status: :bad_request, plain: "Could not find SAML Entity"
      end
    end

    unless message.valid_schema?
      if aac.settings["ignore_slo_schema_errors"]
        logger.warn "Ignoring SAML LogoutRequest schema errors"
      else
        increment_statsd(:failure, reason: :invalid_schema)
        return render status: :bad_request, plain: "Invalid SAML message"
      end
    end

    case message
    when SAML2::LogoutResponse
      increment_statsd(:attempts, action: :slo_response)

      if aac.debugging? && aac.debug_get(:logout_request_id) == message.in_response_to
        aac.debug_set(:idp_logout_response_encoded, params[:SAMLResponse])
        aac.debug_set(:idp_logout_response_xml_encrypted, message.xml.to_xml)
        aac.debug_set(:idp_logout_response_in_response_to, message.in_response_to)
        aac.debug_set(:idp_logout_response_destination, message.destination)
        aac.debug_set(:debugging, t("debug.logout_response_redirect_from_idp", "Received LogoutResponse from IdP"))
      end

      unless message.status.code == SAML2::Status::SUCCESS
        logger.error "Failed SAML LogoutResponse: #{message.status.code}: #{message.status.message}"
        flash[:delegated_message] = t("There was a failure logging out at your IdP")
        increment_statsd(:failure, action: :slo_response)
        return redirect_to login_url
      end

      increment_statsd(:success, action: :slo_response)

      handle_slo_response(message)
    when SAML2::LogoutRequest
      handle_slo_request(message, relay_state)
    else
      error = "Unexpected SAML message: #{message.class}"
      Canvas::Errors.capture_exception(:saml, error, :warn)
      render status: :bad_request, plain: error
    end
  end

  def handle_slo_response(_message)
    # for parent using self-registration to observe a student
    # following saml validation of student
    # resume registration process
    if (data = session.delete(:parent_registration))
      if data[:unique_id_match]
        if data[:observee_only].present?
          # TODO: a race condition exists where the observee unique_id is
          # already checked during pre-login form submit, but might have gone
          # away during login. this should be very rare, and we don't have a
          # mechanism for displaying and correcting the error yet.

          # create the observee relationship, then send them back to that index
          complete_observee_addition(data)
          redirect_to observees_profile_path
        else
          # TODO: a race condition exists where the observer unique_id and
          # observee unique_id are already checked during pre-login form
          # submit, but the former might have been taken or the latter gone
          # away during login. this should be very rare, and we don't have a
          # mechanism for displaying and correcting the error yet.

          # create the observer user connected to the observee
          pseudonym = complete_parent_registration(data)

          # log the new user in and send them to the dashboard
          PseudonymSession.new(pseudonym).save
          redirect_to dashboard_path(registration_success: 1)
        end
      else
        flash[:error] = t("We're sorry, a login error has occurred, please check your child's credentials and try again.")
        redirect_to data[:observee_only].present? ? observees_profile_path : canvas_login_path
      end
      return
    end

    redirect_to saml_login_url(id: aac.id)
  end

  def handle_slo_request(message, relay_state)
    increment_statsd(:attempts)

    if aac.debugging? && aac.debug_get(:logged_in_user_id) == @current_user.id
      aac.debug_set(:idp_logout_request_encoded, params[:SAMLRequest])
      aac.debug_set(:idp_logout_request_xml_encrypted, message.xml.to_xml)
      aac.debug_set(:idp_logout_request_name_id, message.name_id.id)
      aac.debug_set(:idp_logout_request_session_index, message.session_index)
      aac.debug_set(:idp_logout_request_destination, message.destination)
      aac.debug_set(:debugging, t("debug.logout_request_redirect_from_idp", "Received LogoutRequest from IdP"))
    end

    sso_idp = aac.idp_metadata.identity_providers.first
    if sso_idp.single_logout_services.empty?
      increment_statsd(:failure, reason: :no_slo_service)
      return render status: :bad_request, plain: "IDP Metadata contains no destination to send a logout response"
    end

    status = SAML2::Status::SUCCESS

    if !@current_user
      increment_statsd(:failure, reason: :no_session)
      status = SAML2::Status::RESPONDER
      error_message = "No current session"
    elsif message.name_id.id != session[:name_id] ||
          (message.name_id.format || SAML2::NameID::Format::UNSPECIFIED) != (session[:name_identifier_format] || SAML2::NameID::Format::UNSPECIFIED) ||
          message.name_id.name_qualifier != session[:name_qualifier] ||
          message.name_id.sp_name_qualifier != session[:sp_name_qualifier]
      increment_statsd(:failure, reason: :name_id_mismatch)
      status = SAML2::Status::RESPONDER
      error_message = "NameID does not match current session"
    end

    logout_response = SAML2::LogoutResponse.respond_to(message,
                                                       aac.idp_metadata.identity_providers.first,
                                                       SAML2::NameID.new(aac.entity_id),
                                                       status,
                                                       message: error_message)

    # Seperate the debugging out because we want it to log the request even if the response dies.
    if aac.debugging? && aac.debug_get(:logged_in_user_id) == @current_user.id
      aac.debug_set(:idp_logout_response_xml_encrypted, logout_response.to_s)
      aac.debug_set(:idp_logout_response_status_code, logout_response.status.code)
      aac.debug_set(:idp_logout_response_destination, logout_response.destination)
      aac.debug_set(:idp_logout_response_in_response_to, logout_response.in_response_to)
      aac.debug_set(:debugging, t("debug.logout_response_redirect_to_idp", "Sending LogoutResponse to IdP"))
    end

    if status == SAML2::Status::SUCCESS
      increment_statsd(:success)

      # ignore the redirect response; it would just be a circular response back to the IdP
      logout_current_user_for_idp
      return if performed?
    end

    private_key = AuthenticationProvider::SAML.private_key
    private_key = nil if aac.sig_alg.nil?
    forward_url = SAML2::Bindings::HTTPRedirect.encode(logout_response,
                                                       relay_state:,
                                                       private_key:,
                                                       sig_alg: aac.sig_alg)

    redirect_to(forward_url)
  end

  def metadata
    # This needs to be publicly available since external SAML
    # servers need to be able to access it without being authenticated.
    # It is used to disclose our SAML configuration settings.
    metadata = AuthenticationProvider::SAML.sp_metadata_for_account(@domain_root_account, request.host_with_port, include_all_encryption_certificates: false)
    render xml: metadata.to_xml
  end

  def observee_validation
    redirect_to
    @domain_root_account.parent_registration_ap.generate_authn_request_redirect(host: request.host_with_port,
                                                                                force_login: session[:parent_registration])
  end

  protected

  def aac
    @aac ||= begin
      scope = @domain_root_account.authentication_providers.active.where(auth_type: "saml")
      id = params[:id] || params[:entityID]

      if !id
        scope.first!
      elsif id.to_i == 0
        scope.find_by!(idp_entity_id: id)
      else
        scope.find(id)
      end
    end
  end

  def complete_observee_addition(registration_data)
    observee_unique_id = registration_data[:observee][:unique_id]
    observee = @domain_root_account.pseudonyms.by_unique_id(observee_unique_id).first.user
    unless @current_user.as_observer_observation_links.where(user_id: observee, root_account: @domain_root_account).exists?
      UserObservationLink.create_or_restore(student: observee, observer: @current_user, root_account: @domain_root_account)
      @current_user.touch
    end
  end

  def complete_parent_registration(registration_data)
    user_name = registration_data[:user][:name]
    terms_of_use = registration_data[:user][:terms_of_use]
    observee_unique_id = registration_data[:observee][:unique_id]
    observer_unique_id = registration_data[:pseudonym][:unique_id]

    # create observer with specificed name
    user = User.new
    user.name = user_name
    user.terms_of_use = terms_of_use
    user.initial_enrollment_type = "observer"
    user.workflow_state = "pre_registered"
    user.require_presence_of_name = true
    user.require_acceptance_of_terms = @domain_root_account.terms_required?
    user.validation_root_account = @domain_root_account

    # add the desired pseudonym
    pseudonym = user.pseudonyms.build(account: @domain_root_account)
    pseudonym.account.email_pseudonyms = true
    pseudonym.unique_id = observer_unique_id
    pseudonym.workflow_state = "active"
    pseudonym.user = user
    pseudonym.account = @domain_root_account

    # add the email communication channel
    cc = user.communication_channels.build(path_type: CommunicationChannel::TYPE_EMAIL, path: observer_unique_id)
    cc.workflow_state = "unconfirmed"
    cc.user = user
    user.save!

    # set the new user (observer) to observe the target user (observee)
    observee = @domain_root_account.pseudonyms.active.by_unique_id(observee_unique_id).first.user
    UserObservationLink.create_or_restore(student: observee, observer: user, root_account: @domain_root_account)

    notify_policy = Users::CreationNotifyPolicy.new(false, unique_id: observer_unique_id)
    notify_policy.dispatch!(user, pseudonym, cc)

    pseudonym
  end

  def auth_type
    AuthenticationProvider::SAML.sti_name
  end
end
