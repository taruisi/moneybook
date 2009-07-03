# $Id: dblib.rb 101 2009-07-02 04:38:42Z taruisi $

require 'rubygems'
require 'activerecord'

ActiveRecord::Base.establish_connection(
  :adapter => 'mysql',
  :host => 'localhost',
  :username => $Config[ 'DB_USER' ],
  :password => $Config[ 'DB_PASSWORD' ],
  :database => $Config[ 'DB_NAME' ],
  :encoding => 'utf8',
  :socket   => '/var/run/mysqld/mysqld.sock'
)

# updated_at の自動更新をしないようにする。(そこまでするなら、updated_at なんてカラム名を使わなきゃいいのだけれど…)
ActiveRecord::Base.record_timestamps = false

class Alias < ActiveRecord::Base
  belongs_to :user

  def self.check_maddr( s )
    find( :first, :conditions => [ "mailaddress = ?", s ] )
  end

  def self.create( user, m )
    if a=check_maddr( m ) then
      return a
    else
      al = Alias.new
      al.user = user
      al.mailaddress = m
      al.save
    end
  end
end

# ユーザクラス
#   目下のところは、メールアドレスのみを保持。
class User < ActiveRecord::Base
  has_many :sections
  has_many :items
  has_many :aliases

  # メールアドレスチェック。メールアドレスを入力にして、対応するユーザオブジェクトを返す。
  # つまりは、単純なSELECT。
  def self.check_maddr( s )
    ret=find(:first, :conditions => [ "mailaddress = ?", s ] )
    unless ret then
      ret=Alias.check_maddr( s )
      if ret then
        ret = ret.user
      end
    end
    return ret
  end

  # メールアドレスから、ユーザオブジェクトを作成する。
  # 重複ユーザを登録しないように、事前にチェックして、
  # あれば、それをそのまま返却する。ない場合に、初めて作成する。
  def self.create( m )
    if u=check_maddr( m ) then
      return u
    else
      us = User.new
      us.mailaddress = m
      us.save
    end
  end
end

# セクションクラス（いわゆる摘要？）
#   Userに属する形。1:n
class Section < ActiveRecord::Base
  belongs_to :user
  has_many   :items

  # 指定された名前のセクションが対象のユーザ用として登録されているかチェックする。
  # 入力は、Userオブジェクトと、セクション名。
  def self.check_section( u, n )
    un = Kconv.toutf8( n.split(',').shift )
    find( :first, :conditions => [ "name = ? and user_id = ?", un, u ] )
 end

  # 指定されたユーザに対応づけられたセクションの一覧を配列で取得する。
  # 入力は、Userオブジェクト。
  def self.collect_all( user )
    find( :all, :conditions => [ "user_id = ?", user ] )
  end

  def self.modify_by_options( s, aopt )
    return false if /BLOG/=~s.name
    modified = false
    aopt.each do |opt|
      if /^(type|(oneaday|one)|sum|(ofs|offset)|unit|total|def(ault)*)\=.+/=~ opt then
        aopt=opt.split('=')
        case( aopt[0] )
          when /^unit/
            s.unit   = Kconv.toutf8(aopt[1].strip)
            s.total  = false unless s.unit=~/円/  # unitが後ろに来たときのオーバーライドはやめさせたい。
            modified = true
          when /^type/
            s.vtype = $VTypeR[ aopt[1].capitalize.to_sym ]
            s.vtype = $VTypeR[ :Integer ] unless s.vtype
            modified = true
          when /^one/
            s.oneaday=true  if /(t|true)/=~ aopt[1]
            s.oneaday=false if /(f|false)/=~aopt[1]
            modified = true
          when /^sum/
            s.sum    =true  if /(t|true)/=~ aopt[1]
            s.sum    =false if /(f|false)/=~aopt[1]
            modified = true
          when /^(ofs|offset)/
            if /^\-?([0-9]+)([dh])?$/=~aopt[1] then
              s.offset = aopt[1].to_i
              tunit = $2
              if tunit then
                s.offset *= 60*60
                s.offset *= 24 if tunit=="d"
              end
              modified = true
            end
          when /^total/
            s.total  =true  if /(t|true)/=~ aopt[1]
            s.total  =false if /(f|false)/=~aopt[1]
            modified = true
        end
      end
    end
    return modified
  end

  def self.modify_by_section( s )
    case( s.name )
      when /体重/
        s.unit    = "Kg"
        s.vtype   = $VTypeR[ :Float ]
        s.oneaday = true
        s.sum     = false
        s.offset  = 0
        s.total   = false
      when /体脂肪/
        s.unit    = "％"
        s.vtype   = $VTypeR[ :Float ]
        s.oneaday = true
        s.sum     = false
        s.offset  = 0
        s.total   = false
      when /歩数/
        s.unit    = "歩"
        s.vtype   = $VTypeR[ :Integer ]
        s.oneaday = true
        s.sum     = false
        s.offset  = -24*60*60
        s.total   = false
      when /BLOG/
        s.unit    = ""
        s.vtype   = $VTypeR[ :String ]
        s.oneaday = false
        s.sum     = false
        s.offset  = 0
        s.total   = false
      when /((朝|夕|昼)食|(筋|脳)トレ)/
        s.unit    = ""
        s.vtype   = $VTypeR[ :String ]
        s.oneaday = true
        s.sum     = false
        s.offset  = 0
        s.total   = false
      else
        s.unit    = "円"
        s.vtype   = $VTypeR[ :Integer ]
        s.oneaday = false
        s.sum     = true
        s.offset  = 0
        s.total   = true
     end
     return s
  end

  # セクションの作成メソッド。
  # 重複しないように、チェックしたうえで、ない場合のみ作成する。
  # 復帰オブジェクトは、Sectionオブジェクトそのもの。（実際には先頭の１オブジェクト）
  def self.create( u, s )
    asec = s.split(',')
    sname = Kconv.toutf8( asec.shift )
    if ret=check_section( u, sname ) then
  # 前の unit フィールドがないテーブルに unit を拡張した時のための考慮。
      if (ret.unit==""||ret.unit==nil) then
        modify_by_section( ret )
        modify_by_options( ret, asec )
        ret.save
      else
        ret.save if modify_by_options( ret, asec )
      end
      return ret
    else
      sec = Section.new
      sec.name    = sname
      sec.user    = u
      modify_by_section( sec )
      modify_by_options( sec, asec )
      sec.save
      return sec
    end
  end
end

# アイテムクラス（一つ一つの項目）
#   UserとSectionに属する。
class Item < ActiveRecord::Base
  belongs_to :user
  belongs_to :section

  # 項目毎の金額の合計を計算する。SQLで一発。該当するアイテムがなければ、０を通知する。
  def self.summation( u, s, t )
    if t.class==Array then
      lt=time_period_max(t)
    else
      lt=time_period(t)
    end
    r = find_by_sql( [ "select sum(price) as price from items where user_id = ? and section_id = ? and updated_at >= ?", u, s, lt ] )
    if r[0].price then
      return r[0].price
    else
      return 0
    end
  end

  def self.find_recent( u, s )
    r = find_by_sql( [ "select * from items where user_id = ? and section_id = ? order by updated_at desc limit 1", u, s ] )
    return r[0]
  end

  # アイテムの登録。重複することはないので、チェックはせずに作成。
  # 入力は、値段、ユーザオブジェクト、セクションオブジェクト、時刻(デフォルトは現在)
  def self.create( p, u, s, t=Time.now, c=nil )
  # あらかじめ section の offset を加算しておく。
    t += s.offset
    if s.oneaday then
      tdy = Time.local( t.year, t.month, t.day, 0, 0, 0 )
      i=find( :first, :conditions => [ "section_id = ? and user_id = ? and updated_at>= ?", s, u, tdy ] )
      i=Item.new unless i
    else
      i=Item.new
    end
    i.price, i.user, i.section, i.updated_at = p, u, s, t
    i.comment = Kconv.toutf8(c) if c
    i.save
    return i
  end

  # 配列で一括設定する。セクションも、なければ登録する。（冗長？）
  # とりあえず、トランザクションしてみる。
  def self.set_items( u, items, t=Time.now )
    ActiveRecord::Base::transaction() do
      items.each do |i|
#        unless sec=Section.check_section( u, i[0] ) then
        sec = Section.create( u, i[0] )
#        end
        if i[1]>0 || $VType[sec.vtype]==:String then
          it = Item.create( i[1], u, sec, t, i[2] )
        end
      end
    end
  end

  # 最も大きいIdをSQLで求める。基本はSQLで一発。
  def self.newest_id( u )
    return find_by_sql( [ "select max(id) as id from items where user_id = ?", u ] )[0].id
  end

  # 最も大きいIdを持つアイテムオブジェクトを削除する。
  # Idを求めるメソッドがあるので、直接Destroy。
  # 復帰値は、削除した項目と、値段。
  def self.delete_newest( u )
    i = self.newest_id( u )
    it = Item.find( i )
    return nil unless it
    ret = [ it.section.name, it.price.to_i ]
    Item.destroy( i )
    return ret
  end

  # 指定したシンボルで対応する起点の時間を通知する。
  # 今のところ、 summation メソッドで利用するのみ。
  # :all または 対応していないシンボルの場合は、EPOCを返却。
  def self.time_period( s )
    lt = Time.now
    case( s )
      when :today
        return Time.local( lt.year, lt.month, lt.mday, 0, 0, 0 )
      when :this_week
        return Time.local( lt.year, lt.month, lt.mday, 0, 0, 0 ) - lt.wday*60*60*24
      when :seven_days
        return Time.local( lt.year, lt.month, lt.mday, 0, 0, 0 ) - 7*60*60*24
      when :this_month
        return Time.local( lt.year, lt.month, 1, 0, 0, 0 )
      when :this_year
        return Time.local( lt.year, 1, 1, 0, 0, 0 )
      when :all
        return (lt-lt.to_i)
      else
        return (lt-lt.to_i)
    end
  end

  def self.time_period_max( sa )
    return sa.map{ |s| time_period( s ) }.max
  end

  # 一定日時からの項目を列挙し、文字列化するメソッド
  # SQLで一発。
  def self.enumeration( u, t )
    if t.class==Array then
      lt=time_period_max(t)
    else
      lt=time_period(t)
    end
    return find_by_sql( [ "select * from items where user_id = ? and updated_at >= ? order by updated_at desc", u, lt ] )
  end

end

class Limit < ActiveRecord::Base
  belongs_to :user
  belongs_to :section

  #
  def self.create( p, u, sec, t=Time.now )
    l=Limit.new
    l.price, l.user, l.section, l.updated_at = p, u, s, t
    l.save
    return l
  end

  # 配列で予算を一括設定する。セクションは、なければ登録しない。
  # 合計という値があれば、Sectionはnilで登録する。
  # とりあえず、トランザクションしてみる。
  def self.set_items( u, items )
    ActiveRecord::Base::transaction() do
      items.each do |i|
        if i[0] then
          if sec=Section.check_section( u, i[0] ) then
            sec = Section.create( u, i[0] )
          else
            sec=nil
            i[1]==0
          end
        else
          sec=nil
        end
        if i[1]>0 then
          lm = Limit.create( i[1], u, sec )
        end
      end
    end
  end
=begin
  def self.collect_all( u )
    s = find( :all, :conditions => [ "user_id = ?", user ] )
    ret = Array.new
    s.each do |s|
      r = find( :first, [ "user_id = ? and section_id = ? order by id desc", u, s ] )
      ret << [ r.section.name, 
    end
    return find_by_sql( [ "select max(id) as id from items where user_id = ?", u ] )[0].id
  end
=end
end
