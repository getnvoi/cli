class UsersController < ApplicationController
  def index
    # Create a new user on every visit
    @new_user = User.create!(
      name: generate_random_name,
      email: "user-#{Time.now.to_i}-#{rand(1000)}@example.com"
    )

    @users = User.all.order(created_at: :desc)
  end

  private

  def generate_random_name
    first_names = %w[Alice Bob Charlie Diana Eve Frank Grace Henry Ivy Jack]
    last_names = %w[Smith Johnson Williams Brown Jones Garcia Miller Davis Rodriguez Martinez]
    "#{first_names.sample} #{last_names.sample}"
  end
end
