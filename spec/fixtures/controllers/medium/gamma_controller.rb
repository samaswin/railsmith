# frozen_string_literal: true

# Medium fixture — 3 direct_model_access violations, service present in one action.
class GammaController < ApplicationController
  def index
    @products = Product.where(available: true).order(:name)
  end

  def show
    @product = Product.find_by!(slug: params[:slug])
  end

  def stats
    @count = Product.count
    @recent = Product.last
  end

  def featured
    result = ProductService.new(context: context).featured
    @products = result.value
  end

  private

  def product_params
    params.require(:product).permit(:name, :price, :slug)
  end
end
