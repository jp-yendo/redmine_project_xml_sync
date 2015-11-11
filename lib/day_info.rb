class DayInfo
  attr_accessor :date
  attr_accessor :dayname
  attr_accessor :isHoliday

  def self.getDayCollection(startdate, enddate)
    result = []
    for targetindex in 0..(enddate - startdate) do
      targetdate = startdate + targetindex
      dayinfo = DayInfo::new
      dayinfo.date = targetdate
      #dayinfo.dayname = day_name(targetdate.wday) #targetdate.wday 曜日 0:日曜日〜6:土曜日)
      dayinfo.dayname = targetdate.strftime("%a")
      dayinfo.isHoliday = DayInfo.isHoliday(targetdate)
      result[targetindex] = dayinfo
    end
    return result
  end
  
  def self.getWorkdays(startdate, enddate)
    result = 0
    for targetindex in 0..(enddate - startdate) do
      targetdate = startdate + targetindex
      if DayInfo.isHoliday(targetdate) == false
        result += 1
      end
    end
    return result
  end

  def self.calcProvisionalStartDate(end_date, total_hour, day_hour)
    result = end_date
    while total_hour > day_hour
      if DayInfo.isHoliday(result) == false
        total_hour -= day_hour
      end
      result -= 1
    end
    return result
  end

  def self.calcProvisionalEndDate(start_date, total_hour, day_hour)
    result = start_date
    while total_hour > day_hour
      if DayInfo.isHoliday(result) == false
        total_hour -= day_hour
      end
      result += 1
    end
    return result
  end
  
private
  def self.isHoliday(targetdate)
    result = false

    #Redmineの休業日をまず取得
    convert_wday = [7, 1, 2, 3, 4, 5, 6]
    datecalc = Object.new
    datecalc.extend Redmine::Utils::DateCalculation
    result = datecalc.non_working_week_days.include?(convert_wday[targetdate.wday])

    #日本の祝日と論理和
    result = result | targetdate.holiday?(Setting.plugin_redmine_manage_summary['region']) 

    return result
  end
end