module Api
  module V1
    module Admin
      class UsersController < ApplicationController
        before_action :authenticate_admin!
        before_action :set_user, only: [ :show, :update, :destroy ]

        # create new user POST - api/v1/admin/users/
        def create
          user = User.new(user_params)

          if user.save
            user.send_confirmation_instructions
            render json: { message: 'User created successfully.', user: user }, status: :created
          else
            render json: { errors: user.errors.full_messages }, status: :unprocessable_entity
          end
        end

        # show user GET - api/v1/admin/users/:id
        def show
          if @user.nil?
            render json: { error: "User not found" }, status: :not_found
          elsif @user.confirmed?
            render json: { user: @user }, status: :ok
          else
            render json: { errors: "User not confirmed" }, status: :unprocessable_entity
          end
        end

        # Edit user PATCH - api/v1/admin/users/:id
        def update
          if @user.confirmed?
            if @user.update(user_params)
              render json: { message: 'User updated successfully.', user: @user }, status: :ok
            else
              render json: { errors: @user.errors.full_messages }, status: :unprocessable_entity
            end
          else
            render json: { error: 'Unconfirmed users cannot be updated.' }, status: :unprocessable_entity
          end
        end

        # Delete user DELETE - api/v1/admin/users/:id
        def destroy
          if @user.destroy
            render json: { message: "User deleted successfully"}, status: :ok
          else 
            render json: { message: "Unable to delete user"}, status: :unprocessable_entity
          end
        end

        # GET api/v1/admin/users
        def index
          users = User.order(:id)

          # Filter by confirmation status if confirmed params provided
          if params[:confirmed].present?
            if params[:confirmed] == 'true'
              users = users.where.not(confirmed_at: nil)
            else
              users = users.where(confirmed_at: nil)
            end
          end

          # Filter by role if role params provided
          if params[:role].present?
            users = users.where(role: params[:role])
          end

          # Apply pagination (10 users per page)
          users = users.page(params[:page]).per(10)

          render json: {
            users: users,
            total_pages: users.total_pages,
            current_page: users.current_page
          }, status: :ok
        end

        private

        def user_params
          params.require(:user).permit(:email, :first_name, :last_name, :role, :password)
        end

        def set_user 
          @user = User.find(params[:id])
        end
      end
    end
  end
end
