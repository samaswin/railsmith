# frozen_string_literal: true

# Medium fixture — mixed: some actions direct, some via service.
class DeltaController < ApplicationController
  def index
    result = ReportService.new(context: context).all
    @reports = result.value
  end

  def show
    @report = Report.find(params[:id])
  end

  def export
    @data = Report.where(exported: false).pluck(:id, :name)
  end

  def regenerate
    result = ReportService.new(context: context).regenerate(params[:id])
    redirect_to report_path(result.value)
  end

  private

  def report_params
    params.require(:report).permit(:title, :format)
  end
end
