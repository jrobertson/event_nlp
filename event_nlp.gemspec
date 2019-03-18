Gem::Specification.new do |s|
  s.name = 'event_nlp'
  s.version = '0.5.3'
  s.summary = 'Parses a calendar event for date, time, and description e.g. ' + 
      'hall 2 friday at 11am #=> {:title=>"hall 2", :date=>2017-05-12 11:...} '
  s.authors = ['James Robertson']
  s.files = Dir['lib/event_nlp.rb']
  s.add_runtime_dependency('chronic_cron', '~> 0.5', '>=0.5.0') 
  s.add_runtime_dependency('app-routes', '~> 0.1', '>=0.1.19') 
  s.signing_key = '../privatekeys/event_nlp.pem'
  s.cert_chain  = ['gem-public_cert.pem']
  s.license = 'MIT'
  s.email = 'james@jamesrobertson.eu'
  s.homepage = 'https://github.com/jrobertson/event_nlp'
end
