require "test_helper"

class Oauth::ScopesTest < ActiveSupport::TestCase
  test "valid? accepts each known scope alone and together" do
    assert Oauth::Scopes.valid?("analytics:read")
    assert Oauth::Scopes.valid?("analytics:manage")
    assert Oauth::Scopes.valid?("analytics:read analytics:manage")
  end

  test "valid? rejects empty string and unknown tokens" do
    assert_not Oauth::Scopes.valid?("")
    assert_not Oauth::Scopes.valid?("read:analytics") # the old (renamed) scope
    assert_not Oauth::Scopes.valid?("admin:everything")
    assert_not Oauth::Scopes.valid?("analytics:read drop:database")
  end

  test "granted? requires every named scope" do
    assert Oauth::Scopes.granted?("analytics:read analytics:manage", "analytics:read")
    assert Oauth::Scopes.granted?("analytics:read analytics:manage", [ "analytics:read", "analytics:manage" ])
    assert_not Oauth::Scopes.granted?("analytics:read", "analytics:manage")
    assert_not Oauth::Scopes.granted?("", "analytics:read")
  end

  test "parse drops unknown scopes silently" do
    assert_equal Set.new([ "analytics:read" ]),
                 Oauth::Scopes.parse("analytics:read drop:database")
  end
end
