Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  # Browse every stream and event in development, including the usage behind
  # any invoice: http://localhost:3000/res
  mount RailsEventStore::Browser => "/res" if Rails.env.development?
end
