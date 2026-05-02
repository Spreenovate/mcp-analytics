class AddOauthToEmailVerifications < ActiveRecord::Migration[8.1]
  def change
    add_reference :email_verifications, :oauth_authorization_request,
                  foreign_key: true, null: true
  end
end
