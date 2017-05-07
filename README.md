# Introducing the event_nlp gem

    require 'event_nlp'

    nlp = EventNlp.new
    r = nlp.parse 'hall 2 friday at 11am'

    #=> {:title=>"hall 2", :date=>2017-05-12 11:00:00 +0100} 

The event_nlp gem attempts to parse a calendar event to capture the data, time, and description.

## Resources 

* event_nlp https://rubygems.org/gems/event_nlp

event nlp eventnlp gem date
