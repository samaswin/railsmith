# frozen_string_literal: true

# Medium fixture — 2 violations: direct_model_access in index and show.
class AlphaController < ApplicationController
  def index
    @items = Item.all
  end

  def show
    @item = Item.find(params[:id])
  end

  def new
    result = ItemService.new(context: context).build
    @item = result.value
  end

  def create
    result = ItemService.new(context: context).create(item_params)
    redirect_to result.value
  end

  private

  def item_params
    params.require(:item).permit(:name)
  end
end
