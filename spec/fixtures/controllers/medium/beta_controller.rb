# frozen_string_literal: true

# Medium fixture — all actions use services, zero violations expected.
class BetaController < ApplicationController
  def index
    result = OrderService.new(context: context).list(filters: filter_params)
    @orders = result.value
  end

  def show
    result = OrderService.new(context: context).find(id: params[:id])
    @order = result.value
  end

  def create
    result = OrderService.new(context: context).create(order_params)
    if result.success?
      redirect_to order_path(result.value)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    OrderService.new(context: context).cancel(params[:id])
    redirect_to orders_path
  end

  private

  def order_params
    params.require(:order).permit(:product_id, :quantity)
  end

  def filter_params
    params.permit(:status, :from_date)
  end
end
