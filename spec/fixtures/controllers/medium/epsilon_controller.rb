# frozen_string_literal: true

# Medium fixture — zero violations: every action uses a service.
class EpsilonController < ApplicationController
  def index
    result = NotificationService.new(context: context).list(user_id: current_user_id)
    @notifications = result.value
  end

  def show
    result = NotificationService.new(context: context).find(id: params[:id])
    @notification = result.value
  end

  def mark_read
    NotificationService.new(context: context).mark_read(params[:id])
    head :ok
  end

  def destroy
    NotificationService.new(context: context).dismiss(params[:id])
    redirect_to notifications_path
  end

  private

  def current_user_id
    session[:user_id]
  end
end
