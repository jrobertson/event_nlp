#!/usr/bin/env ruby

# file: event_nlp.rb

require 'chronic_cron'
require 'ostruct'
require 'app-routes'



module Ordinals

  refine Integer do
    def ordinal
      self.to_s + ( (10...20).include?(self) ? 'th' : 
                    %w{ th st nd rd th th th th th th }[self % 10] )
    end
  end
end


class EventNlp
  include AppRoutes
  using Ordinals
  
  attr_accessor :params
  
  def initialize(now=Time.now, params: {}, debug: false)
    
    super()
    
    @now = now
    @params = params
    expressions(@params)
    @debug = debug

  end
  
  def parse(s)

    @params[:input] = s
    r = run_route(s)

    return unless r.is_a? Hash
    
    OpenStruct.new({input: s}.merge r)
    
  end  

  private

  def expressions(params) 
    
    # some event every 2 weeks
    # some event every 2 weeks at 6am starting from 14th Jan
    # some event every 2 weeks at 6am starting from 18th Feb until 28th Oct
    # some event every 2nd Monday (starting 7th Nov 2016)
    # some event every 2nd Monday (starting 7th Nov until 3rd Dec)


    starting = /(?:\(?\s*starting (\d+\w{2} \w+\s*\w*)(?: until (.*))?\s*\))?/
    weekday = Date::DAYNAMES.join('|').downcase
    months = (Date::MONTHNAMES[1..-1] + Date::ABBR_MONTHNAMES[1..-1])
      .join('|').downcase
    time = /(?: (?:at )?(\d+(?::\d+)?am) )?/


    get /^(.*)\s+(every \d\w+ \w+#{time})\s*#{starting}/ do \
                                   |title, recurring, time, raw_date, end_date|

      input = params[:input].clone            
      d = Chronic.parse(raw_date + ' ' + time.to_s)
      
      if recurring =~ /day|week/ then

        if d < @now then

          new_date = CronFormat.new(ChronicCron.new(recurring)\
                                    .to_expression, d).to_time
          input.gsub!(raw_date, new_date\
                      .strftime("#{new_date.day.ordinal} %b %Y"))             
          d = new_date
          
        end
      end
      
      if @debug then
        puts [0, input, title, recurring, time, raw_date, end_date].inspect 
      end
      
      {input: input, title: title, recurring: recurring, date: d, 
       end_date: end_date}      
      
    end
    
    # e.g. some event 1st Monday of every month (starting 3rd Jul 2017)

    get /^(.*)\s+(\d(?:st|nd|rd|th) \w+ of every \w+(?: at (\d+[ap]m) )?)\s*#{starting}/ do \
                                   |title, recurring, time, raw_date, end_date|

      input = params[:input].clone
      d = Chronic.parse(raw_date)
      
      if recurring =~ /day|week|month/ then        
        
        if d < @now then

          new_date = CronFormat.new(ChronicCron.new(recurring)\
                                    .to_expression, d).to_time
          input.gsub!(raw_date, new_date\
                      .strftime("#{new_date.day.ordinal} %b %Y"))        
          d = new_date
        else
          d = ChronicCron.new(recurring, d.to_date.to_time).to_time
        end
      end
      
      puts [0.3, title, recurring, time, raw_date, end_date].inspect if @debug
      {input: input, title: title, recurring: recurring, date: d, end_date: 
                                                                      end_date}
      
    end    
    
    get /^(.*)(every .*)/ do |title, recurring|

      exp = ChronicCron.new(recurring).to_expression

      d = CronFormat.new(exp).to_time
      
      puts [0.5, title, recurring, d].inspect if @debug
      {title: title, recurring: recurring, date: d }
      
    end    
    
    # some meeting 3rd thursday of the month at 7:30pm
    # some meeting First thursday of the month at 7:30pm
    get /(.*)\s+(\w+ \w+day of (?:the|every) month at .*)/ do 
                                                             |title, recurring|

      puts [1, title, recurring].inspect if @debug
      { title: title, recurring: recurring }

    end
    
    # hall 2 friday at 11am
    get /(.*)\s+(#{weekday})\s+at\s+(.*)/i do |title, raw_day, time|
      
      d = Chronic.parse(raw_day + ' ' + time)
      
      puts [1.5, title, raw_day].inspect if @debug
      { title: title, date: d }
      
    end    
    
    # e.g. 21/05/2017 Forum meetup at Roundpeg from 2pm
    get /^(\d+\/\d+\/\d+)\s+(.*)(?: from|at)\s+(\d+[ap]m)/ do 
                                                    |raw_date, title, raw_time|
      
      d = Chronic.parse(raw_date + ' ' + 
                        raw_time, :endian_precedence => :little)
      recurring = nil            
      
      puts [3, title, raw_date].inspect if @debug
      { title: title, date: d }
    end        
    
    # friday hall 2 11am
    get /^(#{weekday})\s+(.*)\s+(\d+(?::\d{2})?[ap]m)$/i do |raw_day, title, time|
      
      d = Chronic.parse(raw_day + ' ' + time)
      
      puts [1.44, title, raw_day].inspect if @debug
      { title: title, date: d }
      
    end    
    
    
    # hall 2 at 11am
    get /(.*)\s+at\s+(.*)/i do |title,  time|
      
      d = Chronic.parse(time)
      
      puts [1.45, title].inspect if @debug
      { title: title, date: d }
      
    end        
 
    # hall 2 friday at 11am
    # some important day 24th Mar
    
    with_date = "(.*)\\s+(\\d\+\s*(?:st|nd|rd|th)?\\s+(?:#{months}))"
    alt_pattern = '([^\d]+)\s+(\d+[^\*]+)(\*)?'
    
    get /#{with_date}|#{alt_pattern}\s*(\*)$/i do |title, raw_date, annualar|

      d = Chronic.parse(raw_date)

      recurring = nil
      
      if annualar then
        
        recurring = 'yearly'
        if d < @now then
          d = Chronic.parse(raw_date, now: Time.local(@now.year + 1, 1, 1)) 
        end
      end
      
      puts [2, title, raw_date].inspect if @debug
      { title: title, date: d, recurring: recurring }
    end
    
    # 27-Mar@1436 some important day
    # 25/07/2017 11pm some important day
    #
    get /(\d[^\s]+)\s*(\d+(?:\:\d+)?[ap]m)?\s+([^\*]+)(\*)?/ do |raw_date,
        time, title, annualar|

      d = Chronic.parse(raw_date + ' ' + time.to_s, 
                        :endian_precedence => :little)
      recurring = nil
      
      if annualar then
        
        recurring = 'yearly'
        if d < @now then
          d = Chronic.parse(raw_date, now: Time.local(@now.year + 1, 1, 1)) 
        end
      end
      
      
      puts [3, title, raw_date, time].inspect if @debug
      { title: title, date: d, recurring: recurring }
    end

    # some event Wednesday
    # some event Wednesday 11am
    
    relative_day = '|today|tomorrow|tonight'
    get /^(.*)\s+((?:#{weekday+relative_day})(?: \d{1,2}(?::\d{2})?[ap]m)?)/i \
                                                           do |title, raw_date|
      
      d = Chronic.parse(raw_date)
      
      puts [4, title, raw_date].inspect if @debug
      {title: title, date: d }
       
    end
    
    # e.g. 04-Aug@12:34
    get '*' do |s|
      puts 's: ' + s.inspect if @debug
      'pattern unrecognised'
    end

  end
  
end