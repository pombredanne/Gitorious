# encoding: utf-8
#--
#   Copyright (C) 2011 Gitorious AS
#
#   This program is free software: you can redistribute it and/or modify
#   it under the terms of the GNU Affero General Public License as published by
#   the Free Software Foundation, either version 3 of the License, or
#   (at your option) any later version.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU Affero General Public License for more details.
#
#   You should have received a copy of the GNU Affero General Public License
#   along with this program.  If not, see <http://www.gnu.org/licenses/>.
#++

require "test_helper"
class Gitorious::Authentication::LDAPAuthenticationTest < ActiveSupport::TestCase
  # Mock that should receive callbacks
  class CallbackMock
    def self.reset
      @post_authenticate_called = nil
    end

    def self.post_authenticate(options)
      @post_authenticate_called = :true
    end

    def self.called?
      @post_authenticate_called == :true
    end
  end

  def valid_client_credentials(username, password)
    credentials = Gitorious::Authentication::Credentials.new
    credentials.username = username
    credentials.password = password
    credentials
  end


  context "Configuration" do
    setup do
      @ldap = Gitorious::Authentication::LDAPAuthentication.new({
          "server" => "localhost",
          "base_dn" => "DC=gitorious,DC=org"
        })
    end

    should "require a server name" do
      assert_raises Gitorious::Authentication::ConfigurationError do
        ldap = Gitorious::Authentication::LDAPAuthentication.new({"base_dn" => "DC=gitorious.DC=org"})
      end
    end

    should "require a base DN" do
      assert_raises Gitorious::Authentication::ConfigurationError do
        ldap = Gitorious::Authentication::LDAPAuthentication.new({"server" => "localhost"})
      end
    end

    should "use a default LDAP port" do
      assert_equal 389, @ldap.port
    end

    should "default to simple tls encryption" do
      assert_equal :simple_tls, @ldap.encryption
    end

    should "provide a default attribute mapping" do
      assert_equal({"displayname" => "fullname", "mail" => "email"}, @ldap.attribute_mapping)
    end

    should "use a Net::LDAP instance by default" do
      assert_equal Net::LDAP, @ldap.connection_type
    end

    should "provide a default DN template" do
      assert_equal "CN={},DC=gitorious,DC=org", @ldap.distinguished_name_template
    end

    should "provide default DN template with different login attribute" do
      @ldap = Gitorious::Authentication::LDAPAuthentication.new({
          "server" => "localhost",
          "base_dn" => "dc=gitorious,dc=org",
          "login_attribute" => "uid"
        })

      assert_equal "uid={},dc=gitorious,dc=org", @ldap.distinguished_name_template
    end
  end

  class StaticLDAPConnection
    def initialize(opts)
      raise "Static LDAP connection created without host" unless opts[:host]
    end

    def self.login_attribute=(attr)
      @login_attribute = attr
    end

    def self.login_attribute
      @login_attribute || "CN"
    end

    def self.username=(name)
      @username = name
    end

    def self.username
      @username || "moe"
    end

    def auth(username, password)
      @allowed = username == "#{self.class.login_attribute}=#{self.class.username},DC=gitorious,DC=org" && password == "secret"
    end

    def bind
      @allowed
    end

    def search(options)
      return [] unless /^\(#{login_attribute}=/ =~ options[:filter].to_s
      entry = {"displayname" => ["Moe Szyslak"], "mail" => ["moe@gitorious.org"]}
      entry["mail"] = [] if self.class.never_return_email?
      result = [entry]
      result
    end

    def self.never_return_email?
      @return_empty_email_address
    end
    
    def self.return_empty_email_address!
      @return_empty_email_address = true
      yield
      @return_empty_email_address = false
    end

    private
    def login_attribute
      self.class.login_attribute
    end
  end

  context "Authentication" do
    setup do
      @ldap = Gitorious::Authentication::LDAPAuthentication.new({
          "server" => "localhost",
          "base_dn" => "DC=gitorious,DC=org",
          "connection_type" => StaticLDAPConnection
        })
    end

    should "not accept invalid credentials" do
      assert !@ldap.valid_credentials?("moe","LetMe1n")
    end

    should "accept valid credentials" do
      assert @ldap.valid_credentials?("moe","secret")
    end

    should "return the actual user" do
      assert_equal(users(:moe), @ldap.authenticate(valid_client_credentials("moe","secret")))
    end

    should "allow host as alias for server" do
      ldap = Gitorious::Authentication::LDAPAuthentication.new({
          "host" => "localhost",
          "base_dn" => "DC=gitorious,DC=org",
          "connection_type" => StaticLDAPConnection
        })

      assert ldap.valid_credentials?("moe","secret")
    end
  end

  context "Callbacks" do
    setup do
      @ldap = Gitorious::Authentication::LDAPAuthentication.new({
          "server" => "localhost",
          "base_dn" => "DC=gitorious,DC=org",
          "connection_type" => StaticLDAPConnection,
          "callback_class" => "Gitorious::Authentication::LDAPAuthenticationTest::CallbackMock"
        })
      CallbackMock.reset
      StaticLDAPConnection.username = "moe"
    end

    should "not call post_authenticate when login fails" do
      assert !@ldap.authenticate(valid_client_credentials("moe", "ohno"))
      assert !CallbackMock.called?
    end

    should "call post_authenticate after successful login" do
      assert_equal users(:moe), @ldap.authenticate(valid_client_credentials("moe","secret"))
      assert CallbackMock.called?
    end
  end

  context "Authenticated binding" do
    should "use authenticated bind when a bind user has been specified" do
      ldap = Gitorious::Authentication::LDAPAuthentication.new({
                                                                 "server" => "localhost",
                                                                 "base_dn" => "",
                                                                 "bind_user" => {"username" => "cn=guest"}
                                                               })
      assert ldap.use_authenticated_bind?
    end
  end

  context "Auto-registration" do
    setup do
      @ldap = Gitorious::Authentication::LDAPAuthentication.new({
          "server" => "localhost",
          "base_dn" => "DC=gitorious,DC=org",
          "connection_type" => StaticLDAPConnection})
      StaticLDAPConnection.username = "moe.szyslak"
    end

    teardown do
      StaticLDAPConnection.login_attribute = "CN"
    end

    should "create a new user with attributes mapped from LDAP" do
      user = @ldap.authenticate(valid_client_credentials("moe.szyslak", "secret"))
      assert_equal "moe@gitorious.org", user.email
      assert_equal "Moe Szyslak", user.fullname
      assert_equal "moe-szyslak", user.login

      assert user.valid?
    end

    should "build a synthetic email if LDAP entry has no email" do
      StaticLDAPConnection.return_empty_email_address! do
        user = @ldap.authenticate(valid_client_credentials("moe.szyslak", "secret"))
        assert_equal("moe.szyslak.example@#{GitoriousConfig['gitorious_host']}", user.email)
      end
    end

    should "transform user's login to not contain dots" do
      StaticLDAPConnection.username = "mr.moe.szyslak"
      user = @ldap.authenticate(valid_client_credentials("mr.moe.szyslak", "secret"))

      assert_equal "mr-moe-szyslak", user.login
    end

    should "search using uid instead of cn" do
      @ldap = Gitorious::Authentication::LDAPAuthentication.new({
        "server" => "localhost",
        "base_dn" => "DC=gitorious,DC=org",
        "login_attribute" => "uid",
        "connection_type" => StaticLDAPConnection})
      StaticLDAPConnection.username = "mr.moe.szyslak"
      StaticLDAPConnection.login_attribute = "uid"
      user = @ldap.authenticate(valid_client_credentials("mr.moe.szyslak", "secret"))

      assert_equal "mr-moe-szyslak", user.login
    end
  end
end
