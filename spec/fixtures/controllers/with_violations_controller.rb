# frozen_string_literal: true

# Fixture: intentional violations for detector tests.
#
# Expected violations:
#   index  — direct_model_access (User.all)     + missing_service_usage
#   show   — direct_model_access (User.find)    + missing_service_usage
#   create — direct_model_access (Post.where)   + missing_service_usage
#   mixed  — direct_model_access (Comment.count), NO missing_service_usage (service present)
#   clean  — no violations (service only)
#   dangerous_helper (private) — direct_model_access (User.find); NO missing_service_usage
class WithViolationsController < ApplicationController
  # Violation: User.all with no service
  def index
    @users = User.all
  end

  # Violation: User.find with no service
  def show
    @user = User.find(params[:id])
    render :show
  end

  # Violation: Post.where with no service
  def create
    @posts = Post.where(active: true)
    render :index
  end

  # direct_model_access on Comment.count, but service IS present → only 1 violation
  def mixed
    result = CommentService.new(context: context).list
    @count = Comment.count
    @comments = result.value
  end

  # Clean action — no violations
  def clean
    result = UserService.new(context: context).list
    @users = result.value
  end

  private

  def user_params
    params.require(:user).permit(:name, :email)
  end

  # Direct AR in a private helper — direct_model_access may flag; missing_service_usage skips private defs.
  def dangerous_helper
    User.find(1)
  end
end
