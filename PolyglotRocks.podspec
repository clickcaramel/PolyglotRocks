Pod::Spec.new do |s|
  s.name = 'PolyglotRocks'
  s.version = ENV['LIB_VERSION'] || '0.1.0'
  s.summary = 'One step localization for your mobile app'
  s.description = 'Drop in our SDK into your project and run the build: you get AI translations instantly, and manual ones a bit later.'
  
  s.homepage = 'https://github.com/clickcaramel/PolyglotRocks'
  s.license = { :type => 'Apache 2.0', :file => 'LICENSE' }
  s.author = { 'bleshik' => 'abalchunas@4spaces.company' }
  s.source = { :git => 'https://github.com/clickcaramel/PolyglotRocks.git', :tag => "v#{s.version.to_s}" }
  
  s.ios.deployment_target = '11.0'
  s.source_files = 'bin/**/*'
end
