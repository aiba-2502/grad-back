class Api::V1::Auth::AuthController < ApplicationController
  before_action :authorize_request, only: [ :me ]

  # POST /api/v1/auth/signup
  def signup
    user = User.new(user_params)

    if user.save
      token = JsonWebToken.encode(user_id: user.id)
      render json: {
        user: {
          id: user.id,
          name: user.name,
          email: user.email
        },
        token: token,
        message: "User created successfully"
      }, status: :created
    else
      render json: { errors: user.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # POST /api/v1/auth/login
  def login
    user = User.find_by(email: params[:email]&.downcase)

    if user&.authenticate(params[:password])
      token = JsonWebToken.encode(user_id: user.id)
      render json: {
        user: {
          id: user.id,
          name: user.name,
          email: user.email
        },
        token: token,
        message: "Logged in successfully"
      }, status: :ok
    else
      render json: { error: "Invalid email or password" }, status: :unauthorized
    end
  end

  # DELETE /api/v1/auth/logout
  def logout
    render json: { message: "Logged out successfully" }, status: :ok
  end

  # GET /api/v1/auth/me
  def me
    render json: {
      user: {
        id: @current_user.id,
        name: @current_user.name,
        email: @current_user.email
      }
    }, status: :ok
  end

  private

  def user_params
    params.require(:user).permit(:name, :email, :password, :password_confirmation)
  end

  def current_user
    @current_user ||= User.find_by(id: session[:user_id]) if session[:user_id]
  end
end
