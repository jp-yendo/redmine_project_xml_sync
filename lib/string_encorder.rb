class StringEncorder
  MAP_CHAR = [
    {:utf8 => "\u301C", :sjis => "\uFF5E"}, #～（ウェーブダッシュ）
    {:utf8 => "\u2212", :sjis => "\uFF0D"}, #－（全角マイナス）
    {:utf8 => "\u00A2", :sjis => "\uFFE0"}, #￠（セント）
    {:utf8 => "\u00A3", :sjis => "\uFFE1"}, #￡（ポンド）
    {:utf8 => "\u00AC", :sjis => "\uFFE2"}, #￢（ノット）
    {:utf8 => "\u2014", :sjis => "\u2015"}, #―（全角マイナスより少し幅のある文字）
    {:utf8 => "\u2016", :sjis => "\u2225"} #∥（半角パイプが2つ並んだような文字）
  ]
  
  def self.convert_utf8_to_sjis(utf8)
    result = utf8
    MAP_CHAR.each do |map|
      result = result.gsub(map[:utf8], map[:sjis].to_s)
    end
    return result.encode(Encoding::SJIS)
  end

  def self.convert_sjis_to_utf8(sjis)
    result = sjis
    MAP_CHAR.each do |map|
      result = result.gsub(map[:sjis], map[:utf8].to_s)
    end
    return result.encode(Encoding::UTF_8)
  end
end
