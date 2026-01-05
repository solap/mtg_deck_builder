defmodule MtgDeckBuilder.Accounts do
  @moduledoc """
  The Accounts context for user management.
  """

  import Ecto.Query, warn: false
  alias MtgDeckBuilder.Repo
  alias MtgDeckBuilder.Accounts.User

  @admin_emails ["joeldehlin@gmail.com"]

  @doc """
  Gets a user by their Google ID.
  """
  def get_user_by_google_id(google_id) do
    Repo.get_by(User, google_id: google_id)
  end

  @doc """
  Gets a user by ID.
  """
  def get_user(id) do
    Repo.get(User, id)
  end

  @doc """
  Creates or updates a user from Google OAuth data.
  Sets is_admin based on email whitelist.
  """
  def find_or_create_user_from_google(%{
        "sub" => google_id,
        "email" => email,
        "name" => name,
        "picture" => avatar_url
      }) do
    is_admin = email in @admin_emails

    case get_user_by_google_id(google_id) do
      nil ->
        %User{}
        |> User.changeset(%{
          google_id: google_id,
          email: email,
          name: name,
          avatar_url: avatar_url,
          is_admin: is_admin
        })
        |> Repo.insert()

      user ->
        # Update user info on each login
        user
        |> User.changeset(%{
          email: email,
          name: name,
          avatar_url: avatar_url,
          is_admin: is_admin
        })
        |> Repo.update()
    end
  end

  @doc """
  Checks if a user is an admin.
  """
  def admin?(nil), do: false
  def admin?(%User{is_admin: is_admin}), do: is_admin
end
