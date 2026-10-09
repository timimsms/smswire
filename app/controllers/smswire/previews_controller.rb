module Smswire
  class PreviewsController < DevelopmentController
    self.enabled_by = :show_previews

    def index
      @previews = Preview.all
    end

    def show
      preview_name, _, message_name = params[:path].rpartition("/")
      @preview = Preview.find(preview_name)
      return head(:not_found) unless @preview&.message_exists?(message_name)

      @message_name = message_name
      @message = @preview.call(message_name)
      return render(plain: @message&.body.to_s) if params[:raw].present?

      @analysis = @message && Segments.analyze(@message.body)
      @non_gsm = @message ? Segments.non_gsm_characters(@message.body) : []
    end
  end
end
