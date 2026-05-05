class AddSessionVersionToUsers < ActiveRecord::Migration[8.1]
  # Bumped on sign-out (and any future "log me out everywhere" event) so a
  # stolen Settings cookie can't be replayed past the moment the legitimate
  # user signed out — defeats the cookie-store replay window without
  # moving session state out of the cookie.
  def change
    add_column :users, :session_version, :integer, default: 0, null: false
  end
end
