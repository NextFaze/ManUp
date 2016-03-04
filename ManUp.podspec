Pod::Spec.new do |s|
  s.name             = "ManUp"
  s.version          = "0.1.1"
  s.summary          = "A server side check of the app version and configuration options for your iOS app."

  s.description      = <<-DESC
  A useful class to add a server side check for a mandatory update and server-side configuration options to your iOS application.
                       DESC

  s.homepage         = "https://github.com/NextFaze/ManUp"
  s.license          = 'Apache 2.0'
  s.authors          = { "Jeremy Day" => "jer.day@gmail.com",
                         "Ricardo Santos" => "rics@ntos.me" }
  s.source           = { :git => "https://github.com/NextFaze/ManUp.git", :tag => s.version.to_s }

  s.platform     = :ios, '7.0'
  s.requires_arc = true

  s.source_files = 'ManUp/*.{h,m}'
end
