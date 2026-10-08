class NoticeMessenger < ApplicationMessenger
  layout "sms"

  def reminder(phone)
    text to: phone
  end
end
