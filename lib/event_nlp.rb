#!/usr/bin/env ruby

# file: event_nlp.rb

require 'ostruct'
require 'app-routes'
require 'chronic_cron'


module Ordinals

  refine Integer do
    def ordinal
      self.to_s + ( self.between?(10,20) ? 'th' :
                    %w{ th st nd rd th th th th th th }[self % 10] )
    end
  end
end


class EventNlp
  include AppRoutes
  using Ordinals
  using ColouredText
  
  attr_accessor :params
  
  def initialize(now=Time.now, params: {}, debug: false)
    
    super()
    
    @debug = debug    
    
    @now = now
    @params = params
    expressions(@params)


  end
  
  def parse(raws)

    s = filter_irregular(raws)

    #-----------------------------------------------------------

    @params[:input] = s
    r = run_route(s)

    return unless r.is_a? Hash
    
    OpenStruct.new({input: s}.merge r)
    
  end

  # returns an Array object of dates, projected from a recurring event
  #
  # Example parameters:
  #
  # s: 'Council Tax 30th Monthly'
  # s: 'Council Tax 30th Monthly until 2nd October'
  #
  def project(s, year: @now.year)

    s2, raw_end_date = s.split(/ +\buntil\b +/)
    
    end_date = if raw_end_date then
      EventNlp.new().parse(raw_end_date).date    
    else
      (Date.parse('1 Jan ' + (year+1).to_s) - 1).to_time
    end
    
    puts 'project/end_date: ' + end_date.inspect if @debug
    
    # filter the input to ensure validity
    r0 = parse s2
    puts 'project/r0: ' + r0.inspect if @debug
    r = parse r0.input
    puts 'project/r: ' + r.inspect if @debug
    
    dates = []
    now = @now

    if @debug then
      puts 'r.date: ' + r.date.inspect
      puts 'r.input: ' + r.input.inspect
      puts 'EventNlp.new(r.date+1).parse(r.input).date: ' + \
          EventNlp.new(r.date+1).parse(r.input).date.inspect
    end

    return [r.date] if (r.date == EventNlp.new(r.date+1, debug: @debug).parse(r.input).date)
#year.to_i

    while r.date <= end_date do

      dates << r.date
      @now = if r.recurring == 'month' then
       (r.date.to_date >> 1).to_time
      #elsif r.recurring == 'weekly'

      else
        r.date + 1
      end
      puts '@now: ' + @now.inspect if @debug
      #@now = r.date + 1
      r = parse(r.input)

    end

    @now = now
    return dates

  end

  private

  def filter_irregular(raws)

    # catch irregular expressions and interpret them in advance
    #
    # e.g. Cafe meeting Thursday every 2 weeks =>
    #                       Cafe meeting every 2nd Thursday
    #
    weekdays2 = (Date::DAYNAMES + Date::ABBR_DAYNAMES).join('|').downcase
    pattern = /(?<day>#{weekdays2}) every (?<n>\d) weeks/i
    found = raws.match(pattern)

    if found then
      s2 = "every %s %s" % [found[:n].to_i.ordinal, found[:day]]
      s = raws.sub(pattern, s2)
    end

    months = (Date::MONTHNAMES + Date::ABBR_MONTHNAMES).join('|').downcase

    # the following would be ambiguous input, but we will assume they
    # meant the 14th day of every month
    # e.g. "Cafe meeting 14th May Monthly"
    found = raws.match(/(?<title>.*)\s+(?<day>\w+(?:st|nd|rd|th)) (#{months}) monthly/i)

    if found then
      s = "%s on the %s of every month" % [found[:title],
                                           found[:day].to_i.ordinal]
    end

    # e.g.  "Cafe meeting 14th Monthly" =>
    #                         Cafe meeting on the 14th of every month
    #
    found = raws.match(/(?<title>.*)\s+(?<day>\w+)(?:st|nd|rd|th) monthly/i)

    if found then
      s = "%s on the %s of every month" % [found[:title],
                                           found[:day].to_i.ordinal]
    end

    # e.g.  "Utility bill last day Monthly" =>
    #                         Utility bill last day of the month
    #
    if raws =~ /last day monthly$/i then
      s = raws.sub(/last day monthly$/i,'last day of the month')
    end


    puts 'filter_irregular - s: ' + s.inspect if @debug
    return s || raws

  end

  def expressions(params)     

    starting = /(?:\(?\s*starting (\d+\w{2} \w+\s*\w*)(?: until (.*))?\s*\))?/
    weekdays2 = (Date::DAYNAMES + Date::ABBR_DAYNAMES).join('|').downcase    
    weekdays = "(%s)" % weekdays2
    months = "(%s)" % (Date::MONTHNAMES[1..-1] + Date::ABBR_MONTHNAMES[1..-1])\
                                                        .join('|').downcase
    years = /(20[0-9]{2})/

    times = /(?: *(?:at |@ |from )?(\d+(?::\d+)?(?:[ap]m|\b)) *)/
    times2 = /\d+(?::\d+)?[ap]m-\d+(?::\d+)?[ap]m|\d+(?::\d+)?-\d+(?::\d+)?/
    times3 = /(\d+(?::\d+)?[ap]m-\d+(?::\d+)?[ap]m|\d+(?::\d+)?-\d+(?::\d+)?)/    
    days = /(\d+(?:st|nd|rd|th))/
    periods = /day|week|month/
    
    #weekdays = Date::DAYNAMES.join('|').downcase
    #
    
    #times = /(?: *at )?\d[ap]m/

   # e.g. electricity bill on the 28th of every month    

   get /(.*) on the #{days} of every (month)/i do |title, day, recurring|


      puts 'day: ' + day.inspect if @debug
      raw_d = Chronic.parse(day + ' ' + Date::MONTHNAMES[@now.month], now: @now)
      
      # if the date is less than now then increment it by a month
      d = raw_d < @now ? (raw_d.to_date >> 1).to_time : raw_d
      
      
      if @debug then
        puts [0.1, title, recurring, d].inspect.debug
      end
      
      {title: title, recurring: recurring, date: d}      
      
    end
    
    #

    get /^(.*)\s+(every \d\w+ \w+#{times}\s*#{starting})/ do \
                                   |title, recurring, time, raw_date, end_date|

      input = params[:input].clone            
      d = Chronic.parse(raw_date + ' ' + time.to_s, now: @now)

      if @debug then
        puts 'e300'
        puts 'd: ' + d.inspect
        puts 'recurring: ' + recurring.inspect
      end
      
      if recurring =~ /day|week/ then

        if d < @now then

          cc = ChronicCron.new(recurring, d)
          exp = cc.to_expression
          puts 'exp: ' + exp.inspect if @debug

          cf = CronFormat.new(exp, d)
          cf.next until cf.to_time > @now

          new_date = cf.to_time
          puts 'new_date: ' + new_date.inspect if @debug

          input.gsub!(raw_date, new_date\
                      .strftime("#{new_date.day.ordinal} %b %Y"))             
          d = new_date
          
        end
      end
      
      if @debug then
        puts 'd: ' + d.inspect
        puts ["0.2", input, title, recurring, time, raw_date, end_date].inspect.debug
      end
      
      {input: input, title: title, recurring: recurring, date: d, 
       end_date: end_date}      
      
    end
    
    # e.g. some event 1st Monday of every month (starting 3rd Jul 2017)

    get /^(.*)\s+(\d(?:st|nd|rd|th) \w+ of every \w+(?: at (\d+[ap]m) )?)\s*#{starting}/ do \
                                   |title, recurring, time, raw_date, end_date|

      input = params[:input].clone
      d = Chronic.parse(raw_date, now: @now)
      
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
      
      puts ['0.3'.highlight, title, recurring, time, raw_date, end_date].inspect.debug if @debug
      {input: input, title: title, recurring: recurring, date: d, end_date: 
                                                                      end_date}
      
    end    

    # some event every 2 weeks
    # some event every 2 weeks at 6am starting from 14th Jan
    # some event every 2 weeks at 6am starting from 18th Feb until 28th Oct
    # some event every 2nd Monday (starting 7th Nov 2016)
    # some event every 2nd Monday (starting 7th Nov until 3rd Dec)    
    # some event every 2 weeks (starting 02/11/17)
    # some event every Wednesday 1pm-4pm
    #
    get /^(.*)(every .*)/ do |title, recurring|

      input = params[:input].clone
      puts 'recurring: ' + recurring.inspect if @debug
      raw_start_date = recurring[/(?<=starting )[^\)]+/]
      
      d = if raw_start_date then
        start_date = Chronic.parse(raw_start_date, now: @now - 1, 
                                   :endian_precedence => :little)

        puts ('recurring: ' + recurring.inspect).debug if @debug
        puts ('start_date: ' + start_date.inspect).debug if @debug
        
        if @now > start_date then
          exp = ChronicCron.new(recurring, start_date, debug: @debug).to_expression
          puts 'exp: ' + exp.inspect if @debug
          
          cf = CronFormat.new(exp, start_date, debug: @debug)
          puts ('cf.to_time: '  + cf.to_time.inspect).debug if @debug
          cf.next until cf.to_time > start_date
          
          new_date = cf.to_time
          input.gsub!(/(?<=starting )[^\)]+/, new_date\
                      .strftime("#{new_date.day.ordinal} %b %Y"))
          new_date

        else
          start_date
        end
        
      else
        exp = ChronicCron.new(recurring).to_expression
        cf = CronFormat.new(exp, @now)
        cf.to_time
      end
      

      
      if recurring =~ /-/ then
        end_date = Chronic.parse d.to_date.to_s + ' ' + 
            recurring[/(?<=-)\d+(?::\d+)?(?:[ap]m)?/], now: @now
      end
          
      puts ['0.5'.highlight, title, recurring, d].join("\n").debug if @debug
      {input: input, title: title.rstrip, recurring: recurring, 
       date: d, end_date: end_date }
      
    end    
    
    # some meeting 3rd thursday of the month at 7:30pm
    # some meeting First thursday of the month at 7:30pm
    get /(.*)\s+(\w+ \w+day of (?:the|every) month at .*)/ do 
                                                             |title, recurring|

      puts ['1'.highlight, title, recurring].inspect.debug if @debug
      { title: title, recurring: recurring }

    end
    
    
    # 7th Oct Euston Station (meet at Timothy's house at 7pm)
    get /^(\d(?:st|nd|rd|th) \w+) *(.*)\s+at\s+(\w+)/i do \
        |raw_day, title, time|
      
      d = Chronic.parse(raw_day + ' ' + time, now: @now)
      
      puts ['1.5'.highlight, title, raw_day, time].inspect.debug if @debug
      { title: title, date: d }
      
    end    

    # some event Wednesday
    # some event Wednesday 11am
    
    relative_day = '|today|tomorrow|tonight'
    get /^(.*)\s+(#{weekdays2+relative_day}\b)(?: \(([^\)]+)\)) (at \d{1,2}(?::\d{2})?(?:[ap]m)?)/i \
                                                           do |title, raw_date, date2, time2|
      puts ('time2: ' + time2.inspect).debug if @debug
      puts ('date2: ' + date2).debug if @debug
      puts ('raw_date: ' + raw_date).debug if @debug
      
      d = if date2 then
        Chronic.parse(date2 + ' '+ time2.to_s, now: @now)
      else
        Chronic.parse(raw_date + ' '+ time2, now: @now)
      end
      
      puts ['4'.highlight, title, raw_date, date2, time2].inspect.debug if @debug
      {title: title, date: d }
       
    end
        
    # Group meeting Red Hall 2pm-4pm on Monday (4th Dec 2017)
    get /^(.*)\s+(#{times2})(?: on) +#{weekdays}\b(?: \(([^\)]+)\))?/i \
        do |title, xtimes, raw_day, actual_date|
      
      if @debug then
        puts ('actual_date: ' + actual_date.inspect).debug
        puts ('raw_day: ' + raw_day.inspect).debug
        puts ('xtimes: ' + xtimes.inspect).debug
      end
      
      input = params[:input].clone
      
      if actual_date then
        d = Chronic.parse actual_date, now: @now
      else
        d = Chronic.parse(raw_day, now: @now)
        input.sub!(/#{weekdays}\b/i,
                   %Q(#{raw_day} (#{d.strftime("#{d.day.ordinal} %b %Y")})))        
      end

      t1, t2 = xtimes.split(/-/,2)
      
      puts ('d: ' + d.inspect).debug if @debug

      d1, d2 = [t1, t2].map {|t| Chronic.parse([d.to_date.to_s, t].join(' '), now: @now) }
            
      puts ['4.65'.highlight, input, title, raw_day, d1, d2].inspect.debug if @debug
      
      {input: input, title: title, date: d1, end_date: d2 }
      
    end          
    
    # hall 2 friday at 11am

    get /^(.*)\s+#{weekdays}\b(?: \(([^\)]+)\))?(?:#{times})? *(weekly)?/i \
        do |title, raw_day, actual_date, time, recurring|
      
      if @debug then
        puts ('recurring: ' + recurring.inspect).debug
        puts ('actual_date: ' + actual_date.inspect).debug
        puts ('raw_day: ' + raw_day.inspect).debug
        puts ('time: ' + time.inspect).debug
      end
      
      input = params[:input].clone

      d = Chronic.parse(raw_day + ' ' + time.to_s, now: @now)

      if recurring.nil?
        input.sub!(/#{weekdays}/i,
                   %Q(#{raw_day} (#{d.strftime("#{d.day.ordinal} %b %Y")})))        
      end
        
      puts ('d: ' + d.inspect).debug if @debug
      
      puts [1.7, input, title, raw_day].inspect.debug if @debug
      
      {input: input, title: title, date: d }
      
    end        
    
    
    # e.g. 21/05/2017 Forum meetup at Roundpeg from 2pm
    get /^(\d+\/\d+\/\d+)\s+(.*)(?: from|at)\s+(\d+[ap]m)/ do 
                                                    |raw_date, title, raw_time|
      
      d = Chronic.parse(raw_date + ' ' + 
                        raw_time, now: @now, :endian_precedence => :little)
      recurring = nil            
      
      puts [3, title, raw_date].inspect.debug if @debug
      { title: title, date: d }
    end        
    
    # friday hall 2 11am until 12am
    get /^#{weekdays}\s+(.*)\s+#{times} until #{times}$/i do \
        |raw_day, title, start_time, end_time|
      
      venue = title[/^at +(.*)/,1]
      d = Chronic.parse(raw_day + ' ' + start_time, now: @now)
      d2 = Chronic.parse(raw_day + ' ' + end_time, now: @now)
      
      puts ['1.44.3', title, raw_day].inspect.debug if @debug
      { title: title, date: d, end_date: d2, venue: venue }
      
    end       
    
    # friday hall 2 11am
    get /^#{weekdays}\b\s+(.*)\s+(\d+(?::\d{2})?[ap]m)$/i do \
        |raw_day, title, time|
      
      puts [raw_day, title, time].inspect if @debug
      venue = title[/^at +(.*)/,1]
      d = Chronic.parse(raw_day + ' ' + time, now: @now)
      
      puts [1.44, title, raw_day].inspect.debug if @debug
      { title: title, date: d, venue: venue }
      
    end    

    # Tuesday 10th July hall 2 at 11am
    get /#{weekdays}\b\s+#{days}\s+#{months}\s+(?:at )?(.*)\s+at\s+(#{times})/i \
        do |wday, day, month, title,  time|
      
      d = Chronic.parse([day, month, time].join(' '), now: @now)
      
      puts ['1.44.5', day, month, title].inspect.debug if @debug
      { title: title, date: d }
      
    end       
    
   
 
    
    # 27-Mar@1436 some important day
    # 25/07/2017 11pm some important day
    #
    get /^(\d+\/\d+\/\d+)\s*(\d+(?:\:\d+)?[ap]m)?\s+([^\*]+)(\*)?/ \
        do |raw_date, time, title, annualar|

      d = Chronic.parse(raw_date + ' ' + time.to_s, now: @now,
                        :endian_precedence => :little)
      recurring = nil
      
      if annualar then
        
        recurring = 'yearly'
        if d < @now then
          d = Chronic.parse(raw_date, now: Time.local(@now.year + 1, 1, 1)) 
        end
      end
      
      
      puts [3, title, raw_date, time].inspect.debug if @debug
      { title: title, date: d, recurring: recurring }
    end


    
    # Some event (10 Woodhouse Lane) 30th Nov from 9:15-17:00

    get /^(.*) #{days} #{months}(?: from)? (#{times2})/i do \
        |title, day, month, xtimes|

      t1, t2 = xtimes.split(/-/,2)

      d1 = Chronic.parse([month, day, t1].join(' '), now: @now)
      d2 = Chronic.parse([month, day, t2].join(' '), now: @now)

      puts [4.5, title, d1, d2].inspect.debug if @debug

      { title: title, date: d1, end_date: d2 }
    end
    
    # Some event (10 Woodhouse Lane) 30th Nov from 9:15-17:00

    get /^#{weekdays}\b #{months} #{days} #{times3} (.*)/i do \
        |wday, month, day, xtimes, title|

      puts [month, day, xtimes, title].inspect if @debug
      t1, t2 = xtimes.split(/-/,2)

      d1 = Chronic.parse([month, day, t1 + ':00'].join(' '), now: @now)
      d2 = Chronic.parse([month, day, t2 + ':00'].join(' '), now: @now)

      puts [4.55, title, d1, d2].inspect.debug if @debug

      { title: title, date: d1, end_date: d2 }
    end    

    # e.g. Wednesday 30th Nov at 9:15 10 Woodhouse Lane

    get /^(?:#{weekdays2}\b) #{days} #{months}(?: at)? #{times}(.*)/i do \
        |day, month, t1, title|

      d1 = Chronic.parse([month, day, t1].join(' '), now: @now)

      puts [4.6, title, d1].inspect.debug if @debug

      { title: title, date: d1 }
    end

    # Some event (10 Woodhouse Lane) 30th Nov at 9:15-10:00

    get /^(.*) #{days} #{months} #{years}(?: at)? (#{times2})/i do \
        |title, day, month, years, xtimes|

      t1, t2 = xtimes.split(/-/,2)
      puts '[title, years, day, month, t1] ' + [title, years, day, month, t1].inspect if @debug
      d1 = Chronic.parse([month, day, years, t1].join(' '), now: @now)
      d2 = Chronic.parse([month, day, years, t2].join(' '), now: @now)

      puts [4.655, title, d1].inspect.debug if @debug

      { title: title.sub(/ on$/,''), date: d1, end_date: d2 }
    end

    # Some event (10 Woodhouse Lane) 30th Nov at 9:15

    get /^(.*) #{days} #{months} #{years}(?: at)? (#{times})/i do \
        |title, day, month, years, t1|

      puts '[title, years, day, month, t1] ' + [title, years, day, month, t1].inspect if @debug
      d1 = Chronic.parse([month, day, years, t1].join(' '), now: @now)

      puts [4.66, title, d1].inspect.debug if @debug

      { title: title.sub(/ on$/,''), date: d1 }
    end
    
    # Some event (10 Woodhouse Lane) 30th Nov at 9:15-

    get /^(.*) #{days} #{months}(?: at)? (#{times})/i do \
        |title, day, month, t1|

      puts '[title, day, month, t1] ' + [title, day, month, t1].inspect if @debug
      d1 = Chronic.parse([month, day, t1].join(' '), now: @now)

      puts [4.7, title, d1].inspect.debug if @debug

      { title: title, date: d1 }
    end

    # hall 2 at 11am
    #
    get /(.*)\s+at\s+(#{times})/i do |title,  time|
      
      d = Chronic.parse(time, now: @now)
      
      puts [1.45, title].inspect.debug if @debug
      { title: title, date: d }
      
    end         
    
    
    # Council Tax on the last day of the month
    #
    get /^(.*) (?:o[nf] the)\s*last day of the month/i do |title|
      
      td = @now.to_date
      d = Date.civil(td.year, td.month, -1).to_time
      
      puts [5, title].inspect.debug if @debug
      { title: title, date: d }
      
    end        
    
    # Council Tax last day of the month
    #
    get /^(.*) +last day of the month/i do |title|
      
      td = @now.to_date
      d = Date.civil(td.year, td.month, -1).to_time
      
      puts [5.1, title].inspect.debug if @debug
      { title: title, date: d }
      
    end        
    
    # some important day 11 Oct *
    #
    get /^(.*) +(\d+) +#{months} *(\*)?/i \
        do |title, day, month, annualar|
      
      raw_date = day + ' ' + month

      d = Chronic.parse(raw_date, now: @now,
                        :endian_precedence => :little)
      recurring = nil
      
      if annualar then
        
        recurring = 'yearly'
        if d < @now then
          d = Chronic.parse(raw_date, 
                            now: Time.local(@now.year + 1, 1, 1)) 
        end
      end
      
      
      puts [6, title, raw_date].inspect.debug if @debug
      { title: title, date: d, recurring: recurring }
    end
    
    
    
    # Tuesday 3rd October gas service at Barbara's house morning 9am-1pm
    #
    get '*' do
      
      s = params[:input]
      
      time1, time2, month, weekday, day, end_date, annualar  = nil, nil, nil, 
          nil, nil, nil, false

      s2 = s.sub(/#{times}/i) {|x| time1 = x; ''}
      puts 's2: ' + s2.inspect if @debug
      s3 = s2.sub(/-(?=\d)/,'').sub(/#{times}/i) {|x| time2 = x; ''}
      s4 = s3.sub(/ *#{weekdays} */i) {|x| weekday = x; ''}
      s5 = s4.sub(/ *#{months} */i) {|x| month = x; ''}
      s6 = s5.sub(/ *#{days} */i) {|x| day = x; ''}
      s7 = s6.sub(/\*$/) {|x| annualar = true; ''}
      title = s7.strip

      raw_date = [day, month].compact.join(' ')
      raw_date = weekday if raw_date.empty?

      d = Chronic.parse(raw_date + ' ' + time1.to_s, 
                        :endian_precedence => :little, now: @now)
      
      if time2 then
        end_date = Chronic.parse(raw_date + ' ' + time2.to_s, now: @now,
                        :endian_precedence => :little)
      end
      
      recurring = nil
      
      if annualar then
        
        recurring = 'yearly'
        if d < @now then
          d = Chronic.parse(raw_date, now: Time.local(@now.year + 1, 1, 1)) 
        end
      end      
      
      puts [10, title, raw_date, time1].inspect.debug if @debug
      { title: title, date: d, end_date: end_date, recurring: recurring }
    end    
    
    
  end
  
end
