class ApplicationMailer < ActionMailer::Base
  default from: (ENV["MAIL_FROM"] || "no-reply@localhost")
  layout "mailer"
end
