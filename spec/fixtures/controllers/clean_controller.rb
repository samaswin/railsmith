# frozen_string_literal: true

# Fixture: all actions delegate to service classes — zero violations expected.
class CleanController < ApplicationController
  def index
    result = UserService.new(context: context).list
    @users = result.value
  end

  def show
    result = UserService.new(context: context).find(id: params[:id])
    @user = result.value
  end

  def create
    result = UserService.new(context: context).create(user_params)
    if result.success?
      redirect_to @user
    else
      render :new
    end
  end

  def update
    result = UserService.new(context: context).update(params[:id], user_params)
    if result.success?
      redirect_to @user
    else
      render :edit
    end
  end

  def destroy
    UserService.new(context: context).destroy(params[:id])
    redirect_to users_path
  end

  private

  def user_params
    params.require(:user).permit(:name, :email)
  end
end
